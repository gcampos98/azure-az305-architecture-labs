#!/usr/bin/env bash
# Configuración y funciones del Laboratorio 01B. No se ejecuta directamente.
# Las variables definidas aquí las usan los scripts que cargan este archivo.
# shellcheck disable=SC2034
set -Eeuo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_TAG="az305-lab01b"
STATE_VARS=(SUFFIX RG_PREFIX LOC_PRI LOC_DR VM_SIZE VM_IMAGE STG_SKU VAULT_REDUNDANCY
  LTR_DAILY LTR_WEEKLY LTR_MONTHLY LTR_YEARLY TFO_RPO BACKUP_JOB RP_NAME RESTORE_JOB)
# shellcheck source=../../shared/common.sh
source "$LAB_DIR/../shared/common.sh"

MARKER_PATH="/var/lib/az305-lab/marker.txt"
ASR_API="2025-01-01"
export MARKER_PATH

load_config() {
  load_state
  : "${RG_PREFIX:=rg-az305-1b}"
  : "${LOC_PRI:=eastus}"
  : "${LOC_DR:=westus2}"
  # Site Recovery exige al menos 2 vCPU y no admite Arm64 (por eso no se usa B1s)
  : "${VM_SIZE:=Standard_B2ats_v2}"
  : "${VM_IMAGE:=Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest}"
  : "${VM_ADMIN:=azureuser}"
  : "${STG_SKU:=Standard_GZRS}"
  : "${VAULT_REDUNDANCY:=GeoRedundant}"
  : "${ENABLE_CRR:=false}"
  : "${LTR_DAILY:=30}"
  : "${LTR_WEEKLY:=12}"
  : "${LTR_MONTHLY:=12}"
  : "${LTR_YEARLY:=3}"
  : "${TFO_RPO:=}"
  : "${BACKUP_JOB:=}"
  : "${RP_NAME:=}"
  : "${RESTORE_JOB:=}"
  RG_PRI="$RG_PREFIX-pri"          # Origen: VM, red, vault de Backup, storage
  RG_DR="$RG_PREFIX-dr"            # Destino: vault de Site Recovery, redes y réplicas
  RG_RESTORE="$RG_PREFIX-restore"  # Discos restaurados desde Azure Backup
}

set_names() {
  VM_NAME="vm-az305-1b-$SUFFIX"
  ST_CACHE="st1bcache$SUFFIX"      # LRS: caché de ASR y staging de restauración
  ST_GEO="st1bgeo$SUFFIX"          # GZRS: demostración de redundancia geográfica
  BKP_VAULT="rsv-1b-bkp-$SUFFIX"
  ASR_VAULT="rsv-1b-asr-$SUFFIX"
  LAW_NAME="law-az305-1b-$SUFFIX"
  POLICY_NAME="pol-vm-ltr"
  FAB_SRC="fab-$LOC_PRI"
  FAB_DR="fab-$LOC_DR"
  CONT_SRC="cont-$LOC_PRI"
  CONT_DR="cont-$LOC_DR"
  ASR_POLICY="pol-asr-24h"
  MAP_CONT="map-cont-forward"
  MAP_NET="map-net-forward"
  NET_ASR="azureNetwork"           # Nombre fijo que usa Site Recovery para redes de Azure
  ITEM_ARGS=(-g "$RG_DR" --vault-name "$ASR_VAULT" --fabric-name "$FAB_SRC"
    --protection-container "$CONT_SRC")
}

# Carga el despliegue existente (para pruebas)
require_deployment() {
  load_config
  recover_suffix "$RG_PRI"
  [[ -n "${SUFFIX:-}" ]] || die "No hay despliegue. Ejecuta primero ./scripts/01-deploy.sh"
  set_names
}

require_extension() {
  az extension show --name site-recovery -o none 2>/dev/null ||
    az extension add --name site-recovery --only-show-errors -o none
}

# --- Site Recovery -------------------------------------------------------------
asr_item_count() {
  az site-recovery protected-item list "${ITEM_ARGS[@]}" \
    --query "length([?name=='$VM_NAME'])" -o tsv
}

# asr_prop <JMESPath>
asr_prop() {
  az site-recovery protected-item show "${ITEM_ARGS[@]}" -n "$VM_NAME" --query "$1" -o tsv
}

asr_allows() { # operación
  local n
  n="$(asr_prop "length(properties.allowedOperations[?@=='$1'] || \`[]\`)")" || return 1
  [[ "$n" != "0" && -n "$n" ]]
}

asr_test_state() {
  local s
  s="$(asr_prop "properties.testFailoverState")" || return 1
  printf '%s' "${s:-None}"
}

asr_item_id() { asr_prop id; }

# asr_post <acción> <cuerpo JSON>: operaciones que la extensión de CLI no incluye (API REST)
asr_post() {
  local id
  id="$(asr_item_id)"
  [[ -n "$id" ]] || die "No se encontró el elemento replicado."
  az rest --method post \
    --url "https://management.azure.com$id/$1?api-version=$ASR_API" \
    --body "$2" -o none
}

asr_latest_job() { # escenario campo
  az site-recovery job list -g "$RG_DR" --vault-name "$ASR_VAULT" \
    --query "sort_by([?properties.scenarioName=='$1'], &properties.startTime)[-1].$2" -o tsv
}

# --- Azure Backup --------------------------------------------------------------
backup_item_count() {
  az backup item list -g "$RG_PRI" -v "$BKP_VAULT" \
    --backup-management-type AzureIaasVM --workload-type VM \
    --query "length([?properties.friendlyName=='$VM_NAME'])" -o tsv
}

job_status() { # id del trabajo de Backup
  az backup job show -g "$RG_PRI" -v "$BKP_VAULT" -n "$1" --query properties.status -o tsv
}

# 0 = terminó bien; 1 = sigue en curso; termina el script si el trabajo falló
job_done() {
  local status
  status="$(job_status "$1")" || return 1
  case "$status" in
    Completed|CompletedWithWarnings) return 0 ;;
    Failed|Cancelled) die "El trabajo $1 terminó en estado $status. Revisa: az backup job show -g $RG_PRI -v $BKP_VAULT -n $1" ;;
    *) return 1 ;;
  esac
}

# run_in_vm <grupo> <vm> <script>: ejecuta un script en la VM y devuelve su salida
run_in_vm() {
  az vm run-command invoke -g "$1" -n "$2" --command-id RunShellScript \
    --scripts "$3" --query "value[0].message" -o tsv
}
