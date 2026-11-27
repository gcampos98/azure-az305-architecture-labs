#!/usr/bin/env bash
# Despliegue del Laboratorio 01. Idempotente: se puede reejecutar si la sesión se corta
# y completa lo que falte en un despliegue anterior.
# Uso: ./scripts/01-deploy.sh      Opciones: ENABLE_NAT=true  ENABLE_CRR=true
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

ENABLE_NAT="${ENABLE_NAT:-false}"   # Salida explícita para la VM (genera costo por hora)
ENABLE_CRR="${ENABLE_CRR:-false}"   # Cross Region Restore (solo hacia la región emparejada)

require_login
load_config
load_identity

log "1. Registrando proveedores de recursos"
for rp in Microsoft.Network Microsoft.Sql Microsoft.Storage Microsoft.Compute \
          Microsoft.RecoveryServices Microsoft.KeyVault Microsoft.OperationalInsights Microsoft.Insights; do
  info "$rp"
  az provider register --namespace "$rp" --wait -o none
done

log "2. Grupos de recursos y estado local"
recover_suffix
: "${SUFFIX:=$(openssl rand -hex 3)}"
set_names
save_env   # Se guarda ANTES de crear recursos
az group create --name "$RG_PRI" --location "$LOC_PRI" --tags lab=az305-01 suffix="$SUFFIX" -o none
az group create --name "$RG_SEC" --location "$LOC_SEC" --tags lab=az305-01 suffix="$SUFFIX" -o none
info "SUFFIX=$SUFFIX (guardado en $ENV_FILE y como tag del grupo)"

log "3. Log Analytics Workspace"
exists az monitor log-analytics workspace show -g "$RG_PRI" -n "$LAW_NAME" ||
  az monitor log-analytics workspace create -g "$RG_PRI" -n "$LAW_NAME" -l "$LOC_PRI" -o none
LAW_ID="$(az monitor log-analytics workspace show -g "$RG_PRI" -n "$LAW_NAME" --query id -o tsv)"

log "4. Storage Account (Standard_GZRS)"
exists az storage account show -g "$RG_PRI" -n "$STG_NAME" ||
  az storage account create -n "$STG_NAME" -g "$RG_PRI" -l "$LOC_PRI" \
    --sku Standard_GZRS --kind StorageV2 --min-tls-version TLS1_2 \
    --https-only true --allow-blob-public-access false -o none

log "5. VM sin IP pública ni reglas de entrada"
if ! exists az vm show -g "$RG_PRI" -n "$VM_NAME"; then
  sku="$(az vm list-skus --location "$LOC_PRI" --size "$VM_SIZE" --resource-type virtualMachines \
    --query "[?name=='$VM_SIZE' && length(restrictions)==\`0\`].name | [0]" -o tsv)"
  [[ -n "$sku" && "$sku" != "None" ]] ||
    die "$VM_SIZE no está disponible en $LOC_PRI para esta suscripción. Define VM_SIZE y VM_IMAGE."
  az vm create -g "$RG_PRI" -n "$VM_NAME" -l "$LOC_PRI" \
    --image "$VM_IMAGE" --size "$VM_SIZE" \
    --admin-username "${VM_ADMIN_USER:-azureuser}" --generate-ssh-keys \
    --public-ip-address "" --nsg-rule NONE -o none
fi
if [[ "$ENABLE_NAT" == "true" ]]; then
  exists az network public-ip show -g "$RG_PRI" -n pip-nat-az305 ||
    az network public-ip create -g "$RG_PRI" -n pip-nat-az305 -l "$LOC_PRI" \
      --sku Standard --allocation-method Static -o none
  exists az network nat gateway show -g "$RG_PRI" -n nat-az305 ||
    az network nat gateway create -g "$RG_PRI" -n nat-az305 -l "$LOC_PRI" \
      --public-ip-addresses pip-nat-az305 -o none
  nat_id="$(az network nat gateway show -g "$RG_PRI" -n nat-az305 --query id -o tsv)"
  nic_id="$(az vm show -g "$RG_PRI" -n "$VM_NAME" --query "networkProfile.networkInterfaces[0].id" -o tsv)"
  subnet_id="$(az network nic show --ids "$nic_id" --query "ipConfigurations[0].subnet.id" -o tsv)"
  az network vnet subnet update --ids "$subnet_id" --nat-gateway "$nat_id" -o none
fi

log "6. Recovery Services Vault y respaldo de la VM"
exists az backup vault show -g "$RG_PRI" -n "$RSV_NAME" ||
  az backup vault create -g "$RG_PRI" -n "$RSV_NAME" -l "$LOC_PRI" -o none
if [[ "$ENABLE_CRR" == "true" ]]; then
  az backup vault backup-properties set -g "$RG_PRI" -n "$RSV_NAME" --cross-region-restore-flag true -o none
fi
protected="$(az backup item list -g "$RG_PRI" -v "$RSV_NAME" \
  --backup-management-type AzureIaasVM --workload-type VM \
  --query "length([?properties.friendlyName=='$VM_NAME'])" -o tsv)"
if [[ "$protected" == "0" ]]; then
  vm_id="$(az vm show -g "$RG_PRI" -n "$VM_NAME" --query id -o tsv)"
  az backup protection enable-for-vm -g "$RG_PRI" -v "$RSV_NAME" \
    --vm "$vm_id" --policy-name DefaultPolicy -o none
fi

log "7. Key Vaults con RBAC y asignación de rol"
create_kv() { # nombre grupo región
  local kv_id count deleted
  if ! exists az keyvault show -g "$2" -n "$1"; then
    deleted="$(az keyvault list-deleted --resource-type vault --query "length([?name=='$1'])" -o tsv)"
    [[ "$deleted" == "0" ]] ||
      die "$1 está en soft delete. Púrgalo (az keyvault purge --name $1) o usa otro SUFFIX."
    az keyvault create -n "$1" -g "$2" -l "$3" \
      --enable-rbac-authorization true --retention-days 7 -o none
  fi
  kv_id="$(az keyvault show -g "$2" -n "$1" --query id -o tsv)"
  count="$(az role assignment list --scope "$kv_id" --role "Key Vault Secrets Officer" \
    --query "length([?principalId=='$ADMIN_OID'])" -o tsv)"
  if [[ "$count" == "0" ]]; then
    az role assignment create --role "Key Vault Secrets Officer" --scope "$kv_id" \
      --assignee-object-id "$ADMIN_OID" --assignee-principal-type User -o none
  fi
}
create_kv "$KV_PRI" "$RG_PRI" "$LOC_PRI"
create_kv "$KV_SEC" "$RG_SEC" "$LOC_SEC"

log "8. Azure SQL: servidores, base de datos y Failover Group"
create_sql_server() { # nombre grupo región
  if ! exists az sql server show -g "$2" -n "$1"; then
    az sql server create -n "$1" -g "$2" -l "$3" \
      --enable-ad-only-auth --external-admin-principal-type User \
      --external-admin-name "$ADMIN_NAME" --external-admin-sid "$ADMIN_OID" \
      --minimal-tls-version 1.2 -o none
  else
    # Servidor de un despliegue anterior: asegura un administrador Entra ID
    local admins
    admins="$(az sql server ad-admin list -g "$2" -s "$1" --query "length(@)" -o tsv)"
    if [[ "$admins" == "0" ]]; then
      az sql server ad-admin create -g "$2" -s "$1" -u "$ADMIN_NAME" -i "$ADMIN_OID" -o none
    fi
  fi
}
create_sql_server "$SQL_PRI" "$RG_PRI" "$LOC_PRI"
create_sql_server "$SQL_SEC" "$RG_SEC" "$LOC_SEC"

exists az sql db show -g "$RG_PRI" -s "$SQL_PRI" -n "$SQL_DB" ||
  az sql db create -g "$RG_PRI" -s "$SQL_PRI" -n "$SQL_DB" --service-objective S0 -o none

if ! exists az sql failover-group show -g "$RG_PRI" -s "$SQL_PRI" -n "$FOG_NAME"; then
  az sql failover-group create -n "$FOG_NAME" -g "$RG_PRI" -s "$SQL_PRI" \
    --partner-resource-group "$RG_SEC" --partner-server "$SQL_SEC" \
    --failover-policy Manual --add-db "$SQL_DB" -o none
fi

# Verifica que la base pertenezca al grupo (y la agrega si falta)
db_in_group() {
  az sql failover-group show -g "$RG_PRI" -s "$SQL_PRI" -n "$FOG_NAME" \
    --query "length(databases[?ends_with(@, '/databases/$SQL_DB')] || \`[]\`)" -o tsv
}
members="$(db_in_group)"
if [[ "$members" == "0" ]]; then
  role="$(az sql failover-group show -g "$RG_PRI" -s "$SQL_PRI" -n "$FOG_NAME" --query replicationRole -o tsv)"
  [[ "$role" == "Primary" ]] ||
    die "La base no está en el grupo y el primario no es $SQL_PRI. Haz failback y reejecuta."
  warn "El Failover Group no incluía $SQL_DB; agregándola."
  az sql failover-group update -g "$RG_PRI" -s "$SQL_PRI" -n "$FOG_NAME" --add-db "$SQL_DB" -o none
  members="$(db_in_group)"
fi
[[ "$members" != "0" ]] || die "$SQL_DB no quedó en el Failover Group."

log "9. Diagnósticos hacia Log Analytics"
diag() { # id-recurso logs-json [argumentos extra]
  local id="$1" logs="$2"
  shift 2
  az monitor diagnostic-settings create --name ds-lab01 --resource "$id" \
    --workspace "$LAW_ID" --logs "$logs" "$@" -o none
}
for par in "$RG_PRI:$SQL_PRI" "$RG_SEC:$SQL_SEC"; do
  for intento in $(seq 1 20); do   # la réplica puede tardar en aparecer
    exists az sql db show -g "${par%%:*}" -s "${par##*:}" -n "$SQL_DB" && break
    info "Esperando la base en ${par##*:} ($intento/20)"
    sleep "${DB_WAIT:-15}"
  done
  db_id="$(az sql db show -g "${par%%:*}" -s "${par##*:}" -n "$SQL_DB" --query id -o tsv)"
  diag "$db_id" '[{"category":"Errors","enabled":true},{"category":"Timeouts","enabled":true},{"category":"Deadlocks","enabled":true}]' \
    --metrics '[{"category":"Basic","enabled":true}]'
done
for par in "$RG_PRI:$KV_PRI" "$RG_SEC:$KV_SEC"; do
  kv_id="$(az keyvault show -g "${par%%:*}" -n "${par##*:}" --query id -o tsv)"
  diag "$kv_id" '[{"category":"AuditEvent","enabled":true}]' --export-to-resource-specific true
done
stg_id="$(az storage account show -g "$RG_PRI" -n "$STG_NAME" --query id -o tsv)"
diag "$stg_id/blobServices/default" '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' \
  --export-to-resource-specific true
rsv_id="$(az backup vault show -g "$RG_PRI" -n "$RSV_NAME" --query id -o tsv)"
diag "$rsv_id" '[{"category":"CoreAzureBackup","enabled":true},{"category":"AddonAzureBackupJobs","enabled":true}]' \
  --export-to-resource-specific true
az monitor diagnostic-settings subscription create --name "$ACTIVITY_DS_NAME" --location "$LOC_PRI" \
  --workspace "$LAW_ID" --logs '[{"category":"Administrative","enabled":true}]' -o none ||
  warn "No se pudo exportar el Activity Log (requiere permisos sobre la suscripción)."

log "DESPLIEGUE COMPLETADO (SUFFIX=$SUFFIX)"
info "Siguiente paso: ./scripts/02-test-workloads.sh"
