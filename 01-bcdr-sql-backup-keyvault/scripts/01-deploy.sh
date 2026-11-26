#!/bin/bash
set -e

echo "=== 1. Registrando Resource Providers ==="
for rp in Microsoft.Sql Microsoft.RecoveryServices Microsoft.Storage Microsoft.Compute Microsoft.KeyVault; do
  az provider register --namespace $rp --wait
done

echo "=== 2. Configurando variables y Resource Groups ==="
if [ -f .env_lab01 ]; then
  source .env_lab01
else
  export SUFFIX=$RANDOM
  echo "export SUFFIX=$SUFFIX" > .env_lab01
fi

export RG_PRI="rg-az305-bcdr-pri"
export RG_SEC="rg-az305-bcdr-sec"
export LOC_PRI="centralus"
export LOC_SEC="westus3"

az group create --name $RG_PRI --location $LOC_PRI -o table
az group create --name $RG_SEC --location $LOC_SEC -o table

echo "=== 3. Desplegando Azure SQL Servers, DB S0 y Failover Group ==="
export SQL_PRI="sql-az305-pri-$SUFFIX"
export SQL_SEC="sql-az305-sec-$SUFFIX"
export FOG_NAME="fog-az305-$SUFFIX"
export DB_NAME="db-ventas-critica"
export SQL_ADMIN="adminaz305"
export SQL_PASS="${SQL_PASS:-$(openssl rand -base64 16)Aa1!}"

az sql server create --name $SQL_PRI --resource-group $RG_PRI --location $LOC_PRI --admin-user $SQL_ADMIN --admin-password "$SQL_PASS" -o none
az sql server create --name $SQL_SEC --resource-group $RG_SEC --location $LOC_SEC --admin-user $SQL_ADMIN --admin-password "$SQL_PASS" -o none
az sql db create --resource-group $RG_PRI --server $SQL_PRI --name $DB_NAME --service-objective S0 -o table

az sql failover-group create \
  --name $FOG_NAME \
  --partner-server $SQL_SEC \
  --partner-resource-group $RG_SEC \
  --resource-group $RG_PRI \
  --server $SQL_PRI \
  --failover-policy Automatic \
  --grace-period 1 \
  --add-db $DB_NAME -o table

echo "=== 4. Desplegando Storage GZRS, VM B2pts_v2 (ARM64) y Recovery Services Vault ==="
export STG_NAME="stgaz305gzrs$SUFFIX"
export RSV_NAME="rsv-az305-pri-$SUFFIX"
export VM_NAME="vm-az305-web01"

az storage account create --name $STG_NAME --resource-group $RG_PRI --location $LOC_PRI --sku Standard_GZRS --kind StorageV2 -o table
az backup vault create --resource-group $RG_PRI --name $RSV_NAME --location $LOC_PRI -o table

az vm create \
  --resource-group $RG_PRI \
  --name $VM_NAME \
  --location $LOC_PRI \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-arm64:latest \
  --size Standard_B2pts_v2 \
  --admin-username azureuser \
  --generate-ssh-keys -o table

az backup protection enable-for-vm \
  --resource-group $RG_PRI \
  --vault-name $RSV_NAME \
  --vm $(az vm show -g $RG_PRI -n $VM_NAME --query id -o tsv) \
  --policy-name DefaultPolicy -o table

echo "=== 5. Desplegando Key Vaults en centralus y westus3 ==="
export KV_PRI="kv-az305-pri-$SUFFIX"
export KV_SEC="kv-az305-sec-$SUFFIX"

az keyvault create --name $KV_PRI --resource-group $RG_PRI --location $LOC_PRI --enable-rbac-authorization false -o none
az keyvault create --name $KV_SEC --resource-group $RG_SEC --location $LOC_SEC --enable-rbac-authorization false -o none
az keyvault secret set --vault-name $KV_PRI --name "CadenaConexionProd" --value "Server=tcp:$FOG_NAME.database.windows.net;Database=$DB_NAME;" -o table

echo "=== DESPLIEGUE COMPLETADO CON SUFFIX: $SUFFIX ==="
