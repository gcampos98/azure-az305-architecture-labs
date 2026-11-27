#!/usr/bin/env bash
# Despliega el Laboratorio 01B: VM + Azure Backup (LTR) + Site Recovery. Es idempotente.
# shellcheck source=00-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

require_login
require_extension
load_config
recover_suffix "$RG_PRI"
if [[ -z "${SUFFIX:-}" ]]; then SUFFIX="$(new_suffix)"; fi
set_names
save_state
load_identity
MARKER="AZ305-1B-$SUFFIX-dato-critico"

log "1. Comprobaciones previas (sufijo $SUFFIX)"
for ns in Microsoft.Compute Microsoft.Network Microsoft.Storage Microsoft.RecoveryServices \
  Microsoft.OperationalInsights Microsoft.Insights; do
  az provider register --namespace "$ns" --wait -o none
done

check_region() { # región
  local ok usage used limit
  ok="$(az vm list-skus -l "$1" --size "$VM_SIZE" --resource-type virtualMachines \
    --query "length([?name=='$VM_SIZE' && !(restrictions[?type=='Location'])])" -o tsv)"
  [[ "$ok" != "0" && -n "$ok" ]] ||
    die "$VM_SIZE no está disponible en $1 para tu suscripción. Exporta VM_SIZE (x64, 2 vCPU o más)."
  usage="$(az vm list-usage -l "$1" \
    --query "[?name.value=='cores'] | [0].join(' ', [to_string(currentValue), to_string(limit)])" -o tsv)"
  read -r used limit <<<"$usage"
  ((limit - used >= 2)) ||
    die "Cuota insuficiente en $1: $used de $limit vCPU en uso y se necesitan 2 libres."
  info "$1: $VM_SIZE disponible; vCPU en uso $used de $limit"
}

if ! exists az vm show -g "$RG_PRI" -n "$VM_NAME"; then
  check_region "$LOC_PRI" # VM de origen
  check_region "$LOC_DR"  # VM del Test Failover
fi

log "2. Grupos de recursos y Log Analytics"
ensure_rg "$RG_PRI" "$LOC_PRI"
ensure_rg "$RG_DR" "$LOC_DR"
ensure_rg "$RG_RESTORE" "$LOC_PRI"
exists az monitor log-analytics workspace show -g "$RG_PRI" -n "$LAW_NAME" ||
  az monitor log-analytics workspace create -g "$RG_PRI" -n "$LAW_NAME" -l "$LOC_PRI" -o none
LAW_ID="$(az monitor log-analytics workspace show -g "$RG_PRI" -n "$LAW_NAME" --query id -o tsv)"

log "3. Redes (origen con salida por NAT; destino y red aislada de pruebas)"
ensure_vnet() { # grupo nombre región prefijo subred
  exists az network vnet show -g "$1" -n "$2" ||
    az network vnet create -g "$1" -n "$2" -l "$3" --address-prefixes "$4" -o none
  exists az network vnet subnet show -g "$1" --vnet-name "$2" -n snet-workload ||
    az network vnet subnet create -g "$1" --vnet-name "$2" -n snet-workload \
      --address-prefixes "$5" --default-outbound false -o none
}
ensure_vnet "$RG_PRI" vnet-src "$LOC_PRI" 10.10.0.0/16 10.10.1.0/24
ensure_vnet "$RG_DR" vnet-dr "$LOC_DR" 10.20.0.0/16 10.20.1.0/24
# Red de pruebas: sin peering con otras redes; aísla la VM del Test Failover
ensure_vnet "$RG_DR" vnet-test "$LOC_DR" 10.30.0.0/16 10.30.1.0/24

# Run Command necesita salida por el puerto 443 hacia Azure para devolver resultados.
# La red de pruebas permite solo eso y bloquea el resto de Internet.
exists az network nsg show -g "$RG_DR" -n nsg-test ||
  az network nsg create -g "$RG_DR" -n nsg-test -l "$LOC_DR" -o none
az network nsg rule create -g "$RG_DR" --nsg-name nsg-test -n allow-azure-443 \
  --priority 100 --direction Outbound --access Allow --protocol Tcp \
  --destination-address-prefixes AzureCloud --destination-port-ranges 443 -o none
az network nsg rule create -g "$RG_DR" --nsg-name nsg-test -n deny-internet \
  --priority 4000 --direction Outbound --access Deny --protocol '*' \
  --destination-address-prefixes Internet --destination-port-ranges '*' -o none
exists az network public-ip show -g "$RG_DR" -n pip-nat-test ||
  az network public-ip create -g "$RG_DR" -n pip-nat-test -l "$LOC_DR" \
    --sku Standard --allocation-method Static -o none
exists az network nat gateway show -g "$RG_DR" -n nat-test ||
  az network nat gateway create -g "$RG_DR" -n nat-test -l "$LOC_DR" \
    --public-ip-addresses pip-nat-test -o none
az network vnet subnet update -g "$RG_DR" --vnet-name vnet-test -n snet-workload \
  --nat-gateway nat-test --network-security-group nsg-test -o none

exists az network nsg show -g "$RG_PRI" -n nsg-workload ||
  az network nsg create -g "$RG_PRI" -n nsg-workload -l "$LOC_PRI" -o none
exists az network public-ip show -g "$RG_PRI" -n pip-nat ||
  az network public-ip create -g "$RG_PRI" -n pip-nat -l "$LOC_PRI" \
    --sku Standard --allocation-method Static -o none
exists az network nat gateway show -g "$RG_PRI" -n nat-src ||
  az network nat gateway create -g "$RG_PRI" -n nat-src -l "$LOC_PRI" \
    --public-ip-addresses pip-nat -o none
az network vnet subnet update -g "$RG_PRI" --vnet-name vnet-src -n snet-workload \
  --nat-gateway nat-src --network-security-group nsg-workload -o none

log "4. VM de origen sin IP pública ($VM_SIZE)"
SUBNET_ID="$(az network vnet subnet show -g "$RG_PRI" --vnet-name vnet-src -n snet-workload --query id -o tsv)"
if ! exists az vm show -g "$RG_PRI" -n "$VM_NAME"; then
  az vm create -g "$RG_PRI" -n "$VM_NAME" -l "$LOC_PRI" \
    --image "$VM_IMAGE" --size "$VM_SIZE" \
    --admin-username "$VM_ADMIN" --generate-ssh-keys \
    --subnet "$SUBNET_ID" --public-ip-address "" --nsg "" \
    --storage-sku StandardSSD_LRS \
    --os-disk-delete-option Delete --nic-delete-option Delete \
    --tags "lab=$LAB_TAG" -o none
fi
VM_ID="$(az vm show -g "$RG_PRI" -n "$VM_NAME" --query id -o tsv)"

# El archivo marcador prueba que los datos llegan a la réplica y se pueden recuperar
if [[ -z "$RP_NAME" ]]; then
  info "Escribiendo el archivo marcador en la VM"
  OUTPUT="$(run_in_vm "$RG_PRI" "$VM_NAME" \
    "mkdir -p ${MARKER_PATH%/*} && echo '$MARKER' > $MARKER_PATH && sync && cat $MARKER_PATH")"
  grep -qF "$MARKER" <<<"$OUTPUT" || die "No se pudo confirmar el archivo marcador en la VM."
fi

log "5. Cuentas de almacenamiento (caché LRS y demostración $STG_SKU)"
ensure_storage() { # nombre sku permitir_clave
  exists az storage account show -g "$RG_PRI" -n "$1" ||
    az storage account create -g "$RG_PRI" -n "$1" -l "$LOC_PRI" --sku "$2" --kind StorageV2 \
      --min-tls-version TLS1_2 --allow-blob-public-access false \
      --allow-shared-key-access "$3" -o none
}
ensure_storage "$ST_CACHE" Standard_LRS true # Site Recovery necesita la clave en la caché
ensure_storage "$ST_GEO" "$STG_SKU" false    # Solo Microsoft Entra ID
GEO_ID="$(az storage account show -g "$RG_PRI" -n "$ST_GEO" --query id -o tsv)"
assign_role "Storage Blob Data Contributor" "$GEO_ID"
retry 12 20 az storage container create --account-name "$ST_GEO" -n config-backup \
  --auth-mode login -o none

log "6. Azure Backup: vault en $LOC_PRI, redundancia y directiva LTR"
exists az backup vault show -g "$RG_PRI" -n "$BKP_VAULT" ||
  az backup vault create -g "$RG_PRI" -n "$BKP_VAULT" -l "$LOC_PRI" -o none
ITEMS="$(backup_item_count)"
if [[ "$ITEMS" == "0" ]]; then
  # La redundancia solo se puede cambiar antes de proteger el primer elemento
  az backup vault backup-properties set -g "$RG_PRI" -n "$BKP_VAULT" \
    --backup-storage-redundancy "$VAULT_REDUNDANCY" -o none
  if [[ "$ENABLE_CRR" == "true" ]]; then
    az backup vault backup-properties set -g "$RG_PRI" -n "$BKP_VAULT" \
      --cross-region-restore-flag true -o none
  fi
fi
BKP_VAULT_ID="$(az backup vault show -g "$RG_PRI" -n "$BKP_VAULT" --query id -o tsv)"
az monitor diagnostic-settings create --name diag-law --resource "$BKP_VAULT_ID" \
  --workspace "$LAW_ID" --export-to-resource-specific true \
  --logs '[{"category":"CoreAzureBackup","enabled":true},{"category":"AddonAzureBackupJobs","enabled":true},{"category":"AddonAzureBackupPolicy","enabled":true}]' \
  -o none
if ! exists az backup policy show -g "$RG_PRI" -v "$BKP_VAULT" -n "$POLICY_NAME"; then
  POLICY_JSON="$(python3 "$LAB_DIR/scripts/ltr_policy.py" \
    "$LTR_DAILY" "$LTR_WEEKLY" "$LTR_MONTHLY" "$LTR_YEARLY")"
  az backup policy create -g "$RG_PRI" -v "$BKP_VAULT" -n "$POLICY_NAME" \
    --backup-management-type AzureIaasVM --policy "$POLICY_JSON" -o none
fi
if [[ "$ITEMS" == "0" ]]; then
  az backup protection enable-for-vm -g "$RG_PRI" -v "$BKP_VAULT" \
    --vm "$VM_ID" --policy-name "$POLICY_NAME" -o none
fi

log "7. Site Recovery: vault, fabrics, contenedores y directiva en $LOC_DR"
exists az backup vault show -g "$RG_DR" -n "$ASR_VAULT" ||
  az backup vault create -g "$RG_DR" -n "$ASR_VAULT" -l "$LOC_DR" -o none
ASR_VAULT_ID="$(az backup vault show -g "$RG_DR" -n "$ASR_VAULT" --query id -o tsv)"
az monitor diagnostic-settings create --name diag-law --resource "$ASR_VAULT_ID" \
  --workspace "$LAW_ID" --export-to-resource-specific true \
  --logs '[{"category":"AzureSiteRecoveryJobs","enabled":true},{"category":"ASRReplicatedItems","enabled":true}]' \
  -o none

VAULT_ARGS=(-g "$RG_DR" --vault-name "$ASR_VAULT")
ensure_fabric() { # fabric región
  exists az site-recovery fabric show "${VAULT_ARGS[@]}" --fabric-name "$1" ||
    az site-recovery fabric create "${VAULT_ARGS[@]}" -n "$1" \
      --custom-details "{azure:{location:$2}}" -o none
}
ensure_container() { # fabric contenedor
  exists az site-recovery protection-container show "${VAULT_ARGS[@]}" --fabric-name "$1" -n "$2" ||
    az site-recovery protection-container create "${VAULT_ARGS[@]}" --fabric-name "$1" -n "$2" \
      --provider-input "[{instance-type:A2A}]" -o none
}
ensure_fabric "$FAB_SRC" "$LOC_PRI"
ensure_fabric "$FAB_DR" "$LOC_DR"
ensure_container "$FAB_SRC" "$CONT_SRC"
ensure_container "$FAB_DR" "$CONT_DR"

# Puntos de recuperación: 24 h; consistentes con la aplicación cada 4 h
exists az site-recovery policy show "${VAULT_ARGS[@]}" -n "$ASR_POLICY" ||
  az site-recovery policy create "${VAULT_ARGS[@]}" -n "$ASR_POLICY" \
    --provider-input "{a2a:{multi-vm-sync-status:Enable,recovery-point-history:1440,app-consistent-frequency-in-minutes:240,crash-consistent-frequency-in-minutes:5}}" -o none
ASR_POLICY_ID="$(az site-recovery policy show "${VAULT_ARGS[@]}" -n "$ASR_POLICY" --query id -o tsv)"
CONT_DR_ID="$(az site-recovery protection-container show "${VAULT_ARGS[@]}" \
  --fabric-name "$FAB_DR" -n "$CONT_DR" --query id -o tsv)"

exists az site-recovery protection-container mapping show "${VAULT_ARGS[@]}" \
  --fabric-name "$FAB_SRC" --protection-container "$CONT_SRC" --mapping-name "$MAP_CONT" ||
  az site-recovery protection-container mapping create "${VAULT_ARGS[@]}" \
    --fabric-name "$FAB_SRC" --protection-container "$CONT_SRC" -n "$MAP_CONT" \
    --policy-id "$ASR_POLICY_ID" --target-container "$CONT_DR_ID" \
    --provider-input "{a2a:{agent-auto-update-status:Disabled}}" -o none

SRC_VNET_ID="$(az network vnet show -g "$RG_PRI" -n vnet-src --query id -o tsv)"
DR_VNET_ID="$(az network vnet show -g "$RG_DR" -n vnet-dr --query id -o tsv)"
exists az site-recovery network mapping show "${VAULT_ARGS[@]}" \
  --fabric-name "$FAB_SRC" --network-name "$NET_ASR" -n "$MAP_NET" ||
  az site-recovery network mapping create "${VAULT_ARGS[@]}" \
    --fabric-name "$FAB_SRC" --network-name "$NET_ASR" -n "$MAP_NET" \
    --recovery-network-id "$DR_VNET_ID" --recovery-fabric-name "$FAB_DR" \
    --fabric-details "{azure-to-azure:{primary-network-id:$SRC_VNET_ID}}" -o none

log "8. Habilitar la replicación $LOC_PRI -> $LOC_DR"
ITEMS="$(asr_item_count)"
if [[ "$ITEMS" == "0" ]]; then
  DISK_ID="$(az vm show -g "$RG_PRI" -n "$VM_NAME" --query storageProfile.osDisk.managedDisk.id -o tsv)"
  CACHE_ID="$(az storage account show -g "$RG_PRI" -n "$ST_CACHE" --query id -o tsv)"
  RG_DR_ID="$(az group show -n "$RG_DR" --query id -o tsv)"
  DISK="{disk-id:$DISK_ID,primary-staging-azure-storage-account-id:$CACHE_ID,recovery-resource-group-id:$RG_DR_ID,recovery-replica-disk-account-type:Standard_LRS,recovery-target-disk-account-type:StandardSSD_LRS}"
  az site-recovery protected-item create "${ITEM_ARGS[@]}" -n "$VM_NAME" \
    --policy-id "$ASR_POLICY_ID" \
    --provider-details "{a2a:{fabric-object-id:$VM_ID,recovery-container-id:$CONT_DR_ID,recovery-resource-group-id:$RG_DR_ID,recovery-azure-network-id:$DR_VNET_ID,recovery-subnet-name:snet-workload,vm-managed-disks:[$DISK]}}" \
    --no-wait -o none
  info "Solicitud enviada."
else
  info "La VM ya tiene un elemento de replicación."
fi

log "Despliegue enviado"
cat <<MSG
  La replicación inicial continúa en Azure (puede tardar bastante; consulta el avance).
  Estado:        ./scripts/02-test.sh status
  Respaldo:      ./scripts/02-test.sh backup      (puede ejecutarse en paralelo)
  Al terminar:   ./scripts/03-cleanup.sh
MSG
