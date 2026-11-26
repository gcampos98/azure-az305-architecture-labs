#!/bin/bash
set -euo pipefail

export RG_PRI="rg-az305-bcdr-pri"
export RG_SEC="rg-az305-bcdr-sec"
export LOC_PRI="centralus"
export LOC_PAIR="eastus2"
export LOC_SEC="westus3"
export SUFFIX="${SUFFIX:-$((RANDOM % 9000 + 1000))}"

export SQL_PRI="sql-az305-pri-${SUFFIX}"
export SQL_SEC="sql-az305-sec-${SUFFIX}"
export SQL_DB="db-ventas-critica"
export FOG_NAME="fog-az305-${SUFFIX}"
export SQL_ADMIN="${SQL_ADMIN:-az305admin}"
export SQL_PASS="${SQL_PASS:-$(openssl rand -base64 16)Aa1!}"

export STG_NAME="stgaz305gzrs${SUFFIX}"
export VM_NAME="vm-az305-web01"
export VM_SIZE="${VM_SIZE:-Standard_B2pts_v2}"
export VM_IMAGE="${VM_IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"
export RSV_NAME="rsv-az305-pri-${SUFFIX}"
export KV_PRI="kv-az305-pri-${SUFFIX}"
export KV_SEC="kv-az305-sec-${SUFFIX}"
export LAW_NAME="law-az305-bcdr-${SUFFIX}"

echo "=== 1. Registrando proveedores de recursos necesarios ==="
az provider register --namespace Microsoft.Network --wait -o none
az provider register --namespace Microsoft.Sql --wait -o none
az provider register --namespace Microsoft.Storage --wait -o none
az provider register --namespace Microsoft.Compute --wait -o none
az provider register --namespace Microsoft.RecoveryServices --wait -o none
az provider register --namespace Microsoft.KeyVault --wait -o none
az provider register --namespace Microsoft.OperationalInsights --wait -o none

echo "=== 2. Creando Resource Groups ==="
az group create --name "$RG_PRI" --location "$LOC_PRI" -o none
az group create --name "$RG_SEC" --location "$LOC_SEC" -o none

echo "=== 3. Creando Log Analytics Workspace ==="
az monitor log-analytics workspace create \
  --resource-group "$RG_PRI" \
  --workspace-name "$LAW_NAME" \
  --location "$LOC_PRI" \
  -o none

echo "=== 4. Creando Storage Account (Standard_GZRS) ==="
az storage account create \
  --name "$STG_NAME" \
  --resource-group "$RG_PRI" \
  --location "$LOC_PRI" \
  --sku Standard_GZRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  -o none

echo "=== 5. Creando VM sin IP pública ni regla SSH abierta ==="
az vm create \
  --resource-group "$RG_PRI" \
  --name "$VM_NAME" \
  --location "$LOC_PRI" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "${VM_ADMIN_USER:-azureuser}" \
  --generate-ssh-keys \
  --public-ip-address "" \
  --nsg-rule NONE \
  -o none

echo "=== 6. Creando Recovery Services Vault y habilitando respaldo de VM ==="
az backup vault create \
  --resource-group "$RG_PRI" \
  --name "$RSV_NAME" \
  --location "$LOC_PRI" \
  -o none

az backup protection enable-for-vm \
  --resource-group "$RG_PRI" \
  --vault-name "$RSV_NAME" \
  --vm "$VM_NAME" \
  --policy-name DefaultPolicy \
  -o none

echo "=== 7. Creando Azure Key Vaults con RBAC en región primaria y secundaria ==="
az keyvault create \
  --name "$KV_PRI" \
  --resource-group "$RG_PRI" \
  --location "$LOC_PRI" \
  --enable-rbac-authorization true \
  -o none

az keyvault create \
  --name "$KV_SEC" \
  --resource-group "$RG_SEC" \
  --location "$LOC_SEC" \
  --enable-rbac-authorization true \
  -o none

echo "=== 8. Creando Azure SQL Servers, DB y Failover Group ==="
az sql server create \
  --name "$SQL_PRI" \
  --resource-group "$RG_PRI" \
  --location "$LOC_PRI" \
  --admin-user "$SQL_ADMIN" \
  --admin-password "$SQL_PASS" \
  -o none

az sql server create \
  --name "$SQL_SEC" \
  --resource-group "$RG_SEC" \
  --location "$LOC_SEC" \
  --admin-user "$SQL_ADMIN" \
  --admin-password "$SQL_PASS" \
  -o none

az sql db create \
  --resource-group "$RG_PRI" \
  --server "$SQL_PRI" \
  --name "$SQL_DB" \
  --service-objective S0 \
  -o none

az sql failover-group create \
  --name "$FOG_NAME" \
  --resource-group "$RG_PRI" \
  --server "$SQL_PRI" \
  --partner-resource-group "$RG_SEC" \
  --partner-server "$SQL_SEC" \
  --failover-policy Manual \
  -o none

cat << EOF > .env_lab01
export RG_PRI="$RG_PRI"
export RG_SEC="$RG_SEC"
export LOC_PRI="$LOC_PRI"
export LOC_PAIR="$LOC_PAIR"
export LOC_SEC="$LOC_SEC"
export SUFFIX="$SUFFIX"
export SQL_PRI="$SQL_PRI"
export SQL_SEC="$SQL_SEC"
export SQL_DB="$SQL_DB"
export FOG_NAME="$FOG_NAME"
export STG_NAME="$STG_NAME"
export VM_NAME="$VM_NAME"
export RSV_NAME="$RSV_NAME"
export KV_PRI="$KV_PRI"
export KV_SEC="$KV_SEC"
export LAW_NAME="$LAW_NAME"
EOF

echo "=== DESPLIEGUE COMPLETADO (SUFFIX=$SUFFIX) ==="
```[cite: 1, 2]
