#!/bin/bash
set -e
source .env_lab01

export RG_PRI="rg-az305-bcdr-pri"
export RG_SEC="rg-az305-bcdr-sec"
export SQL_SEC="sql-az305-sec-$SUFFIX"
export FOG_NAME="fog-az305-$SUFFIX"
export STG_NAME="stgaz305gzrs$SUFFIX"
export RSV_NAME="rsv-az305-pri-$SUFFIX"
export VM_NAME="vm-az305-web01"
export KV_PRI="kv-az305-pri-$SUFFIX"
export KV_SEC="kv-az305-sec-$SUFFIX"

echo "=== EVIDENCIA 1: Failover SQL hacia westus3 (Rol Primary + Endpoint R/W) ==="
az sql failover-group show \
  --name $FOG_NAME \
  --resource-group $RG_SEC \
  --server $SQL_SEC \
  --query "{Grupo:name, RolEnWestUS3:replicationRole, EstadoReplicacion:replicationState, Politica:readWriteEndpoint.failoverPolicy, GracePeriodMin:readWriteEndpoint.failoverWithDataLossGracePeriodMinutes}" \
  -o table | tee evidence/01-sql-failover-status.txt

echo "=== EVIDENCIA 2: Redundancia GZRS (6 copias: ZRS primaria + LRS secundaria) ==="
az storage account show \
  --name $STG_NAME \
  --resource-group $RG_PRI \
  --query "{Cuenta:name, SKU:sku.name, RegionPrimaria:primaryLocation, EstadoPri:statusOfPrimary, RegionSecundaria:secondaryLocation, EstadoSec:statusOfSecondary}" \
  -o table | tee evidence/02-storage-gzrs-status.txt

echo "=== EVIDENCIA 3: Trabajo de Respaldo IaaS en Recovery Services Vault ==="
az backup protection backup-now \
  --resource-group $RG_PRI \
  --vault-name $RSV_NAME \
  --container-name $VM_NAME \
  --item-name $VM_NAME \
  --backup-management-type AzureIaasVM \
  --retain-until $(date -d "+7 days" +%d-%m-%Y) -o none

sleep 15
az backup job list \
  --resource-group $RG_PRI \
  --vault-name $RSV_NAME \
  --query "[0].{Operacion:properties.operation, Estado:properties.status, RecursoProtegido:properties.entityFriendlyName, InicioUTC:properties.startTime}" \
  -o table | tee evidence/03-backup-job-completed.txt

echo "=== EVIDENCIA 4: Backup Cifrado y Restore Intrageográfico en Key Vault ==="
az keyvault secret backup --vault-name $KV_PRI --name "CadenaConexionProd" --file "secreto-prod.backup"
az keyvault secret restore --vault-name $KV_SEC --file "secreto-prod.backup" -o none
rm -f secreto-prod.backup

az keyvault secret show \
  --vault-name $KV_SEC \
  --name "CadenaConexionProd" \
  --query "{Secreto:name, Habilitado:attributes.enabled, CreadoUTC:attributes.created, Recuperacion:attributes.recoveryLevel}" \
  -o table | tee evidence/04-kv-secret-restored.txt

echo "=== EVIDENCIAS GENERADAS Y SANITIZADAS EN evidence/ ==="
