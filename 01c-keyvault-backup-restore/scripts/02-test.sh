#!/usr/bin/env bash
# Pruebas del Laboratorio 01C. Uso: ./scripts/02-test.sh <subcomando>
# shellcheck source=00-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

usage() {
  cat <<'MSG'
Uso: ./scripts/02-test.sh <subcomando>
  backup-restore  Respalda el secreto y la clave y los restaura en la segunda región
  verify          Comprueba versiones, valor del secreto y descifrado con la clave restaurada
  independence    Demuestra que la copia restaurada no se sincroniza con el origen
  cross-geo       Prueba negativa: restaurar en otra geografía debe fallar
  all             backup-restore, verify, independence y cross-geo
  reset-dr        Borra y purga los objetos restaurados para repetir la restauración
MSG
}

TMP_DIR=""
make_tmp() {
  [[ -n "$TMP_DIR" ]] && return 0
  umask 077
  TMP_DIR="$(mktemp -d)"
  # Los archivos de respaldo se eliminan siempre, incluso si el script falla
  trap 'rm -rf "$TMP_DIR"' EXIT
}

backup_object() { # secret|key nombre archivo
  rm -f "$3"
  az keyvault "$1" backup --vault-name "$KV_PRI" -n "$2" --file "$3" -o none
  [[ -s "$3" ]] || die "El respaldo de $2 salió vacío."
}

# --- Respaldo y restauración ---------------------------------------------------
restore_one() { # secret|key nombre
  local source_ids target_ids file extra
  source_ids="$(version_ids "$1" "$KV_PRI" "$2")"
  [[ -n "$source_ids" ]] || die "No existe $2 en $KV_PRI."
  target_ids="$(version_ids "$1" "$KV_DR" "$2")"
  if [[ -n "$target_ids" ]]; then
    extra="$(comm -13 <(printf '%s\n' "$source_ids") <(printf '%s\n' "$target_ids"))"
    [[ -z "$extra" ]] ||
      die "$2 ya existe en $KV_DR con versiones ajenas al origen. Ejecuta reset-dr."
    info "$1 $2: ya está restaurado ($(count_lines "$target_ids") versiones); no se sobrescribe."
    RESULTS+="$1 $2: restaurado en una ejecución anterior"$'\n'
    return 0
  fi
  file="$TMP_DIR/$1.bak"
  backup_object "$1" "$2" "$file"
  retry 6 20 az keyvault "$1" restore --vault-name "$KV_DR" --file "$file" -o none
  target_ids="$(version_ids "$1" "$KV_DR" "$2")"
  [[ "$source_ids" == "$target_ids" ]] || die "Las versiones restauradas de $2 no coinciden."
  RESULTS+="$1 $2: respaldo cifrado de $(wc -c <"$file" | tr -d ' ') bytes; restauradas $(count_lines "$target_ids") versiones"$'\n'
  rm -f "$file"
}

backup_restore_report() {
  printf 'Origen: %s (%s)\nDestino: %s (%s)\n' "$KV_PRI" "$LOC_PRI" "$KV_DR" "$LOC_DR"
  printf '%s' "$RESULTS"
  printf 'Archivos de respaldo locales eliminados: sí\n'
}

test_backup_restore() {
  log "Respaldo en $LOC_PRI y restauración en $LOC_DR"
  make_tmp
  RESULTS=""
  restore_one secret "$SECRET_NAME"
  restore_one key "$KEY_NAME"
  save_evidence 01-backup-restore.txt backup_restore_report
}

# --- Verificación --------------------------------------------------------------
secret_hash() { # vault versión; el valor nunca se muestra
  az keyvault secret show --vault-name "$1" -n "$SECRET_NAME" --version "$2" \
    --query value -o tsv | sha256sum | cut -d' ' -f1
}

test_verify() {
  log "Verificación de los objetos restaurados"
  local ids version hash_pri hash_dr plain cipher decrypted total
  RESULTS=""

  ids="$(version_ids secret "$KV_DR" "$SECRET_NAME")"
  [[ -n "$ids" ]] || die "No hay secreto restaurado. Ejecuta backup-restore."
  total=0
  for version in $ids; do
    hash_pri="$(secret_hash "$KV_PRI" "$version")"
    hash_dr="$(secret_hash "$KV_DR" "$version")"
    [[ "$hash_pri" == "$hash_dr" ]] || die "El secreto difiere en la versión $version."
    total=$((total + 1))
  done
  RESULTS+="Secreto: $total versiones con el mismo identificador y el mismo SHA-256: sí"$'\n'

  ids="$(version_ids key "$KV_DR" "$KEY_NAME")"
  [[ -n "$ids" ]] || die "No hay clave restaurada. Ejecuta backup-restore."
  plain="prueba-az305-$SUFFIX"
  total=0
  for version in $ids; do
    # Cifrar con la clave de origen y descifrar con la restaurada (misma versión)
    cipher="$(az keyvault key encrypt --vault-name "$KV_PRI" -n "$KEY_NAME" --version "$version" \
      --algorithm RSA-OAEP-256 --value "$plain" --data-type plaintext --query result -o tsv)"
    decrypted="$(az keyvault key decrypt --vault-name "$KV_DR" -n "$KEY_NAME" --version "$version" \
      --algorithm RSA-OAEP-256 --value "$cipher" --data-type base64 --query result -o tsv)"
    [[ "$decrypted" == "$(printf '%s' "$plain" | base64 -w0)" ]] ||
      die "La clave restaurada no descifra la versión $version."
    total=$((total + 1))
  done
  RESULTS+="Clave: $total versiones; lo cifrado en origen se descifra en destino: sí"$'\n'
  save_evidence 02-verification.txt printf '%s' "$RESULTS"
}

test_independence() {
  log "Independencia entre origen y copia restaurada"
  make_tmp
  local before after pri
  before="$(version_ids secret "$KV_DR" "$SECRET_NAME")"
  [[ -n "$before" ]] || die "Primero ejecuta backup-restore."
  printf 'Server=demo;Password=%s' "$(openssl rand -hex 16)" >"$TMP_DIR/value"
  az keyvault secret set --vault-name "$KV_PRI" -n "$SECRET_NAME" \
    --file "$TMP_DIR/value" --encoding utf-8 -o none
  rm -f "$TMP_DIR/value"
  pri="$(version_ids secret "$KV_PRI" "$SECRET_NAME")"
  after="$(version_ids secret "$KV_DR" "$SECRET_NAME")"
  [[ "$before" == "$after" ]] || die "El destino cambió: no es lo esperado."
  (($(count_lines "$pri") > $(count_lines "$after"))) || die "El origen no registró la nueva versión."
  save_evidence 03-independence.txt printf \
    'Se creó una versión nueva del secreto en el origen.\nVersiones en origen: %s\nVersiones en destino: %s\nLa copia restaurada no se sincroniza (no es replicación): sí\n' \
    "$(count_lines "$pri")" "$(count_lines "$after")"
}

# --- Prueba negativa entre geografías ------------------------------------------
test_cross_geo() {
  log "Prueba negativa: restaurar en $LOC_FOREIGN (otra geografía)"
  make_tmp
  load_identity
  ensure_rg "$RG_DR" "$LOC_DR"
  ensure_vault "$RG_DR" "$KV_GEO" "$LOC_FOREIGN"
  grant_data_access "$RG_DR" "$KV_GEO"
  # Control: una escritura correcta demuestra que un fallo posterior no es por permisos
  retry 6 20 az keyvault secret set --vault-name "$KV_GEO" -n control-rbac --value ok -o none
  local found file="$TMP_DIR/cross.bak" err="$TMP_DIR/cross.err"
  found="$(version_ids secret "$KV_GEO" "$SECRET_NAME")"
  [[ -z "$found" ]] ||
    die "$KV_GEO ya contiene $SECRET_NAME; ejecuta 03-cleanup.sh o revisa el vault."

  backup_object secret "$SECRET_NAME" "$file"
  if az keyvault secret restore --vault-name "$KV_GEO" --file "$file" -o none 2>"$err"; then
    die "INESPERADO: la restauración entre geografías funcionó. Revisa las regiones configuradas."
  fi
  # Un error de permisos, firewall o red no demuestra la regla de geografía
  if grep -qiE 'ForbiddenByRbac|ForbiddenByPolicy|ForbiddenByFirewall|AuthorizationFailed|Unauthorized|timed out|ConnectionError|Max retries' "$err"; then
    sanitize <"$err" >&2
    die "La restauración falló por permisos o red: la prueba no es válida. Repite más tarde."
  fi
  found="$(version_ids secret "$KV_GEO" "$SECRET_NAME")"
  [[ -z "$found" ]] || die "El secreto aparece en $KV_GEO pese al error."
  CROSS_ERROR="$(head -c 800 "$err")"
  save_evidence 04-cross-geography.txt cross_report
  rm -f "$file" "$err"
}

cross_report() {
  cat <<MSG
Origen: $LOC_PRI   Intento de destino: $LOC_FOREIGN
Escritura de control en el destino (permisos correctos): sí
Restauración rechazada: sí
Secreto presente en el destino: no
Mensaje devuelto por Azure:
$CROSS_ERROR
MSG
}

# --- Repetir la restauración ---------------------------------------------------
dr_deleted_count() { # secret|key nombre
  az keyvault "$1" list-deleted --vault-name "$KV_DR" --query "length([?name=='$2'])" -o tsv
}

is_deleted() { local n; n="$(dr_deleted_count "$@")" || return 1; [[ "$n" != "0" ]]; }
is_purged() { local n; n="$(dr_deleted_count "$@")" || return 1; [[ "$n" == "0" ]]; }

reset_one() { # secret|key nombre
  local found
  found="$(version_ids "$1" "$KV_DR" "$2")"
  if [[ -n "$found" ]]; then
    az keyvault "$1" delete --vault-name "$KV_DR" -n "$2" -o none
    wait_until "borrado de $2" 30 10 is_deleted "$@" || die "$2 no terminó de borrarse."
  fi
  if is_deleted "$@"; then
    az keyvault "$1" purge --vault-name "$KV_DR" -n "$2" -o none
    wait_until "purga de $2" 30 10 is_purged "$@" || die "$2 no terminó de purgarse."
  fi
  info "$1 $2 eliminado de $KV_DR"
}

test_reset_dr() {
  log "Eliminando los objetos restaurados en $KV_DR"
  reset_one secret "$SECRET_NAME"
  reset_one key "$KEY_NAME"
}

CMD="${1:-}"
case "$CMD" in
  backup-restore|verify|independence|cross-geo|all|reset-dr) ;;
  *) usage; exit 1 ;;
esac

require_login
require_deployment

case "$CMD" in
  backup-restore) test_backup_restore ;;
  verify) test_verify ;;
  independence) test_independence ;;
  cross-geo) test_cross_geo ;;
  all) test_backup_restore; test_verify; test_independence; test_cross_geo ;;
  reset-dr) test_reset_dr ;;
esac
