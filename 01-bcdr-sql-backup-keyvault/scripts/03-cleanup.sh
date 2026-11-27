#!/usr/bin/env bash
# Elimina el Laboratorio 01 y verifica el resultado. Se puede ejecutar varias veces.
# Uso: ./scripts/03-cleanup.sh [--yes | --verify]
#   (sin opción) pide confirmación    --yes no pregunta    --verify solo comprueba, no borra
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

MODE="${1:-}"
case "$MODE" in ""|--yes|--verify) ;; *) die "Opción no válida: $MODE" ;; esac
require_login
load_config
GROUPS_LAB=("$RG_RESTORE" "$RG_SEC" "$RG_PRI")   # El primario al final: el vault puede retenerlo
FAILURES=0

fail() { warn "$*"; FAILURES=$((FAILURES + 1)); }

# query <comando az...>: guarda la salida en QUERY; si falla, lo registra
query() {
  if ! QUERY="$("$@")"; then fail "Falló la consulta: $*"; QUERY=""; return 1; fi
}

delete_failover_groups() {
  local rg server servers fog
  for rg in "$RG_PRI" "$RG_SEC"; do
    rg_exists "$rg" || continue
    query az sql server list -g "$rg" --query "[].name" -o tsv || continue
    servers="$QUERY"
    for server in $servers; do
      # El grupo se borra desde el servidor que hoy es primario
      query az sql failover-group list -g "$rg" -s "$server" \
        --query "[?replicationRole=='Primary'].name" -o tsv || continue
      for fog in $QUERY; do
        info "Eliminando $fog (primario: $server)"
        az sql failover-group delete -g "$rg" -s "$server" -n "$fog" -o none ||
          fail "No se pudo eliminar $fog"
      done
    done
  done
}

delete_all_but_vaults() {
  local pass id
  for pass in 1 2 3 4; do   # varias pasadas por las dependencias entre recursos
    query az resource list -g "$RG_PRI" \
      --query "[?type!='Microsoft.RecoveryServices/vaults'].id" -o tsv || return 0
    [[ -n "$QUERY" ]] || return 0
    info "Pasada $pass"
    for id in $QUERY; do
      az resource delete --ids "$id" -o none 2>/dev/null || true
    done
  done
}

delete_vaults() {
  rg_exists "$RG_PRI" || return 0
  query az backup vault list -g "$RG_PRI" --query "[].name" -o tsv || return 0
  local vaults="$QUERY" vault item blocked=false
  for vault in $vaults; do
    if query az backup item list -g "$RG_PRI" -v "$vault" --backup-management-type AzureIaasVM --workload-type VM \
        --query "[?!(properties.isScheduledForDeferredDelete)].properties.friendlyName" -o tsv; then
      for item in $QUERY; do
        info "Deteniendo la protección de $item y borrando sus respaldos (quedan en soft delete)"
        az backup protection disable -g "$RG_PRI" -v "$vault" -c "$item" -i "$item" \
          --backup-management-type AzureIaasVM --delete-backup-data true --yes -o none ||
          fail "No se pudo detener la protección de $item"
      done
    fi
    info "Eliminando vault $vault"
    if ! az backup vault delete -g "$RG_PRI" -n "$vault" --yes -o none; then
      fail "El vault $vault no se pudo eliminar (habitualmente por elementos en soft delete)."
      blocked=true
    fi
  done
  if [[ "$blocked" == "true" ]]; then
    warn "Se eliminarán los demás recursos de $RG_PRI para detener costos."
    delete_all_but_vaults
  fi
}

delete_workspaces() {
  rg_exists "$RG_PRI" || return 0
  query az monitor log-analytics workspace list -g "$RG_PRI" --query "[].name" -o tsv || return 0
  local law
  for law in $QUERY; do
    az monitor log-analytics workspace delete -g "$RG_PRI" -n "$law" --force true --yes -o none ||
      fail "No se pudo eliminar el workspace $law"
  done
}

pending_groups() {
  PENDING=()
  local rg
  for rg in "${GROUPS_LAB[@]}"; do
    if rg_exists "$rg"; then PENDING+=("$rg"); fi
  done
}

if [[ "$MODE" != "--verify" ]]; then
  if [[ "$MODE" != "--yes" ]]; then
    echo "Suscripción: $(az account show --query name -o tsv)"
    echo "Se eliminarán: ${GROUPS_LAB[*]}"
    read -r -p "Escribe BORRAR para continuar: " answer
    [[ "$answer" == "BORRAR" ]] || die "Cancelado."
  fi
  log "1. Exportación del Activity Log"
  if exists az monitor diagnostic-settings subscription show --name "$ACTIVITY_DS_NAME"; then
    az monitor diagnostic-settings subscription delete --name "$ACTIVITY_DS_NAME" --yes -o none ||
      fail "No se pudo eliminar $ACTIVITY_DS_NAME"
  fi
  log "2. Failover Group";          delete_failover_groups
  log "3. Backup y Recovery Vault"; delete_vaults
  log "4. Log Analytics";           delete_workspaces
  log "5. Grupos de recursos"
  for rg in "${GROUPS_LAB[@]}"; do
    if rg_exists "$rg"; then
      az group delete -n "$rg" --yes --no-wait || fail "No se pudo solicitar el borrado de $rg"
    fi
  done
fi

log "6. Verificando grupos de recursos"
pending_groups
if [[ "$MODE" != "--verify" ]]; then
  for i in $(seq 1 "${VERIFY_RETRIES:-30}"); do
    [[ ${#PENDING[@]} -eq 0 ]] && break
    info "Pendientes ($i): ${PENDING[*]}"
    sleep "${VERIFY_WAIT:-30}"
    pending_groups
  done
fi

log "7. Key Vaults en soft delete"
if query az keyvault list-deleted --resource-type vault \
    --query "[?contains(properties.vaultId, '/resourceGroups/rg-az305-bcdr-')].name" -o tsv; then
  for kv in $QUERY; do
    if [[ "$MODE" == "--verify" ]]; then fail "Sigue en soft delete: $kv"
    else
      info "Purgando $kv"
      az keyvault purge --name "$kv" -o none || fail "No se pudo purgar $kv"
    fi
  done
fi

if query az group list --query "[?starts_with(name, 'AzureBackupRG_')].name" -o tsv && [[ -n "$QUERY" ]]; then
  warn "Revisa si estos grupos creados por Azure Backup pertenecen al lab: $QUERY"
fi

if [[ ${#PENDING[@]} -gt 0 ]]; then
  for rg in "${PENDING[@]}"; do
    warn "Aún existe $rg:"
    az resource list -g "$rg" --query "[].{Nombre:name, Tipo:type}" -o table || true
  done
  die "LIMPIEZA INCOMPLETA. Comprueba más tarde con '--verify'. Si queda un vault con soft delete, repite la limpieza al vencer la retención."
fi
if [[ $FAILURES -gt 0 ]]; then
  die "Los grupos ya no existen, pero hubo $FAILURES aviso(s). Revísalos antes de dar la limpieza por cerrada."
fi
rm -f "$ENV_FILE"
log "LIMPIEZA COMPLETADA Y VERIFICADA"
