#!/usr/bin/env bash
# Pruebas del Laboratorio 01.
# Uso: ./scripts/02-test-workloads.sh [all|storage|keyvault|failover|backup|backup-status|restore|activity|metrics]
# SKIP_PROBE=true ejecuta el failover sin cliente SQL (no mide RTO ni RPO).
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"

ACTION="${1:-all}"
case "$ACTION" in
  all|storage|keyvault|failover|backup|backup-status|restore|activity|metrics) ;;
  *) sed -n '2,4p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
SKIP_PROBE="${SKIP_PROBE:-false}"

TMP_DIR="$(mktemp -d)"
PROBE_PID=""
on_exit() {
  if [[ -n "$PROBE_PID" ]]; then kill "$PROBE_PID" 2>/dev/null || true; fi
  rm -rf "$TMP_DIR"
}
trap on_exit EXIT

require_login
load_config
recover_suffix
[[ -n "${SUFFIX:-}" ]] || die "No hay despliegue. Ejecuta primero ./scripts/01-deploy.sh"
set_names

test_storage() {
  log "Redundancia GZRS"
  save_evidence 02-storage-gzrs-status.txt az storage account show -n "$STG_NAME" -g "$RG_PRI" \
    --query "{Cuenta:name, SKU:sku.name, RegionPrimaria:primaryLocation, EstadoPri:statusOfPrimary, RegionSecundaria:secondaryLocation, EstadoSec:statusOfSecondary}" -o table
}

test_keyvault() {
  log "Backup y restore de secreto: $KV_PRI -> $KV_SEC"
  local name="lab01-bcdr-secret-$SUFFIX"
  if exists az keyvault secret show --vault-name "$KV_SEC" --name "$name"; then
    warn "El secreto ya existe en el vault secundario; se omite el restore."
  else
    if ! exists az keyvault secret show --vault-name "$KV_PRI" --name "$name"; then
      az keyvault secret set --vault-name "$KV_PRI" --name "$name" --value "ValorPruebaBCDR-$SUFFIX" -o none ||
        die "No se pudo crear el secreto. Si acabas de desplegar, espera la propagación de RBAC."
    fi
    az keyvault secret backup --vault-name "$KV_PRI" --name "$name" --file "$TMP_DIR/secret.kvbak" -o none
    az keyvault secret restore --vault-name "$KV_SEC" --file "$TMP_DIR/secret.kvbak" -o none
  fi
  save_evidence 04-kv-secret-restored.txt az keyvault secret show --vault-name "$KV_SEC" --name "$name" \
    --query "{VaultSecundario:id, Habilitado:attributes.enabled, UltimaActualizacion:attributes.updated}" -o table
}

# ---------- Failover SQL ----------
setup_sql_client() {
  # En Cloud Shell, sqlcmd puede estar instalado fuera del PATH
  local tools="${MSSQL_BIN:-/opt/mssql-tools18/bin}"
  if ! command -v sqlcmd >/dev/null && [[ -x "$tools/sqlcmd" ]]; then PATH="$PATH:$tools"; fi
  command -v sqlcmd >/dev/null || die "No se encontró sqlcmd. Usa SKIP_PROBE=true para omitir la medición."
  local ip par token
  ip="$(curl -fsS --max-time 10 https://api.ipify.org)" || die "No se pudo obtener la IP pública."
  for par in "$RG_PRI:$SQL_PRI" "$RG_SEC:$SQL_SEC"; do
    az sql server firewall-rule create -g "${par%%:*}" -s "${par##*:}" -n cloudshell \
      --start-ip-address "$ip" --end-ip-address "$ip" -o none
  done
  if sqlcmd --version >/dev/null 2>&1; then    # go-sqlcmd
    SQL_AUTH=(--authentication-method=ActiveDirectoryAzCli)
  else                                         # sqlcmd ODBC: token en archivo UTF-16LE
    token="$(az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv)" ||
      die "No se obtuvo token para Azure SQL. Ejecuta: az login --use-device-code"
    (umask 077; printf '%s' "$token" | iconv -f ascii -t UTF-16LE >"$TMP_DIR/token")
    SQL_AUTH=(-G -P "$TMP_DIR/token")
  fi
}

sql() { # consulta contra el listener de lectura/escritura
  sqlcmd -S "tcp:$FOG_NAME.database.windows.net,1433" -d "$SQL_DB" "${SQL_AUTH[@]}" \
    -b -l 5 -t 10 -h -1 -W -Q "SET NOCOUNT ON; $1"
}

count_rows() { sql "SELECT COUNT(*) FROM dbo.bcdr_probe;" | tr -d '\r ' | grep -E '^[0-9]+$' | tail -n1; }

probe_loop() { # una escritura cada ~2 s; registra el servidor que la confirmó
  local out
  while [[ ! -f "$TMP_DIR/stop" ]]; do
    if out="$(sql "INSERT dbo.bcdr_probe DEFAULT VALUES; SELECT @@SERVERNAME;" 2>/dev/null)"; then
      echo "$(date -u +%s) $(date -u +%H:%M:%SZ) OK $(tr -d '\r' <<<"$out" | tail -n1)"
    else
      echo "$(date -u +%s) $(date -u +%H:%M:%SZ) FAIL -"
    fi
    sleep "${PROBE_INTERVAL:-2}"
  done >>"$TMP_DIR/probe.log"
}

switch_to() { # etiqueta grupo-destino servidor-destino
  local start secs before="" after="" acked gap seen=false
  log "$1: nuevo primario $3"
  if [[ "$SKIP_PROBE" != "true" ]]; then
    before="$(count_rows)"
    rm -f "$TMP_DIR/stop" "$TMP_DIR/probe.log"
    probe_loop & PROBE_PID=$!
    sleep "${PROBE_WARMUP:-15}"
  fi
  start="$(date +%s)"
  az sql failover-group set-primary -n "$FOG_NAME" -g "$2" -s "$3" -o none
  secs=$(($(date +%s) - start))

  {
    echo
    echo "[$1] destino: $3"
    echo "Duración del comando set-primary (s): $secs"
  } >>"$TMP_DIR/report"

  if [[ "$SKIP_PROBE" != "true" ]]; then
    for _ in $(seq 1 "${PROBE_RETRIES:-90}"); do
      if tail -n1 "$TMP_DIR/probe.log" 2>/dev/null | grep -qi " OK $3"; then seen=true; break; fi
      sleep "${PROBE_INTERVAL:-2}"
    done
    touch "$TMP_DIR/stop"; wait "$PROBE_PID"; PROBE_PID=""
    [[ "$seen" == "true" ]] || die "No se confirmaron escrituras en $3. Revisa el estado del grupo."
    after="$(count_rows)"
    acked="$(grep -c ' OK ' "$TMP_DIR/probe.log" || true)"
    gap="$(awk '$3=="OK"{ if (p && $1-p>m) m=$1-p; p=$1 } END{print m+0}' "$TMP_DIR/probe.log")"
    {
      echo "Mayor brecha entre escrituras confirmadas, RTO observado (s): $gap"
      echo "Escrituras confirmadas durante la prueba: $acked"
      echo "Filas nuevas en el nuevo primario: $((after - before))"
      echo "Escrituras confirmadas perdidas, RPO observado: $((acked > after - before ? acked - (after - before) : 0))"
      echo "hora_utc resultado servidor"
      cut -d' ' -f2- "$TMP_DIR/probe.log"
    } >>"$TMP_DIR/report"
  else
    echo "RTO y RPO: no medidos (SKIP_PROBE=true)" >>"$TMP_DIR/report"
  fi
  az sql failover-group show -n "$FOG_NAME" -g "$2" -s "$3" \
    --query "{Grupo:name, RolDestino:replicationRole, EstadoReplicacion:replicationState, Politica:readWriteEndpoint.failoverPolicy}" \
    -o table >>"$TMP_DIR/report"
}

test_failover() {
  local members role
  members="$(az sql failover-group show -g "$RG_PRI" -s "$SQL_PRI" -n "$FOG_NAME" \
    --query "length(databases[?ends_with(@, '/databases/$SQL_DB')] || \`[]\`)" -o tsv)"
  [[ "$members" != "0" ]] || die "$SQL_DB no está en el Failover Group. Ejecuta ./scripts/01-deploy.sh"
  role="$(az sql failover-group show -g "$RG_PRI" -s "$SQL_PRI" -n "$FOG_NAME" --query replicationRole -o tsv)"

  if [[ "$SKIP_PROBE" != "true" ]]; then
    setup_sql_client
  fi
  if [[ "$role" != "Primary" ]]; then
    warn "$SQL_PRI no es primario: primero se restaura el rol."
    az sql failover-group set-primary -n "$FOG_NAME" -g "$RG_PRI" -s "$SQL_PRI" -o none
  fi
  if [[ "$SKIP_PROBE" != "true" ]]; then
    sql "IF OBJECT_ID('dbo.bcdr_probe') IS NULL CREATE TABLE dbo.bcdr_probe(id int IDENTITY PRIMARY KEY, ts datetime2 DEFAULT SYSUTCDATETIME());" ||
      die "Sin conexión SQL con el listener; no se inicia el failover. (SKIP_PROBE=true para omitir la medición)"
  fi

  echo "Prueba de failover planificado: $FOG_NAME ($SQL_DB)" >"$TMP_DIR/report"
  switch_to "FAILOVER" "$RG_SEC" "$SQL_SEC"
  sleep "${FAILBACK_WAIT:-30}"
  switch_to "FAILBACK" "$RG_PRI" "$SQL_PRI"
  save_evidence 01-sql-failover-status.txt cat "$TMP_DIR/report"
}

# ---------- Backup y restore ----------
latest_job() { # operación
  az backup job list -g "$RG_PRI" -v "$RSV_NAME" \
    --query "sort_by([?properties.operation=='$1' && properties.entityFriendlyName=='$VM_NAME'], &properties.startTime)[-1].name" -o tsv
}

job_status() {
  az backup job show -g "$RG_PRI" -v "$RSV_NAME" -n "$1" --query properties.status -o tsv
}

wait_job() { # id archivo-evidencia
  local status="" i
  for i in $(seq 1 "${JOB_POLLS:-30}"); do
    status="$(job_status "$1")"
    info "Estado del trabajo ($i): $status"
    case "$status" in
      InProgress|Cancelling) sleep "${JOB_WAIT:-30}" ;;
      *) break ;;
    esac
  done
  case "$status" in
    Completed|CompletedWithWarnings)
      save_evidence "$2" az backup job show -g "$RG_PRI" -v "$RSV_NAME" -n "$1" \
        --query "{Operacion:properties.operation, Estado:properties.status, Inicio:properties.startTime, Fin:properties.endTime, Duracion:properties.duration}" -o table ;;
    InProgress)
      warn "Sigue en curso: no se guarda evidencia. Revisa luego con './scripts/02-test-workloads.sh backup-status'." ;;
    *) die "El trabajo terminó con estado '$status'. Revisa el detalle en el vault." ;;
  esac
}

test_backup() {
  log "Respaldo de $VM_NAME"
  local job status=""
  job="$(latest_job Backup)"
  if [[ -n "$job" && "$job" != "None" ]]; then status="$(job_status "$job")"; fi
  if [[ "$status" == "InProgress" ]]; then
    info "Ya hay un respaldo en curso; se espera ese trabajo."
  else
    job="$(az backup protection backup-now -g "$RG_PRI" -v "$RSV_NAME" -c "$VM_NAME" -i "$VM_NAME" \
      --backup-management-type AzureIaasVM --retain-until "$(date -u -d '+7 days' +%d-%m-%Y)" \
      --query name -o tsv)"
  fi
  wait_job "$job" 03-backup-job-completed.txt
}

test_backup_status() {
  log "Último trabajo de respaldo"
  local job
  job="$(latest_job Backup)"
  [[ -n "$job" && "$job" != "None" ]] || die "No hay trabajos de respaldo."
  JOB_POLLS=1 JOB_WAIT=0 wait_job "$job" 03-backup-job-completed.txt
}

test_restore() {
  log "Restauración de discos en $RG_RESTORE"
  local rp job staging="stgaz305lrs$SUFFIX"
  rp="$(az backup recoverypoint list -g "$RG_PRI" -v "$RSV_NAME" -c "$VM_NAME" -i "$VM_NAME" \
    --backup-management-type AzureIaasVM --workload-type VM --query "[0].name" -o tsv)"
  [[ -n "$rp" && "$rp" != "None" ]] || die "Aún no hay puntos de recuperación."
  az group create -n "$RG_RESTORE" -l "$LOC_PRI" --tags lab=az305-01 suffix="$SUFFIX" -o none
  # Azure Backup rechaza GZRS como destino temporal: se usa una cuenta LRS aparte
  exists az storage account show -g "$RG_PRI" -n "$staging" ||
    az storage account create -n "$staging" -g "$RG_PRI" -l "$LOC_PRI" \
      --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
      --https-only true --allow-blob-public-access false -o none
  job="$(az backup restore restore-disks -g "$RG_PRI" -v "$RSV_NAME" -c "$VM_NAME" -i "$VM_NAME" \
    --rp-name "$rp" --storage-account "$staging" --storage-account-resource-group "$RG_PRI" \
    --target-resource-group "$RG_RESTORE" --query name -o tsv)"
  wait_job "$job" 07-vm-restore-disks.txt
}

# ---------- Observabilidad ----------
activity_report() {
  local rg
  echo "Hora | Operacion | Estado | Grupo"
  for rg in "$RG_PRI" "$RG_SEC"; do
    az monitor activity-log list -g "$rg" --offset 6h --max-events 200 \
      --query "[?contains(operationName.value, 'failoverGroups/failover')].[eventTimestamp, operationName.value, status.value, resourceGroupName]" -o tsv ||
      return 1
  done | sort -r | sed 's/\t/ | /g'
}

test_activity() {
  log "Activity Log: operaciones de failover (últimas 6 horas)"
  local data
  data="$(activity_report)"
  if [[ "$(wc -l <<<"$data")" -le 1 ]]; then
    warn "Aún no hay eventos (la ingesta puede tardar unos minutos). No se guarda evidencia."
    return 0
  fi
  save_evidence 06d-sql-failover-activity-log.txt echo "$data"
}

metrics_report() {
  local par db_id
  for par in "$RG_PRI:$SQL_PRI" "$RG_SEC:$SQL_SEC"; do
    echo
    echo "Servidor: ${par##*:}"
    db_id="$(az sql db show -g "${par%%:*}" -s "${par##*:}" -n "$SQL_DB" --query id -o tsv)" || return 1
    az monitor metrics list --resource "$db_id" \
      --metrics availability connection_successful connection_failed blocked_by_firewall deadlock \
      --offset 2h --interval PT5M -o table || return 1
  done
}

test_metrics() {
  log "Métricas SQL (últimas 2 horas)"
  save_evidence 05-sql-metrics.txt metrics_report
}

case "$ACTION" in
  storage)       test_storage ;;
  keyvault)      test_keyvault ;;
  failover)      test_failover ;;
  backup)        test_backup ;;
  backup-status) test_backup_status ;;
  restore)       test_restore ;;
  activity)      test_activity ;;
  metrics)       test_metrics ;;
  all)
    test_storage
    test_keyvault
    test_failover
    test_metrics
    test_activity
    test_backup
    log "PRUEBAS FINALIZADAS"
    info "La restauración se prueba aparte: ./scripts/02-test-workloads.sh restore" ;;
esac
