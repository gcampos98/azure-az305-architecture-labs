#!/usr/bin/env bash
# Elimina y purga el Laboratorio 01C y verifica el resultado.
# Uso: ./scripts/03-cleanup.sh [--yes | --verify]
# shellcheck source=00-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

: "${DEL_POLLS:=60}"
: "${DEL_WAIT:=20}"

MODE="${1:-}"
case "$MODE" in ""|--yes|--verify) ;; *) die "Uso: $0 [--yes | --verify]" ;; esac

require_login
load_config
recover_suffix "$RG_PRI"
recover_suffix "$RG_DR"
[[ -z "${SUFFIX:-}" ]] || set_names
GROUPS_LAB=("$RG_DR" "$RG_PRI")

deleted_count() { # vault
  az keyvault list-deleted --resource-type vault --query "length([?name=='$1'])" -o tsv
}

# remove_vault <grupo> <vault> <región>: borra y purga un Key Vault
remove_vault() {
  if own_rg "$1"; then
    if query az keyvault list -g "$1" --query "length([?name=='$2'])" -o tsv && [[ "$QUERY" != "0" ]]; then
      info "Eliminando $2"
      az keyvault delete -g "$1" -n "$2" -o none || fail "No se pudo eliminar $2."
    fi
  fi
  if query deleted_count "$2" && [[ "$QUERY" != "0" ]]; then
    info "Purgando $2"
    az keyvault purge -n "$2" --location "$3" -o none || fail "No se pudo purgar $2."
  fi
}

if [[ "$MODE" != "--verify" ]]; then
  confirm_delete "$MODE" "${GROUPS_LAB[@]}"
  if [[ -n "${SUFFIX:-}" ]]; then
    log "1. Eliminar y purgar los Key Vault"
    remove_vault "$RG_PRI" "$KV_PRI" "$LOC_PRI"
    remove_vault "$RG_DR" "$KV_DR" "$LOC_DR"
    remove_vault "$RG_DR" "$KV_GEO" "$LOC_FOREIGN"
    if own_rg "$RG_PRI"; then
      if query az monitor log-analytics workspace list -g "$RG_PRI" \
        --query "length([?name=='$LAW_NAME'])" -o tsv && [[ "$QUERY" != "0" ]]; then
        az monitor log-analytics workspace delete -g "$RG_PRI" -n "$LAW_NAME" --force true --yes -o none ||
          fail "No se pudo eliminar $LAW_NAME."
      fi
    fi
  fi
  log "2. Grupos de recursos"
  for RG in "${GROUPS_LAB[@]}"; do
    if own_rg "$RG"; then
      info "Eliminando $RG"
      az group delete -n "$RG" --yes --no-wait || fail "No se pudo solicitar el borrado de $RG."
    fi
  done
fi

log "3. Verificación"
all_gone() { pending_groups "${GROUPS_LAB[@]}"; ((${#PENDING[@]} == 0)); }
if [[ "$MODE" == "--verify" ]]; then
  pending_groups "${GROUPS_LAB[@]}"
else
  wait_until "borrado de los grupos" "$DEL_POLLS" "$DEL_WAIT" all_gone || true
fi
for RG in "${PENDING[@]}"; do fail "El grupo $RG todavía existe."; done
if [[ -n "${SUFFIX:-}" ]]; then
  for KV in "$KV_PRI" "$KV_DR" "$KV_GEO"; do
    if query deleted_count "$KV" && [[ "$QUERY" != "0" ]]; then
      fail "$KV sigue en soft delete (sin purgar)."
    fi
  done
fi

if ((FAILURES > 0)); then
  die "Limpieza INCOMPLETA ($FAILURES avisos). El estado se conserva; repite más tarde: $0 --verify"
fi
rm -f "$ENV_FILE"
log "Limpieza verificada: no quedan grupos ni Key Vault del laboratorio 01C"
