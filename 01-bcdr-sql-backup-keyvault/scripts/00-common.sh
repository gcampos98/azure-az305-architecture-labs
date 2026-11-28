#!/usr/bin/env bash
# Variables y funciones compartidas. No se ejecuta directamente: los demás scripts lo cargan.
set -Eeuo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$LAB_DIR/.env_lab01"
EVIDENCE_DIR="$LAB_DIR/evidence"
ACTIVITY_DS_NAME="ds-az305-lab01"
export ACTIVITY_DS_NAME EVIDENCE_DIR

log()  { printf '\n=== %s ===\n' "$*"; }
info() { printf '  - %s\n' "$*"; }
warn() { printf 'AVISO: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

trap 'printf "ERROR en %s, línea %s\n" "${BASH_SOURCE[0]##*/}" "$LINENO" >&2' ERR

require_login() {
  command -v az >/dev/null || die "No se encontró Azure CLI."
  az account show -o none || die "Sin sesión activa. Ejecuta: az login --use-device-code"
}

# Devuelve 0 si el recurso consultado existe
exists() { "$@" -o none >/dev/null 2>&1; }

# 0 = existe, 1 = no existe. Si la consulta falla, el script termina (nunca se asume "no existe").
rg_exists() {
  local r
  r="$(az group exists --name "$1")" || die "No se pudo consultar el grupo $1."
  case "$r" in
    true) return 0 ;;
    false) return 1 ;;
    *) die "Respuesta inesperada al consultar el grupo $1: '$r'" ;;
  esac
}

# Carga .env_lab01 (si existe) y completa los valores por defecto
load_config() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
  : "${RG_PRI:=rg-az305-bcdr-pri}"
  : "${RG_SEC:=rg-az305-bcdr-sec}"
  : "${RG_RESTORE:=rg-az305-bcdr-restore}"
  : "${LOC_PRI:=centralus}"
  : "${LOC_PAIR:=eastus2}"
  : "${LOC_SEC:=westus3}"
  : "${SQL_DB:=db-ventas-critica}"
  : "${VM_SIZE:=Standard_B2pts_v2}"
  : "${VM_IMAGE:=Canonical:ubuntu-24_04-lts:server-arm64:latest}"   # Misma arquitectura que VM_SIZE (Arm64)
}

# Si no hay .env_lab01 (sesión efímera de Cloud Shell), recupera el sufijo desde Azure
recover_suffix() {
  [[ -n "${SUFFIX:-}" ]] && return 0
  rg_exists "$RG_PRI" || return 0
  local value
  value="$(az group show --name "$RG_PRI" --query "tags.suffix" -o tsv)"
  if [[ -z "$value" || "$value" == "None" ]]; then
    value="$(az sql server list -g "$RG_PRI" --query "[0].name" -o tsv)"
    value="${value#sql-az305-pri-}"
  fi
  [[ -n "$value" && "$value" != "None" ]] ||
    die "$RG_PRI existe pero no se pudo recuperar el sufijo. Usa: SUFFIX=<valor> $0"
  SUFFIX="$value"
  info "Sufijo recuperado desde Azure: $SUFFIX"
}

set_names() {
  : "${SQL_PRI:=sql-az305-pri-$SUFFIX}"
  : "${SQL_SEC:=sql-az305-sec-$SUFFIX}"
  : "${FOG_NAME:=fog-az305-$SUFFIX}"
  : "${STG_NAME:=stgaz305gzrs$SUFFIX}"
  : "${RSV_NAME:=rsv-az305-pri-$SUFFIX}"
  : "${KV_PRI:=kv-az305-pri-$SUFFIX}"
  : "${KV_SEC:=kv-az305-sec-$SUFFIX}"
  : "${LAW_NAME:=law-az305-bcdr-$SUFFIX}"
  if [[ -z "${VM_NAME:-}" ]]; then
    # Reutiliza la VM existente; si no hay, usa un nombre con sufijo (evita choques con soft delete)
    if rg_exists "$RG_PRI"; then
      VM_NAME="$(az vm list -g "$RG_PRI" --query "[0].name" -o tsv)"
    fi
    : "${VM_NAME:=vm-az305-web-$SUFFIX}"
  fi
}

save_env() {
  local v
  for v in RG_PRI RG_SEC RG_RESTORE LOC_PRI LOC_PAIR LOC_SEC SUFFIX SQL_PRI SQL_SEC SQL_DB \
           FOG_NAME STG_NAME VM_NAME RSV_NAME KV_PRI KV_SEC LAW_NAME; do
    printf 'export %s=%q\n' "$v" "${!v}"
  done >"$ENV_FILE"
}

# Object ID y nombre del usuario conectado (administrador Entra de SQL y rol en Key Vault)
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
  : "${ADMIN_NAME:=$(az account show --query user.name -o tsv)}"
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
