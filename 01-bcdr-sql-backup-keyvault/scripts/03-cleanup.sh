#!/bin/bash
export RG_PRI="rg-az305-bcdr-pri"
export RG_SEC="rg-az305-bcdr-sec"

echo "=== 1. Purgando datos de respaldo y eliminando Recovery Services Vault ==="
export RSV_NAME=$(az backup vault list -g $RG_PRI --query "[0].name" -o tsv 2>/dev/null)
export VM_NAME=$(az vm list -g $RG_PRI --query "[0].name" -o tsv 2>/dev/null)

if [ -n "$RSV_NAME" ]; then
  if [ -n "$VM_NAME" ]; then
    az backup protection disable \
      --resource-group "$RG_PRI" \
      --vault-name "$RSV_NAME" \
      --container-name "$VM_NAME" \
      --item-name "$VM_NAME" \
      --backup-management-type AzureIaasVM \
      --delete-backup-data true \
      --yes -o none
  fi

  az backup vault delete \
    --name "$RSV_NAME" \
    --resource-group "$RG_PRI" \
    --yes -o none
fi

echo "=== 2. Eliminando SQL Failover Group desde el primario actual ==="
export SQL_ACTUAL_PRI=$(az sql server list -g $RG_SEC --query "[0].name" -o tsv 2>/dev/null)
export FOG_NAME=$(az sql failover-group list -g $RG_SEC -s "$SQL_ACTUAL_PRI" --query "[0].name" -o tsv 2>/dev/null)
[ -n "$FOG_NAME" ] && az sql failover-group delete --name "$FOG_NAME" --resource-group "$RG_SEC" --server "$SQL_ACTUAL_PRI" -o none

echo "=== 3. Eliminando Resource Groups y archivos temporales ==="
rm -f .env_lab01 secreto-prod.backup
az group delete --name $RG_PRI --yes --no-wait
az group delete --name $RG_SEC --yes --no-wait
echo "=== LIMPIEZA COMPLETADA ==="
