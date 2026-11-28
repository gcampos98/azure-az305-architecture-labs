#!/usr/bin/env bash
# Revisa los scripts sin desplegar nada en Azure. Pensado para Azure Cloud Shell.
# Uso: bash shared/validate.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SHELLCHECK_PKG="shellcheck-py==0.10.0.1"
LINT_VENV="${LINT_VENV:-$HOME/.cache/az305-lint}"
scripts=(shared/*.sh */scripts/*.sh)

echo "=== Sintaxis de Bash (${#scripts[@]} archivos)"
for f in "${scripts[@]}"; do bash -n "$f"; done

echo "=== Sintaxis de Python"
python3 - */scripts/*.py <<'PY'
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as source:
        compile(source.read(), path, "exec")
PY

echo "=== ShellCheck"
SC="$(command -v shellcheck || true)"
if [[ -z "$SC" ]]; then
  # Cloud Shell no lo incluye: se instala en un entorno virtual propio
  SC="$LINT_VENV/bin/shellcheck"
  if [[ ! -x "$SC" ]]; then
    echo "  - Instalando ShellCheck en $LINT_VENV (solo la primera vez)"
    python3 -m venv "$LINT_VENV"
    "$LINT_VENV/bin/pip" install --quiet "$SHELLCHECK_PKG"
  fi
fi
"$SC" -x -S warning -P SCRIPTDIR "${scripts[@]}"

echo "Validación correcta"
