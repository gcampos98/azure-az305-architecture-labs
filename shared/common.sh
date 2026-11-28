#!/usr/bin/env bash
# Funciones compartidas por los laboratorios 01B y 01C. No se ejecuta directamente.
# Antes de cargarlo, el laboratorio define: LAB_DIR, LAB_TAG y el arreglo STATE_VARS.
# QUERY y PENDING los consumen los scripts que cargan este archivo.
# shellcheck disable=SC2034
set -Eeuo pipefail

ENV_FILE="$LAB_DIR/.env_$LAB_TAG"
EVIDENCE_DIR="$LAB_DIR/evidence"

log()  { printf '\n=== %s ===\n' "$*"; }
info() { printf '  - %s\n' "$*"; }
warn() { printf 'AVISO: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

trap 'printf "ERROR en %s, línea %s\n" "${BASH_SOURCE[0]##*/}" "$LINENO" >&2' ERR

require_login() {
  command -v az >/dev/null || die "No se encontró Azure CLI."
  command -v python3 >/dev/null || die "No se encontró python3."
  az account show -o none || die "Sin sesión activa. Ejecuta: az login --use-device-code"
}

# Devuelve 0 si el recurso consultado existe (solo para decidir si hay que crearlo)
exists() { "$@" -o none >/dev/null 2>&1; }

# 0 = existe, 1 = no existe. Si la consulta falla, el script termina (nunca se asume "no existe").
rg_exists() {
  local r
  r="$(az group exists --name "$1" -o json)" || die "No se pudo consultar el grupo $1."
  case "$r" in
    true) return 0 ;;
    false) return 1 ;;
    *) die "Respuesta inesperada al consultar el grupo $1: '$r'" ;;
  esac
}

# Valor del tag "lab" de un grupo (para no tocar grupos ajenos)
rg_lab_tag() {
  local v
  v="$(az group show --name "$1" --query "tags.lab" -o tsv)" || die "No se pudo leer el grupo $1."
  printf '%s' "$v"
}

# ensure_rg <grupo> <región>: crea el grupo o comprueba que pertenece a este lab
ensure_rg() {
  if rg_exists "$1"; then
    [[ "$(rg_lab_tag "$1")" == "$LAB_TAG" ]] ||
      die "El grupo $1 ya existe y no tiene el tag lab=$LAB_TAG. Usa otro RG_PREFIX."
  else
    az group create --name "$1" --location "$2" \
      --tags "lab=$LAB_TAG" "suffix=$SUFFIX" -o none
  fi
}

load_state() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
}

# Guarda las variables de STATE_VARS (sin secretos) para poder reanudar el lab
save_state() {
  local v
  for v in "${STATE_VARS[@]}"; do
    printf 'export %s=%q\n' "$v" "${!v-}"
  done >"$ENV_FILE.new"
  mv "$ENV_FILE.new" "$ENV_FILE"
}

new_suffix() { od -An -N3 -tx1 /dev/urandom | tr -d ' \n'; }

# Si se perdió el archivo de estado (Cloud Shell efímera), recupera el sufijo del tag del grupo
recover_suffix() {
  [[ -n "${SUFFIX:-}" ]] && return 0
  rg_exists "$1" || return 0
  local value
  value="$(az group show --name "$1" --query "tags.suffix" -o tsv)" || die "No se pudo leer $1."
  [[ -n "$value" && "$value" != "None" ]] || die "$1 existe pero no tiene el tag suffix. Exporta SUFFIX."
  SUFFIX="$value"
  info "Sufijo recuperado desde Azure: $SUFFIX"
}

# wait_until <descripción> <intentos> <segundos> <función> [argumentos]
wait_until() {
  local desc="$1" tries="$2" delay="$3" i
  shift 3
  for ((i = 1; i <= tries; i++)); do
    if "$@"; then return 0; fi
    info "Esperando: $desc ($i/$tries)"
    sleep "$delay"
  done
  return 1
}

# retry <intentos> <segundos> <comando>: útil mientras se propagan los roles RBAC
retry() {
  local tries="$1" delay="$2" i
  shift 2
  for ((i = 1; i < tries; i++)); do
    if "$@" 2>/dev/null; then return 0; fi
    info "Reintentando ($i/$tries)" >&2
    sleep "$delay"
  done
  "$@"
}

load_identity() {
  if [[ -z "${ADMIN_OID:-}" ]]; then
    ADMIN_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
  fi
  if [[ -z "$ADMIN_OID" ]]; then
    # Alternativa sin Microsoft Graph: leer el claim "oid" del token de Azure
    ADMIN_OID="$(az account get-access-token --query accessToken -o tsv |
      python3 -c 'import sys,json,base64; p=sys.stdin.read().split(".")[1]; print(json.loads(base64.urlsafe_b64decode(p+"="*(-len(p)%4))).get("oid",""))')" ||
      die "No se pudo identificar tu usuario. Exporta ADMIN_OID."
  fi
  [[ -n "$ADMIN_OID" ]] || die "No se pudo identificar tu usuario. Exporta ADMIN_OID."
}

# assign_role <rol> <scope>: asigna el rol al usuario conectado si aún no lo tiene
assign_role() {
  local count
  count="$(az role assignment list --scope "$2" --role "$1" \
    --query "length([?principalId=='$ADMIN_OID'])" -o tsv)"
  if [[ "$count" == "0" ]]; then
    az role assignment create --role "$1" --scope "$2" \
      --assignee-object-id "$ADMIN_OID" --assignee-principal-type User -o none
  fi
}

# Oculta GUIDs, correos e IPv4 antes de guardar evidencia
sanitize() {
  sed -E \
    -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<guid>/g' \
    -e 's/[A-Za-z0-9._%+#-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<usuario>/g' \
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g'
}

# save_evidence <archivo_o_bloque> <comando...>: consolida todos los bloques en evidence/EVIDENCIA-CONSOLIDADA.md
save_evidence() {
  local tag="$1" out="$EVIDENCE_DIR/EVIDENCIA-CONSOLIDADA.md" tmp
  shift
  mkdir -p "$EVIDENCE_DIR"
  tmp="$(mktemp)"
  if ! "$@" >"$tmp"; then
    rm -f "$tmp"; die "Falló la evidencia ${tag}; el archivo consolidado no se modificó."
  fi
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"; die "La evidencia ${tag} salió vacía; el archivo consolidado no se modificó."
  fi
  if [[ ! -f "$out" ]]; then
    {
      echo "# Evidencia Técnica Consolidada — ${LAB_TAG:-AZ-305}"
      echo
      echo "> Salidas sanitizadas automáticamente (sin GUIDs, correos ni direcciones IPv4)."
    } >"$out"
  fi
  python3 - "$out" "$tag" "$tmp" <<'PY'
import re, sys
from datetime import datetime, timezone

out_path, tag, tmp_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(out_path, "r", encoding="utf-8") as f:
    doc = f.read()
with open(tmp_path, "r", encoding="utf-8") as f:
    raw = f.read()

raw = re.sub(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", "<guid>", raw)
raw = re.sub(r"[A-Za-z0-9._%+#-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "<usuario>", raw)
raw = re.sub(r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b", "<ip>", raw)

ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
section = (
    f"<!-- BEGIN:{tag} -->\n"
    f"## Bloque: `{tag}`\n"
    f"- **Generado (UTC):** `{ts}`\n\n"
    f"```text\n{raw.rstrip()}\n```\n"
    f"<!-- END:{tag} -->"
)

pattern = re.compile(rf"<!-- BEGIN:{re.escape(tag)} -->.*?<!-- END:{re.escape(tag)} -->", re.DOTALL)
if pattern.search(doc):
    doc = pattern.sub(lambda _: section, doc)
else:
    doc = doc.rstrip() + "\n\n" + section + "\n"

with open(out_path, "w", encoding="utf-8") as f:
    f.write(doc)
PY
  printf '\n--- Bloque consolidado [%s] en %s ---\n' "$tag" "$out"
  sanitize <"$tmp"
  rm -f "$tmp"
}

# --- Ayudas para los scripts de limpieza -------------------------------------
FAILURES=0
fail() { warn "$*"; FAILURES=$((FAILURES + 1)); }

# query <comando az...>: guarda la salida en QUERY; si falla, lo registra
query() {
  if ! QUERY="$("$@")"; then fail "Falló la consulta: $*"; QUERY=""; return 1; fi
}

# own_rg <grupo>: 0 si existe y pertenece a este lab
own_rg() {
  rg_exists "$1" || return 1
  [[ "$(rg_lab_tag "$1")" == "$LAB_TAG" ]] && return 0
  fail "El grupo $1 no tiene el tag lab=$LAB_TAG: no se toca."
  return 1
}

# confirm_delete <MODE> <grupos...>
confirm_delete() {
  local mode="$1" answer
  shift
  [[ "$mode" == "--yes" ]] && return 0
  echo "Suscripción: $(az account show --query name -o tsv)"
  echo "Se eliminarán: $*"
  read -r -p "Escribe BORRAR para continuar: " answer
  [[ "$answer" == "BORRAR" ]] || die "Cancelado."
}

pending_groups() {
  PENDING=()
  local rg
  for rg in "$@"; do
    if rg_exists "$rg"; then PENDING+=("$rg"); fi
  done
}
