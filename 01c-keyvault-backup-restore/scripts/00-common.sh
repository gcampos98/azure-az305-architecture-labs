#!/usr/bin/env bash
# Configuración y funciones del Laboratorio 01C. No se ejecuta directamente.
# Las variables definidas aquí las usan los scripts que cargan este archivo.
# shellcheck disable=SC2034
set -Eeuo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_TAG="az305-lab01c"
STATE_VARS=(SUFFIX RG_PREFIX LOC_PRI LOC_DR LOC_FOREIGN)
# shellcheck source=../../shared/common.sh
source "$LAB_DIR/../shared/common.sh"

SECRET_NAME="db-connection-string"
KEY_NAME="cmk-app"

load_config() {
  load_state
  : "${RG_PREFIX:=rg-az305-1c}"
  : "${LOC_PRI:=eastus}"
  : "${LOC_DR:=westus2}"          # Misma geografía de Azure (Estados Unidos)
  : "${LOC_FOREIGN:=brazilsouth}"  # Otra geografía, solo para la prueba negativa
  RG_PRI="$RG_PREFIX-pri"
  RG_DR="$RG_PREFIX-dr"
}

set_names() {
  KV_PRI="kv1c-pri-$SUFFIX"
  KV_DR="kv1c-dr-$SUFFIX"
  KV_GEO="kv1c-geo-$SUFFIX"
  LAW_NAME="law-az305-1c-$SUFFIX"
}

require_deployment() {
  load_config
  recover_suffix "$RG_PRI"
  [[ -n "${SUFFIX:-}" ]] || die "No hay despliegue. Ejecuta primero ./scripts/01-deploy.sh"
  set_names
}

# ensure_vault <grupo> <nombre> <región>
ensure_vault() {
  local deleted
  if ! exists az keyvault show -g "$1" -n "$2"; then
    deleted="$(az keyvault list-deleted --resource-type vault --query "length([?name=='$2'])" -o tsv)"
    [[ "$deleted" == "0" ]] ||
      die "El nombre $2 está en soft delete. Púrgalo (az keyvault purge -n $2) o usa otro SUFFIX."
    az keyvault create -g "$1" -n "$2" -l "$3" --sku standard \
      --enable-rbac-authorization true --retention-days 7 \
      --tags "lab=$LAB_TAG" -o none
  fi
}

# Asigna los roles de datos mínimos y espera a que se propaguen
grant_data_access() { # grupo vault
  local id
  id="$(az keyvault show -g "$1" -n "$2" --query id -o tsv)"
  assign_role "Key Vault Secrets Officer" "$id"
  assign_role "Key Vault Crypto Officer" "$id"
  retry 20 15 az keyvault secret list --vault-name "$2" -o none
  retry 20 15 az keyvault key list --vault-name "$2" -o none
}

# version_ids <secret|key> <vault> <nombre>: identificadores de versión, ordenados
version_ids() {
  local out count field="id"
  [[ "$1" == "key" ]] && field="kid"
  count="$(az keyvault "$1" list --vault-name "$2" --query "length([?name=='$3'])" -o tsv)" ||
    return 1
  [[ "$count" != "0" ]] || return 0
  out="$(az keyvault "$1" list-versions --vault-name "$2" -n "$3" --query "[].$field" -o tsv)" ||
    return 1
  [[ -z "$out" ]] || sed 's#.*/##' <<<"$out" | sort
}

count_lines() { if [[ -z "$1" ]]; then echo 0; else wc -l <<<"$1" | tr -d ' '; fi; }
