#!/usr/bin/env bash
# Pruebas del Laboratorio 01B. Uso: ./scripts/02-test.sh <subcomando>
# shellcheck source=00-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

: "${ASR_POLLS:=60}"
: "${ASR_WAIT:=30}"
: "${JOB_POLLS:=120}"
: "${JOB_WAIT:=60}"

usage() {
  cat <<'MSG'
Uso: ./scripts/02-test.sh <subcomando>
  status             Estado de la replicación y del respaldo
  test-failover      Test Failover a la red aislada y verificación del marcador
  failover-cleanup   Elimina la VM de prueba del Test Failover
  backup [--no-wait] Respaldo bajo demanda
  backup-status      Estado del último respaldo
  simulate-delete    Borra el archivo marcador (simula un error humano)
  restore            Restaura el disco desde el punto de recuperación anterior al borrado
  recover-file       Recupera el archivo desde el disco restaurado
  redundancy         Evidencia de redundancia y retención LTR
MSG
}

marker_value() { printf 'AZ305-1B-%s-dato-critico' "$SUFFIX"; }

marker_in() { # grupo vm
  local out
  out="$(run_in_vm "$1" "$2" "cat $MARKER_PATH 2>/dev/null || echo MARCADOR_AUSENTE")" || return 1
  grep -qF "$(marker_value)" <<<"$out"
}

# --- Site Recovery -------------------------------------------------------------
require_item() {
  local n
  n="$(asr_item_count)"
  [[ "$n" != "0" && -n "$n" ]] || die "La replicación no está configurada. Ejecuta 01-deploy.sh."
}

asr_report() {
  az site-recovery protected-item show "${ITEM_ARGS[@]}" -n "$VM_NAME" -o yaml \
    --query "{VM:name, Estado:properties.protectionState, Salud:properties.replicationHealth, TestFailover:properties.testFailoverState, RPO_segundos:properties.providerSpecificDetails.rpoInSeconds, UltimoCalculoRPO:properties.providerSpecificDetails.lastRpoCalculatedTime, OperacionesPermitidas:properties.allowedOperations}"
}

test_status() {
  log "Site Recovery ($LOC_PRI -> $LOC_DR)"
  if [[ "$(asr_item_count)" == "0" ]]; then
    info "Sin elemento replicado."
  elif asr_allows TestFailover; then
    save_evidence 01-asr-replication.txt asr_report
    info "La replicación está lista para el Test Failover."
  else
    asr_report
    info "Aún no se permite Test Failover. Vuelve a consultar en unos minutos."
    info "Si el estado indica error: az site-recovery job list -g $RG_DR --vault-name $ASR_VAULT -o table"
  fi
  log "Azure Backup"
  az backup item list -g "$RG_PRI" -v "$BKP_VAULT" \
    --backup-management-type AzureIaasVM --workload-type VM -o table \
    --query "[].{VM:properties.friendlyName, Proteccion:properties.protectionState, UltimoRespaldo:properties.lastBackupStatus}"
}

test_vm_name() { az vm list -g "$RG_DR" --query "[0].name" -o tsv; }

# Listo cuando Site Recovery espera confirmación o el trabajo terminó bien y hay VM
failover_ready() {
  local state job status
  state="$(asr_test_state)" || return 1
  [[ "$state" == "WaitingForCompletion" ]] && return 0
  job="$(asr_latest_job TestFailover name)" || return 1
  [[ -n "$job" && "$job" != "None" && "$job" != "$PREV_JOB" ]] || return 1
  status="$(asr_latest_job TestFailover properties.state)" || return 1
  case "$status" in
    Failed|Cancelled) die "El Test Failover terminó en estado $status. Revisa el trabajo $job en el vault $ASR_VAULT." ;;
    Succeeded) [[ -n "$(test_vm_name)" ]] ;;
    *) return 1 ;;
  esac
}

job_duration() { # segundos entre inicio y fin del último trabajo de Test Failover
  local start end
  start="$(asr_latest_job TestFailover properties.startTime)"
  end="$(asr_latest_job TestFailover properties.endTime)"
  python3 - "$start" "$end" <<'PY'
import re, sys
from datetime import datetime

def parse(value):
    # Azure puede devolver 7 decimales; Python admite 6
    value = re.sub(r"(\.\d{6})\d+", r"\1", value.replace("Z", "+00:00"))
    return datetime.fromisoformat(value)

try:
    print(int((parse(sys.argv[2]) - parse(sys.argv[1])).total_seconds()))
except ValueError:
    print("no disponible")
PY
}

test_failover() {
  require_item
  PREV_JOB=""
  if [[ "$(asr_test_state)" == "WaitingForCompletion" ]]; then
    info "Ya hay un Test Failover pendiente de limpieza; solo se verifica."
  elif [[ "$(asr_latest_job TestFailover properties.state)" == "InProgress" ]]; then
    info "Ya hay un Test Failover en curso; se espera ese trabajo."
  else
    asr_allows TestFailover || die "La replicación aún no permite Test Failover. Revisa: ./scripts/02-test.sh status"
    TFO_RPO="$(asr_prop properties.providerSpecificDetails.rpoInSeconds)"
    save_state
    PREV_JOB="$(asr_latest_job TestFailover name)"
    local net_id
    net_id="$(az network vnet show -g "$RG_DR" -n vnet-test --query id -o tsv)"
    log "Iniciando Test Failover hacia la red aislada vnet-test"
    asr_post testFailover "{\"properties\":{\"failoverDirection\":\"PrimaryToRecovery\",\"networkType\":\"VmNetworkAsInput\",\"networkId\":\"$net_id\",\"providerSpecificDetails\":{\"instanceType\":\"A2A\"}}}"
  fi
  wait_until "Test Failover" "$ASR_POLLS" "$ASR_WAIT" failover_ready ||
    die "Se agotó la espera. Repite este subcommando para continuar."
  local vm nic subnet
  vm="$(test_vm_name)"
  [[ -n "$vm" ]] || die "No se encontró la VM de prueba en $RG_DR."
  nic="$(az vm show -g "$RG_DR" -n "$vm" --query "networkProfile.networkInterfaces[0].id" -o tsv)"
  subnet="$(az network nic show --ids "$nic" --query "ipConfigurations[0].subnet.id" -o tsv)"
  [[ "$subnet" == */virtualNetworks/vnet-test/* ]] || die "La VM de prueba no está en la red aislada: $subnet"
  info "Verificando el archivo marcador dentro de $vm"
  wait_until "agente de la VM de prueba" 20 "$ASR_WAIT" marker_in "$RG_DR" "$vm" ||
    die "No se pudo verificar el marcador en $vm. No ejecutes failover-cleanup hasta revisarlo."
  FAILOVER_VM="$vm"
  save_evidence 02-test-failover.txt failover_report
  info "Cuando termines de revisar: ./scripts/02-test.sh failover-cleanup"
}

failover_report() {
  cat <<MSG
Prueba: Site Recovery Test Failover (Azure a Azure)
Origen: $LOC_PRI   Destino: $LOC_DR
VM de prueba: $FAILOVER_VM
Red aislada (vnet-test): sí
Archivo marcador presente en la VM de prueba: sí
RPO informado antes de la prueba (segundos): ${TFO_RPO:-no registrado}
Duración del trabajo de Test Failover según Azure (segundos): $(job_duration)
MSG
}

cleanup_done() {
  local count
  count="$(az vm list -g "$RG_DR" --query "length(@)" -o tsv)" || return 1
  [[ "$count" == "0" ]] && asr_allows TestFailover
}

test_failover_cleanup() {
  require_item
  local vm
  vm="$(test_vm_name)"
  if asr_allows TestFailoverCleanup; then
    log "Limpiando el Test Failover"
    asr_post testFailoverCleanup '{"properties":{"comments":"Prueba revisada (laboratorio AZ-305 01B)"}}'
  elif [[ -z "$vm" ]]; then
    info "No hay Test Failover pendiente."
    return 0
  fi
  wait_until "limpieza del Test Failover" "$ASR_POLLS" "$ASR_WAIT" cleanup_done ||
    die "Se agotó la espera. Repite este subcomando."
  save_evidence 03-test-failover-cleanup.txt printf \
    'VM de prueba eliminada: sí\nLa replicación sigue activa y permite un nuevo Test Failover: sí\n'
}

# --- Azure Backup --------------------------------------------------------------
latest_backup_job() {
  az backup job list -g "$RG_PRI" -v "$BKP_VAULT" -o tsv \
    --query "sort_by([?properties.operation=='Backup' && properties.entityFriendlyName=='$VM_NAME'], &properties.startTime)[-1].name"
}

backup_report() {
  az backup job show -g "$RG_PRI" -v "$BKP_VAULT" -n "$BACKUP_JOB" -o yaml \
    --query "{Operacion:properties.operation, VM:properties.entityFriendlyName, Estado:properties.status, Inicio:properties.startTime, Fin:properties.endTime, Duracion:properties.duration}"
  echo "Puntos de recuperación:"
  az backup recoverypoint list -g "$RG_PRI" -v "$BKP_VAULT" -c "$VM_NAME" -i "$VM_NAME" \
    --backup-management-type AzureIaasVM --workload-type VM -o table \
    --query "[].{Hora:properties.recoveryPointTime, Consistencia:properties.recoveryPointType}"
}

test_backup() {
  local status=""
  [[ -z "$BACKUP_JOB" ]] || status="$(job_status "$BACKUP_JOB")"
  if [[ "$status" != "InProgress" ]]; then
    local latest
    latest="$(latest_backup_job)"
    if [[ -n "$latest" && "$latest" != "None" && "$(job_status "$latest")" == "InProgress" ]]; then
      info "Ya hay un respaldo en curso; se usa ese trabajo."
      BACKUP_JOB="$latest"
    else
      log "Respaldo bajo demanda"
      BACKUP_JOB="$(az backup protection backup-now -g "$RG_PRI" -v "$BKP_VAULT" \
        -c "$VM_NAME" -i "$VM_NAME" --backup-management-type AzureIaasVM \
        --retain-until "$(date -u -d '+30 days' +%d-%m-%Y)" --query name -o tsv)"
    fi
    save_state
  fi
  if [[ "${1:-}" == "--no-wait" ]]; then
    info "Trabajo $BACKUP_JOB en curso. Consulta: ./scripts/02-test.sh backup-status"
    return 0
  fi
  wait_until "respaldo" "$JOB_POLLS" "$JOB_WAIT" job_done "$BACKUP_JOB" ||
    die "El respaldo sigue en curso. Consulta más tarde: ./scripts/02-test.sh backup-status"
  save_evidence 04-backup-job.txt backup_report
}

test_backup_status() {
  if [[ -z "$BACKUP_JOB" ]]; then
    BACKUP_JOB="$(latest_backup_job)"
    [[ -n "$BACKUP_JOB" && "$BACKUP_JOB" != "None" ]] || die "No hay trabajos de respaldo."
    save_state
  fi
  if job_done "$BACKUP_JOB"; then
    save_evidence 04-backup-job.txt backup_report
  else
    backup_report
    info "El trabajo sigue en curso."
  fi
}

test_simulate_delete() {
  [[ -n "$BACKUP_JOB" ]] || die "Primero ejecuta: ./scripts/02-test.sh backup"
  job_done "$BACKUP_JOB" || die "El respaldo aún no termina; no borres datos todavía."
  if [[ -z "$RP_NAME" ]]; then
    marker_in "$RG_PRI" "$VM_NAME" || die "El marcador no está en la VM; no hay nada que proteger."
    RP_NAME="$(az backup recoverypoint list -g "$RG_PRI" -v "$BKP_VAULT" -c "$VM_NAME" -i "$VM_NAME" \
      --backup-management-type AzureIaasVM --workload-type VM -o tsv \
      --query "sort_by(@, &properties.recoveryPointTime)[-1].name")"
    [[ -n "$RP_NAME" && "$RP_NAME" != "None" ]] || die "No hay puntos de recuperación."
    save_state
  fi
  log "Simulando borrado accidental en la VM"
  local output
  output="$(run_in_vm "$RG_PRI" "$VM_NAME" \
    "rm -f $MARKER_PATH && sync; [ -e $MARKER_PATH ] && echo PRESENTE || echo MARCADOR_AUSENTE")"
  # Se exige la confirmación explícita: una salida vacía no demuestra el borrado
  grep -q MARCADOR_AUSENTE <<<"$output" || die "No se pudo confirmar el borrado del marcador."
  save_evidence 05-simulated-deletion.txt printf \
    'Archivo marcador eliminado en la VM de origen: sí\nPunto de recuperación anterior al borrado fijado: sí\nNota: Site Recovery replica también los borrados; la recuperación se hace con Azure Backup.\n'
}

restore_report() {
  az backup job show -g "$RG_PRI" -v "$BKP_VAULT" -n "$RESTORE_JOB" -o yaml \
    --query "{Operacion:properties.operation, VM:properties.entityFriendlyName, Estado:properties.status, Inicio:properties.startTime, Fin:properties.endTime, Duracion:properties.duration}"
}

test_restore() {
  [[ -n "$RP_NAME" ]] || die "Primero ejecuta: ./scripts/02-test.sh simulate-delete"
  if [[ -n "$RESTORE_JOB" ]]; then
    case "$(job_status "$RESTORE_JOB")" in
      Failed|Cancelled) info "La restauración anterior falló; se reintenta."; RESTORE_JOB="" ;;
    esac
  fi
  if [[ -z "$RESTORE_JOB" ]]; then
    log "Restaurando discos en $RG_RESTORE"
    ensure_rg "$RG_RESTORE" "$LOC_PRI"
    RESTORE_JOB="$(az backup restore restore-disks -g "$RG_PRI" -v "$BKP_VAULT" \
      -c "$VM_NAME" -i "$VM_NAME" --rp-name "$RP_NAME" \
      --storage-account "$ST_CACHE" --storage-account-resource-group "$RG_PRI" \
      --target-resource-group "$RG_RESTORE" --query name -o tsv)"
    save_state
  fi
  wait_until "restauración" "$JOB_POLLS" "$JOB_WAIT" job_done "$RESTORE_JOB" ||
    die "La restauración sigue en curso. Repite este subcomando."
  save_evidence 06-restore-job.txt restore_report
}

detach_disk() {
  [[ -n "${ATTACHED_DISK:-}" ]] || return 0
  if az vm disk detach -g "$RG_PRI" --vm-name "$VM_NAME" --name "$ATTACHED_DISK" -o none; then
    ATTACHED_DISK=""
  else
    warn "No se pudo desconectar $ATTACHED_DISK de la VM. Hazlo antes de reiniciarla."
  fi
}

test_recover_file() {
  [[ -n "$RESTORE_JOB" ]] || die "Primero ejecuta: ./scripts/02-test.sh restore"
  job_done "$RESTORE_JOB" || die "La restauración aún no termina."
  local disk name attached output remote
  disk="$(az disk list -g "$RG_RESTORE" -o tsv \
    --query "sort_by([?osType=='Linux'], &timeCreated)[-1].id")"
  [[ -n "$disk" && "$disk" != "None" ]] || die "No se encontró el disco restaurado en $RG_RESTORE."
  name="${disk##*/}"
  attached="$(az vm show -g "$RG_PRI" -n "$VM_NAME" -o tsv \
    --query "length(storageProfile.dataDisks[?name=='$name'])")"
  if [[ "$attached" == "0" ]]; then
    log "Conectando el disco restaurado como disco de datos (solo lectura al montar)"
    az vm disk attach -g "$RG_PRI" --vm-name "$VM_NAME" --name "$disk" --lun 5 -o none
  fi
  ATTACHED_DISK="$name"
  trap detach_disk EXIT
  # Heredoc entre comillas: nada se expande en Cloud Shell; solo se antepone MARKER
  remote="MARKER=$MARKER_PATH
$(cat <<'REMOTE'
set -e
BASE=/dev/disk/azure/scsi1/lun5
for i in $(seq 1 30); do ls ${BASE}-part* >/dev/null 2>&1 && break; sleep 2; done
mkdir -p /mnt/restore
DEV=
for part in ${BASE}-part*; do
  mount -o ro,noload "$part" /mnt/restore 2>/dev/null || continue
  if [ -e "/mnt/restore$MARKER" ]; then DEV=$part; break; fi
  umount /mnt/restore
done
[ -n "$DEV" ] || { echo "No se encontró una partición con $MARKER" >&2; exit 1; }
trap 'umount /mnt/restore' EXIT
mkdir -p "$(dirname "$MARKER")"
cp -p "/mnt/restore$MARKER" "$MARKER"
sync
cat "$MARKER"
REMOTE
)"
  output="$(run_in_vm "$RG_PRI" "$VM_NAME" "$remote")"
  detach_disk
  trap - EXIT
  if ! grep -qF "$(marker_value)" <<<"$output" || ! marker_in "$RG_PRI" "$VM_NAME"; then
    printf '%s\n' "$output" >&2
    die "El archivo no se recuperó."
  fi
  save_evidence 07-file-recovery.txt printf \
    'Archivo recuperado desde el disco restaurado: sí\nContenido igual al marcador original: sí\nDisco restaurado desconectado de la VM: %s\n' \
    "$([[ -z "${ATTACHED_DISK:-}" ]] && echo sí || echo no)"
}

# --- Redundancia y retención ---------------------------------------------------
redundancy_report() {
  echo "## Storage Account de demostración"
  if [[ "$STG_SKU" == *RAGRS || "$STG_SKU" == *RAGZRS ]]; then
    az storage account show -g "$RG_PRI" -n "$ST_GEO" --expand geoReplicationStats -o yaml \
      --query "{SKU:sku.name, Primaria:primaryLocation, Secundaria:secondaryLocation, GeoEstado:geoReplicationStats.status, UltimaSincronizacion:geoReplicationStats.lastSyncTime}"
  else
    az storage account show -g "$RG_PRI" -n "$ST_GEO" -o yaml \
      --query "{SKU:sku.name, Primaria:primaryLocation, Secundaria:secondaryLocation}"
  fi
  echo "## Redundancia del vault de Backup"
  az backup vault backup-properties show -g "$RG_PRI" -n "$BKP_VAULT" -o yaml \
    --query "[0].properties.{Redundancia:storageModelType, RestauracionEntreRegiones:crossRegionRestoreFlag}"
  echo "## Directiva LTR"
  az backup policy show -g "$RG_PRI" -v "$BKP_VAULT" -n "$POLICY_NAME" -o yaml \
    --query "{Directiva:name, Diaria_dias:properties.retentionPolicy.dailySchedule.retentionDuration.count, Semanal_semanas:properties.retentionPolicy.weeklySchedule.retentionDuration.count, Mensual_meses:properties.retentionPolicy.monthlySchedule.retentionDuration.count, Anual_anios:properties.retentionPolicy.yearlySchedule.retentionDuration.count}"
}

test_redundancy() {
  save_evidence 08-redundancy-ltr.txt redundancy_report
  # Copia de la directiva (sin identificadores) en la cuenta geo-redundante
  local tmp
  tmp="$(mktemp)"
  az backup policy show -g "$RG_PRI" -v "$BKP_VAULT" -n "$POLICY_NAME" -o json | sanitize >"$tmp"
  retry 6 20 az storage blob upload --account-name "$ST_GEO" --container-name config-backup \
    --name "$POLICY_NAME.json" --file "$tmp" --auth-mode login --overwrite -o none
  rm -f "$tmp"
  info "Directiva exportada a $ST_GEO/config-backup/$POLICY_NAME.json"
}

CMD="${1:-}"
case "$CMD" in
  status|test-failover|failover-cleanup|backup|backup-status|simulate-delete|restore|recover-file|redundancy) ;;
  *) usage; exit 1 ;;
esac

require_login
require_extension
require_deployment

case "$CMD" in
  status) test_status ;;
  test-failover) test_failover ;;
  failover-cleanup) test_failover_cleanup ;;
  backup) test_backup "${2:-}" ;;
  backup-status) test_backup_status ;;
  simulate-delete) test_simulate_delete ;;
  restore) test_restore ;;
  recover-file) test_recover_file ;;
  redundancy) test_redundancy ;;
esac
