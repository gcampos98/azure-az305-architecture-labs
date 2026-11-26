#!/usr/bin/env bash
set -euo pipefail

if [[ -f ".env_lab01" ]]; then
  # shellcheck disable=SC1091
  source ".env_lab01"
fi

: "${RG_PRI:?Falta RG_PRI en .env_lab01 o entorno}"
: "${RG_SEC:?Falta RG_SEC en .env_lab01 o entorno}"
: "${LOC_PRI:?Falta LOC_PRI en .env_lab01 o entorno}"
: "${LOC_SEC:?Falta LOC_SEC en .env_lab01 o entorno}"
: "${SUFFIX:?Falta SUFFIX en .env_lab01 o entorno}"
: "${SQL_PRI:?Falta SQL_PRI en .env_lab01 o entorno}"
: "${SQL_SEC:?Falta SQL_SEC en .env_lab01 o entorno}"
: "${FOG_NAME:?Falta FOG_NAME en .env_lab01 o entorno}"
: "${STG_NAME:?Falta STG_NAME en .env_lab01 o entorno}"
: "${VM_NAME:?Falta VM_NAME en .env_lab01 o entorno}"
: "${RSV_NAME:?Falta RSV_NAME en .env_lab01 o entorno}"
: "${KV_PRI:?Falta KV_PRI en .env_lab01 o entorno}"
: "${KV_SEC:?Falta KV_SEC en .env_lab01 o entorno}"

mkdir -p evidence

echo "=== 1. Ejecutando Failover SQL hacia $LOC_SEC y validando estado ==="
T_START=$(date +%s)
az sql failover-group set-primary \
  --name "$FOG_NAME" \
  --resource-group "$RG_SEC" \
  --server "$SQL_SEC" \
  -o none
T_END=$(date +%s)
RTO_SEC=$((T_END - T_START))

{
  echo "RTO_Failover_Segundos: ${RTO_SEC}"
  az sql failover-group show \
    --name "$FOG_NAME" \
    --resource-group "$RG_SEC" \
    --server "$SQL_SEC" \
    --query "{Grupo:name, RolEnSecundaria:replicationRole, EstadoReplicacion:replicationState, Politica:readWriteEndpoint.failoverPolicy}" \
    -o table
} > evidence/01-sql-failover-status.txt

# Restaurar rol primario a la región primaria tras la prueba
az sql failover-group set-primary \
  --name "$FOG_NAME" \
  --resource-group "$RG_PRI" \
  --server "$SQL_PRI" \
  -o none

echo "=== 2. Verificando redundancia GZRS en Storage ==="
az storage account show \
  --name "$STG_NAME" \
  --resource-group "$RG_PRI" \
  --query "{Cuenta:name, SKU:sku.name, RegionPrimaria:primaryLocation, EstadoPri:statusOfPrimary, RegionSecundaria:secondaryLocation, EstadoSec:statusOfSecondary}" \
  -o table > evidence/02-storage-gzrs-status.txt

echo "=== 3. Disparando backup de VM y esperando finalización ==="
RETAIN_UNTIL=$(date -u -d '+7 days' '+%d-%m-%Y' 2>/dev/null || date -u -v+7d '+%d-%m-%Y')

JOB_ID=$(az backup protection backup-now \
  --resource-group "$RG_PRI" \
  --vault-name "$RSV_NAME" \
  --container-name "$VM_NAME" \
  --item-name "$VM_NAME" \
  --backup-management-type AzureIaasVM \
  --retain-until "$RETAIN_UNTIL" \
  --query "name" -o tsv)

echo "Job de backup iniciado: $JOB_ID"
for _ in $(seq 1 30); do
  JOB_STATUS=$(az backup job show \
    --resource-group "$RG_PRI" \
    --vault-name "$RSV_NAME" \
    --name "$JOB_ID" \
    --query "properties.status" -o tsv 2>/dev/null || echo "InProgress")
  echo "Estado actual del job ($JOB_ID): $JOB_STATUS"
  if [[ "$JOB_STATUS" == "Completed" || "$JOB_STATUS" == "CompletedWithWarnings" || "$JOB_STATUS" == "Failed" ]]; then
    break
  fi
  sleep 15
done

az backup job show \
  --resource-group "$RG_PRI" \
  --vault-name "$RSV_NAME" \
  --name "$JOB_ID" \
  --query "{JobId:name, Operacion:properties.operation, Estado:properties.status, Inicio:properties.startTime, Fin:properties.endTime}" \
  -o table > evidence/03-backup-job-completed.txt

echo "=== 4. Probando backup y restore de secreto en Key Vault (misma suscripción y geografía) ==="
SECRET_NAME="lab01-bcdr-secret-${SUFFIX}"
BACKUP_FILE="/tmp/${SECRET_NAME}.kvbak"

az keyvault secret set \
  --vault-name "$KV_PRI" \
  --name "$SECRET_NAME" \
  --value "ValorPruebaBCDR-${SUFFIX}" \
  -o none

az keyvault secret backup \
  --vault-name "$KV_PRI" \
  --name "$SECRET_NAME" \
  --file "$BACKUP_FILE" \
  -o none

az keyvault secret restore \
  --vault-name "$KV_SEC" \
  --file "$BACKUP_FILE" \
  -o none

rm -f "$BACKUP_FILE"

az keyvault secret show \
  --vault-name "$KV_SEC" \
  --name "$SECRET_NAME" \
  --query "{VaultSecundario:id, Habilitado:attributes.enabled, UltimaActualizacion:attributes.updated}" \
  -o table > evidence/04-kv-secret-restored.txt

echo "=== PRUEBAS DE CARGA Y BCDR COMPLETADAS (SUFFIX=$SUFFIX) ==="
