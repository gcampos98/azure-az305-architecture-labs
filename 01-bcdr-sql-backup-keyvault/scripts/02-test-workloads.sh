#!/bin/bash
set -euo pipefail

if [ ! -f .env_lab01 ]; then
  echo "Error: no existe .env_lab01. Ejecuta primero ./scripts/01-deploy.sh" >&2
  exit 1
fi
source .env_lab01
mkdir -p evidence

TMP_BACKUP_FILE="$(mktemp)"
cleanup_tmp() {
  rm -f "$TMP_BACKUP_FILE"
}
trap cleanup_tmp EXIT

echo "=== 1. Ejecutando Failover SQL hacia $LOC_SEC y validando estado ==="
START_FAILOVER=$(date -u +%s)
az sql failover-group set-primary \
  --name "$FOG_NAME" \
  --resource-group "$RG_SEC" \
  --server "$SQL_SEC" \
  -o none
END_FAILOVER=$(date -u +%s)
RTO_SEG=$((END_FAILOVER - START_FAILOVER))

tmp_ev1="$(mktemp)"
{
  echo "RTO_Failover_Segundos: ${RTO_SEG}"
  az sql failover-group show \
    --name "$FOG_NAME" \
    --resource-group "$RG_SEC" \
    --server "$SQL_SEC" \
    --query "{Grupo:name, RolEnSecundaria:replicationRole, EstadoReplicacion:replicationState, Politica:readWriteEndpoint.failoverPolicy, GracePeriodMin:readWriteEndpoint.failoverWithGracePeriodMinutes}" \
    -o table
} > "$tmp_ev1"
mv "$tmp_ev1" evidence/01-sql-failover-status.txt

echo "=== 2. Verificando redundancia GZRS en Storage ==="
tmp_ev2="$(mktemp)"
az storage account show \
  --name "$STG_NAME" \
  --resource-group "$RG_PRI" \
  --query "{Cuenta:name, SKU:sku.name, RegionPrimaria:primaryLocation, EstadoPri:statusOfPrimary, RegionSecundaria:secondaryLocation, EstadoSec:statusOfSecondary}" \
  -o table > "$tmp_ev2"
mv "$tmp_ev2" evidence/02-storage-gzrs-status.txt

echo "=== 3. Disparando backup de VM y esperando finalización ==="
JOB_ID=$(az backup protection trigger-now \
  --resource-group "$RG_PRI" \
  --vault-name "$RSV_NAME" \
  --container-name "$VM_NAME" \
  --item-name "$VM_NAME" \
  --backup-management-type AzureIaasVM \
  --retain-until "$(date -u -d '+7 days' '+%Y-%m-%d')" \
  --query "name" -o tsv)

az backup job wait \
  --resource-group "$RG_PRI" \
  --vault-name "$RSV_NAME" \
  --name "$JOB_ID" \
  -o none

tmp_ev3="$(mktemp)"
az backup job show \
  --resource-group "$RG_PRI" \
  --vault-name "$RSV_NAME" \
  --name "$JOB_ID" \
  --query "{Operacion:properties.operation, Estado:properties.status, RecursoProtegido:properties.entityFriendlyName, Duracion:properties.duration}" \
  -o table > "$tmp_ev3"
mv "$tmp_ev3" evidence/03-backup-job-completed.txt

echo "=== 4. Backup y restore de secreto en Key Vault (misma suscripción y geografía) ==="
SECRET_NAME="CadenaConexionDemo"
az keyvault secret set \
  --vault-name "$KV_PRI" \
  --name "$SECRET_NAME" \
  --value "Server=tcp:demo.database.windows.net,1433;" \
  -o none

az keyvault secret backup \
  --vault-name "$KV_PRI" \
  --name "$SECRET_NAME" \
  --file "$TMP_BACKUP_FILE" \
  -o none

az keyvault secret restore \
  --vault-name "$KV_SEC" \
  --file "$TMP_BACKUP_FILE" \
  -o none

tmp_ev4="$(mktemp)"
az keyvault secret show \
  --vault-name "$KV_SEC" \
  --name "$SECRET_NAME" \
  --query "{Secreto:name, Habilitado:attributes.enabled, Recuperable:attributes.recoveryLevel}" \
  -o table > "$tmp_ev4"
mv "$tmp_ev4" evidence/04-kv-secret-restored.txt

echo "=== 5. Ejecutando Failback SQL hacia $LOC_PRI ==="
az sql failover-group set-primary \
  --name "$FOG_NAME" \
  --resource-group "$RG_PRI" \
  --server "$SQL_PRI" \
  -o none

echo "=== PRUEBAS COMPLETADAS ==="
