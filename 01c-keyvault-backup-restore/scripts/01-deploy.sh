#!/usr/bin/env bash
# Despliega el Laboratorio 01C: dos Key Vault, un secreto y una clave con dos versiones.
# Es idempotente.
# shellcheck source=00-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

require_login
command -v openssl >/dev/null || die "No se encontró openssl."
load_config
recover_suffix "$RG_PRI"
if [[ -z "${SUFFIX:-}" ]]; then SUFFIX="$(new_suffix)"; fi
set_names
save_state
load_identity

log "1. Proveedores, grupos de recursos y Log Analytics (sufijo $SUFFIX)"
for ns in Microsoft.KeyVault Microsoft.OperationalInsights Microsoft.Insights; do
  az provider register --namespace "$ns" --wait -o none
done
ensure_rg "$RG_PRI" "$LOC_PRI"
ensure_rg "$RG_DR" "$LOC_DR"
exists az monitor log-analytics workspace show -g "$RG_PRI" -n "$LAW_NAME" ||
  az monitor log-analytics workspace create -g "$RG_PRI" -n "$LAW_NAME" -l "$LOC_PRI" -o none
LAW_ID="$(az monitor log-analytics workspace show -g "$RG_PRI" -n "$LAW_NAME" --query id -o tsv)"

log "2. Key Vault Standard en $LOC_PRI (origen) y $LOC_DR (recuperación)"
ensure_vault "$RG_PRI" "$KV_PRI" "$LOC_PRI"
ensure_vault "$RG_DR" "$KV_DR" "$LOC_DR"

log "3. Auditoría y roles RBAC (la propagación puede tardar unos minutos)"
for pair in "$RG_PRI:$KV_PRI" "$RG_DR:$KV_DR"; do
  KV_ID="$(az keyvault show -g "${pair%%:*}" -n "${pair##*:}" --query id -o tsv)"
  az monitor diagnostic-settings create --name diag-law --resource "$KV_ID" \
    --workspace "$LAW_ID" --export-to-resource-specific true \
    --logs '[{"category":"AuditEvent","enabled":true}]' -o none
  grant_data_access "${pair%%:*}" "${pair##*:}"
done

log "4. Secreto y clave en el vault de origen (dos versiones de cada uno)"
umask 077
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VERSIONS="$(version_ids secret "$KV_PRI" "$SECRET_NAME")"
for ((i = $(count_lines "$VERSIONS"); i < 2; i++)); do
  # El valor es ficticio y aleatorio; se pasa por archivo para que no aparezca en el historial
  printf 'Server=demo;Password=%s' "$(openssl rand -hex 16)" >"$TMP_DIR/value"
  az keyvault secret set --vault-name "$KV_PRI" -n "$SECRET_NAME" \
    --file "$TMP_DIR/value" --encoding utf-8 -o none
  info "Nueva versión del secreto $SECRET_NAME"
done

VERSIONS="$(version_ids key "$KV_PRI" "$KEY_NAME")"
for ((i = $(count_lines "$VERSIONS"); i < 2; i++)); do
  az keyvault key create --vault-name "$KV_PRI" -n "$KEY_NAME" --kty RSA --size 2048 -o none
  info "Nueva versión de la clave $KEY_NAME"
done

log "Despliegue completo"
cat <<MSG
  Respaldo y restauración:  ./scripts/02-test.sh backup-restore
  Verificación:             ./scripts/02-test.sh verify
  Al terminar:              ./scripts/03-cleanup.sh
MSG
