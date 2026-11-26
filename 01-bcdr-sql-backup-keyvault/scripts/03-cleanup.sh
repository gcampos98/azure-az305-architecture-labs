#!/bin/bash
set -euo pipefail

if [ -f .env_lab01 ]; then
  source .env_lab01
else
  export RG_PRI="${RG_PRI:-rg-az305-bcdr-pri}"
  export RG_SEC="${RG_SEC:-rg-az305-bcdr-sec}"
fi

echo "=== 1. Eliminando datos de respaldo y Vault (si existen) ==="
RSV_NAME="${RSV_NAME:-$(az backup vault list -g "$RG_PRI" --query "[0].name" -o tsv 2>/dev/null || true)}"
VM_NAME="${VM_NAME:-$(az vm list -g "$RG_PRI" --query "[0].name" -o tsv 2>/dev/null || true)}"

if [ -n "${RSV_NAME:-}" ] && az backup vault show -g "$RG_PRI" -n "$RSV_NAME" >/dev/null 2>&1; then
  if [ -n "${VM_NAME:-}" ]; then
    DEL_JOB_ID=$(az backup protection disable \
      --resource-group "$RG_PRI" \
      --vault-name "$RSV_NAME" \
      --container-name "$VM_NAME" \
      --item-name "$VM_NAME" \
      --backup-management-type AzureIaasVM \
      --delete-backup-data true \
      --yes \
      --query "name" -o tsv 2>/dev/null || true)

    if [ -n "${DEL_JOB_ID:-}" ]; then
      az backup job wait \
        --resource-group "$RG_PRI" \
        --vault-name "$RSV_NAME" \
        --name "$DEL_JOB_ID" \
        -o none || true
    fi
  fi

  az backup vault delete \
    --name "$RSV_NAME" \
    --resource-group "$RG_PRI" \
    --yes \
    -o none || true
fi

echo "=== 2. Detectando servidor SQL primario actual y eliminando Failover Group ==="
for rg_cand in "$RG_PRI" "$RG_SEC"; do
  if az group exists --name "$rg_cand" | grep -qi "true"; then
    while IFS=$'\t' read -r srv_name fog_name role; do
      if [ -n "${fog_name:-}" ] && [ "$role" = "Primary" ]; then
        az sql failover-group delete \
          --name "$fog_name" \
          --resource-group "$rg_cand" \
          --server "$srv_name" \
          -o none
      fi
    done < <(
      for s in $(az sql server list -g "$rg_cand" --query "[].name" -o tsv 2>/dev/null || true); do
        az sql failover-group list -g "$rg_cand" -s "$s" \
          --query "[].['$s', name, replicationRole]" -o tsv 2>/dev/null || true
      done
    )
  fi
done

echo "=== 3. Eliminando Resource Groups y verificando borrado ==="
for rg in "$RG_PRI" "$RG_SEC"; do
  if az group exists --name "$rg" | grep -qi "true"; then
    az group delete --name "$rg" --yes
  fi
  if az group exists --name "$rg" | grep -qi "true"; then
    echo "Error: el grupo $rg aún existe tras intentar eliminarlo." >&2
    exit 1
  fi
done

rm -f .env_lab01 secreto-prod.backup
echo "=== LIMPIEZA COMPLETADA Y VERIFICADA ==="
