#!/usr/bin/env bash
# Elimina el Laboratorio 01B en el orden que exige Azure y verifica el resultado.
# Uso: ./scripts/03-cleanup.sh [--yes | --verify]
# shellcheck source=00-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

: "${DEL_POLLS:=60}"
: "${DEL_WAIT:=30}"

MODE="${1:-}"
case "$MODE" in ""|--yes|--verify) ;; *) die "Uso: $0 [--yes | --verify]" ;; esac

require_login
load_config
recover_suffix "$RG_PRI"
recover_suffix "$RG_DR"
[[ -z "${SUFFIX:-}" ]] || set_names
GROUPS_LAB=("$RG_RESTORE" "$RG_DR" "$RG_PRI")

# count_is_zero <comando az que devuelve un número>
count_is_zero() {
  local n
  n="$("$@")" || return 1
  [[ "$n" == "0" ]]
}

vault_count() { # grupo vault
  az backup vault list -g "$1" --query "length([?name=='$2'])" -o tsv
}

# --- 1. Site Recovery ----------------------------------------------------------
child_count() { # comando de lista (sin --query) ... ; nombre en $CHILD
  "$@" --query "length([?name=='$CHILD'])" -o tsv
}

# remove_child <descripción> <nombre> -- <lista...> -- <borrado...>
remove_child() {
  local desc="$1" CHILD="$2" list=() del=()
  shift 3
  while [[ "$1" != "--" ]]; do list+=("$1"); shift; done
  shift
  del=("$@")
  query child_count "${list[@]}" || return 0
  [[ "$QUERY" != "0" ]] || return 0
  info "Eliminando $desc $CHILD"
  if ! "${del[@]}" -o none; then fail "No se pudo eliminar $desc $CHILD."; return 0; fi
  wait_until "eliminación de $desc" "$DEL_POLLS" "$DEL_WAIT" count_is_zero child_count "${list[@]}" ||
    fail "$desc $CHILD sigue presente."
}

test_cleanup_done() { asr_allows TestFailover; }

teardown_asr() {
  own_rg "$RG_DR" || return 0
  query vault_count "$RG_DR" "$ASR_VAULT" || return 0
  [[ "$QUERY" != "0" ]] || return 0
  require_extension
  log "1. Site Recovery: desactivar la replicación y desmontar el vault"
  local v=(-g "$RG_DR" --vault-name "$ASR_VAULT")
  query az site-recovery fabric list "${v[@]}" --query "[].name" -o tsv || return 0
  local fabrics="$QUERY"

  if grep -qx "$FAB_SRC" <<<"$fabrics"; then
    query az site-recovery protection-container list "${v[@]}" --fabric-name "$FAB_SRC" \
      --query "[].name" -o tsv || return 0
    if grep -qx "$CONT_SRC" <<<"$QUERY"; then
      query asr_item_count || return 0
      if [[ "$QUERY" != "0" ]]; then
        if asr_allows TestFailoverCleanup; then
          info "Limpiando un Test Failover pendiente"
          asr_post testFailoverCleanup '{"properties":{"comments":"Limpieza del laboratorio"}}' ||
            fail "No se pudo limpiar el Test Failover."
          wait_until "limpieza del Test Failover" "$DEL_POLLS" "$DEL_WAIT" test_cleanup_done ||
            fail "El Test Failover sigue pendiente."
        fi
        info "Desactivando la replicación de $VM_NAME"
        az site-recovery protected-item remove "${ITEM_ARGS[@]}" -n "$VM_NAME" -o none ||
          fail "No se pudo desactivar la replicación."
        if ! wait_until "fin de la replicación" "$DEL_POLLS" "$DEL_WAIT" count_is_zero asr_item_count; then
          fail "La replicación sigue activa; no se desmonta el resto de Site Recovery."
          return 0
        fi
      fi
      remove_child "el mapeo de contenedores" "$MAP_CONT" -- \
        az site-recovery protection-container mapping list "${v[@]}" --fabric-name "$FAB_SRC" \
        --protection-container "$CONT_SRC" -- \
        az site-recovery protection-container mapping remove "${v[@]}" --fabric-name "$FAB_SRC" \
        --protection-container "$CONT_SRC" -n "$MAP_CONT" --provider-input "{instance-type:A2A}"
    fi
    remove_child "el mapeo de red" "$MAP_NET" -- \
      az site-recovery network mapping list "${v[@]}" --fabric-name "$FAB_SRC" \
      --network-name "$NET_ASR" -- \
      az site-recovery network mapping delete "${v[@]}" --fabric-name "$FAB_SRC" \
      --network-name "$NET_ASR" -n "$MAP_NET" --yes
  fi

  local pair fabric container
  for pair in "$FAB_SRC:$CONT_SRC" "$FAB_DR:$CONT_DR"; do
    fabric="${pair%%:*}"
    container="${pair##*:}"
    grep -qx "$fabric" <<<"$fabrics" || continue
    remove_child "el contenedor" "$container" -- \
      az site-recovery protection-container list "${v[@]}" --fabric-name "$fabric" -- \
      az site-recovery protection-container remove "${v[@]}" --fabric-name "$fabric" -n "$container"
    remove_child "el fabric" "$fabric" -- \
      az site-recovery fabric list "${v[@]}" -- \
      az site-recovery fabric remove "${v[@]}" -n "$fabric"
  done
  remove_child "la directiva de replicación" "$ASR_POLICY" -- \
    az site-recovery policy list "${v[@]}" -- \
    az site-recovery policy delete "${v[@]}" -n "$ASR_POLICY" --yes
  az backup vault delete -g "$RG_DR" -n "$ASR_VAULT" --yes -o none ||
    fail "No se pudo eliminar el vault $ASR_VAULT."
}

# --- 2. Azure Backup -----------------------------------------------------------
# Elementos protegidos que todavía no están en soft delete
active_backup_items() {
  az backup item list -g "$RG_PRI" -v "$BKP_VAULT" \
    --backup-management-type AzureIaasVM --workload-type VM -o tsv \
    --query "length([?properties.friendlyName=='$VM_NAME' && !(properties.isScheduledForDeferredDelete)])"
}

# Si el vault no se puede borrar, elimina el resto del grupo para detener los costos
drain_primary_group() {
  local pass id
  info "Eliminando los demás recursos de $RG_PRI para detener sus costos"
  for pass in 1 2 3; do
    query az resource list -g "$RG_PRI" -o tsv \
      --query "[?type!='Microsoft.RecoveryServices/vaults'].id" || return 0
    [[ -n "$QUERY" ]] || return 0
    info "Pasada $pass"
    while read -r id; do
      [[ -n "$id" ]] || continue
      # Las dependencias pueden requerir otra pasada; el resultado se verifica al final
      az resource delete --ids "$id" -o none 2>/dev/null || true
    done <<<"$QUERY"
  done
}

restore_point_collections() {
  az resource list --resource-type Microsoft.Compute/restorePointCollections -o tsv \
    --query "[?starts_with(name, 'AzureBackup_${VM_NAME}_')].id"
}

teardown_backup() {
  own_rg "$RG_PRI" || return 0
  query vault_count "$RG_PRI" "$BKP_VAULT" || return 0
  if [[ "$QUERY" != "0" ]]; then
    log "2. Azure Backup: detener la protección y borrar los respaldos"
    query active_backup_items || return 0
    if [[ "$QUERY" != "0" ]]; then
      az backup protection disable -g "$RG_PRI" -v "$BKP_VAULT" -c "$VM_NAME" -i "$VM_NAME" \
        --backup-management-type AzureIaasVM --workload-type VM \
        --delete-backup-data true --yes -o none ||
        fail "No se pudo detener la protección de $VM_NAME."
    fi
  fi
  # Instantáneas de restauración instantánea (quedan en un grupo AzureBackupRG_*)
  if query restore_point_collections && [[ -n "$QUERY" ]]; then
    local id
    while read -r id; do
      [[ -n "$id" ]] || continue
      az resource delete --ids "$id" -o none || fail "No se pudo eliminar ${id##*/}."
    done <<<"$QUERY"
  fi
  query vault_count "$RG_PRI" "$BKP_VAULT" || return 0
  if [[ "$QUERY" != "0" ]]; then
    if ! az backup vault delete -g "$RG_PRI" -n "$BKP_VAULT" --yes -o none; then
      fail "No se pudo eliminar $BKP_VAULT (posible soft delete). Reintenta cuando venza la retención."
      drain_primary_group
    fi
  fi
}

if [[ "$MODE" != "--verify" ]]; then
  confirm_delete "$MODE" "${GROUPS_LAB[@]}"
  if [[ -n "${SUFFIX:-}" ]]; then
    teardown_asr
    teardown_backup
    if own_rg "$RG_PRI"; then
      if query az monitor log-analytics workspace list -g "$RG_PRI" \
        --query "length([?name=='$LAW_NAME'])" -o tsv && [[ "$QUERY" != "0" ]]; then
        az monitor log-analytics workspace delete -g "$RG_PRI" -n "$LAW_NAME" --force true --yes -o none ||
          fail "No se pudo eliminar $LAW_NAME."
      fi
    fi
  fi
  log "3. Grupos de recursos"
  for RG in "${GROUPS_LAB[@]}"; do
    if own_rg "$RG"; then
      info "Eliminando $RG"
      az group delete -n "$RG" --yes --no-wait || fail "No se pudo solicitar el borrado de $RG."
    fi
  done
fi

log "4. Verificación"
all_gone() { pending_groups "${GROUPS_LAB[@]}"; ((${#PENDING[@]} == 0)); }
if [[ "$MODE" == "--verify" ]]; then
  pending_groups "${GROUPS_LAB[@]}"
else
  wait_until "borrado de los grupos" "$DEL_POLLS" "$DEL_WAIT" all_gone || true
fi
for RG in "${PENDING[@]}"; do
  fail "El grupo $RG todavía existe."
  query az resource list -g "$RG" --query "[].{Nombre:name, Tipo:type}" -o table && printf '%s\n' "$QUERY"
done
if [[ -n "${SUFFIX:-}" ]]; then
  if query restore_point_collections && [[ -n "$QUERY" ]]; then
    fail "Quedan colecciones de puntos de restauración de $VM_NAME (generan costo)."
  fi
fi

if ((FAILURES > 0)); then
  die "Limpieza INCOMPLETA ($FAILURES avisos). El estado se conserva; repite más tarde: $0 --verify"
fi
rm -f "$ENV_FILE"
log "Limpieza verificada: no quedan grupos del laboratorio 01B"
info "Azure Backup conserva los datos borrados en soft delete durante el periodo de retención."
