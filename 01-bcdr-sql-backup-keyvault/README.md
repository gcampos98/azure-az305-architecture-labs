# Laboratorio 01: Continuidad Empresarial y Recuperación ante Desastres (BCDR)

> **Estado:** Completado. Ejecutado en Azure desde Cloud Shell el 2026-11-28, con evidencia. Las pruebas fuera de alcance están en [Limitaciones](#limitaciones).
> **Enfoque AZ-305:** continuidad del negocio, almacenamiento de datos y monitoreo.

## Arquitectura

```mermaid
flowchart LR
    CS["Azure Cloud Shell (cliente de prueba)"]

    subgraph PRI["Región primaria: centralus"]
        SQL1["Azure SQL Server + db-ventas-critica"]
        VM["VM Arm64 Standard_B2pts_v2 (sin IP pública)"]
        RSV["Recovery Services Vault"]
        KV1["Key Vault (RBAC)"]
        STG1["Storage GZRS (3 copias zonales)"]
        LAW["Log Analytics Workspace"]
    end

    subgraph PAIR["Región emparejada: eastus2"]
        STG2["Réplica Storage (3 copias LRS)"]
        BK["Copia georredundante del vault"]
    end

    subgraph SEC["Región secundaria SQL: westus3"]
        SQL2["Azure SQL Server + réplica geográfica"]
        KV2["Key Vault destino (RBAC)"]
    end

    CS -->|"listener del Failover Group"| SQL1
    SQL1 <-->|"Failover Group (política Manual)"| SQL2
    STG1 -->|"Replicación asíncrona"| STG2
    VM -->|"Azure Backup"| RSV
    RSV -. "GRS; restaurar allí requiere CRR" .-> BK
    KV1 -. "Backup/restore manual de secretos" .-> KV2
    SQL1 --> LAW
    SQL2 --> LAW
    KV1 --> LAW
    KV2 --> LAW
    STG1 --> LAW
    RSV --> LAW
```

### Alcance real del DR

| Componente | ¿Recuperable si cae `centralus`? | Cómo |
| :--- | :--- | :--- |
| Azure SQL | Sí, en `westus3` | Failover del grupo (manual) |
| Storage | Sí, en `eastus2` | Failover de la cuenta (no probado). Sin RA-GZRS no hay lectura secundaria previa |
| Key Vault | Solo los secretos copiados | Copia puntual en `westus3`; repetir tras cada rotación |
| VM | **No en `westus3`** | Con `ENABLE_CRR=true`, restauración en `eastus2`. Para otra región, Azure Site Recovery (no admite Arm64; ver [Lab 01B](../01b-bcdr-asr-azure-backup)) |

## Decisiones de arquitectura (ADR)

| Decisión | Elección | Alternativas | Motivo |
| :--- | :--- | :--- | :--- |
| Redundancia de Storage | `Standard_GZRS` | LRS, ZRS, RA-GZRS | Redundancia zonal en la primaria y copia regional. RA-GZRS agrega lectura secundaria a mayor costo |
| Destino temporal de la restauración | Cuenta `Standard_LRS` aparte | Reutilizar la cuenta GZRS | Azure Backup rechaza GZRS (`UserErrorBCMRestoreStorageAccountTypeNotSupported`) y pide redundancia local o geográfica |
| Failover de SQL | Failover Group con política `Manual` (*customer managed*) | Política `Automatic` (*Microsoft managed*) | Microsoft recomienda `Manual`: tú decides cuándo conmutar |
| Resiliencia zonal de SQL | No incluida (`S0`) | Zone redundancy en un nivel que la admita | Es complementaria: cubre fallas de zona, no de región |
| Protección de VM | Azure Backup | Azure Site Recovery | Backup recupera datos desde puntos en el tiempo; Site Recovery replica la VM para conmutar con menor RPO/RTO |
| Acceso a la VM | Sin IP pública ni reglas de entrada | IP pública con SSH 22 | Reduce la superficie de ataque. Administración con Run Command |
| Autenticación SQL | Microsoft Entra ID (solo Entra en servidores nuevos) | Usuario y contraseña | Sin contraseñas que custodiar |
| Autorización Key Vault | Azure RBAC | Access policies | Modelo unificado y rol mínimo (*Secrets Officer*) |

## RPO / RTO

Los objetivos son propuestas para el lab; ajústalos a tu escenario.

| Componente | RPO objetivo | RTO objetivo | Medido | Fuente |
| :--- | :--- | :--- | :--- | :--- |
| SQL, failover planificado | 0 | < 1 min | RPO 0; RTO observado 8 s | Bloque `01-sql-failover-status.txt` |
| SQL, failback planificado | 0 | < 1 min | RPO 0; RTO observado 7 s | Bloque `01-sql-failover-status.txt` |
| SQL, failover forzado | ~5 s | < 1 min | No se prueba | n/a |
| Storage GZRS | A definir | A definir | No se prueba | n/a |
| VM (Azure Backup) | 24 h (política diaria) | A definir | Respaldo: 26 min. Restauración de discos: 1 min 5 s | Bloques `03-backup-job-completed.txt` y `07-vm-restore-disks.txt` |

El RTO observado es la mayor brecha entre dos escrituras confirmadas e incluye el intervalo de sondeo (~2 s más el tiempo de conexión). La restauración de discos no equivale a recuperar la VM: no incluye crearla ni validarla.

En el failover, la sonda registró errores después de la primera escritura en el nuevo primario y su última muestra fue un error (`15:14:26Z`). Por eso los 8 s no demuestran que la conexión quedara estable en ese momento: una aplicación necesita reintentos.

## Ejecución en Azure Cloud Shell (Bash)

**Prerrequisitos**
- Rol que permita crear recursos y asignar roles (por ejemplo, Owner de la suscripción).
- Usa una sesión con almacenamiento montado si quieres conservar archivos y evidencias.
- Si un comando falla por token o audiencia: `az login --use-device-code`.

```bash
cd 01-bcdr-sql-backup-keyvault
./scripts/01-deploy.sh                 # reejecutable
./scripts/02-test-workloads.sh         # todas las pruebas, salvo restore
./scripts/02-test-workloads.sh restore # cuando el backup esté "Completed"
./scripts/03-cleanup.sh                # pide escribir BORRAR
```

> Cloud Shell cierra la sesión tras 20 minutos sin interacción. Si ocurre, vuelve a ejecutar el mismo comando.
> Para un respaldo en curso usa `./scripts/02-test-workloads.sh backup-status`.
> Sin subcomando se ejecutan todas las pruebas (salvo `restore`) y se reemplazan sus bloques de evidencia.

| Variable | Uso |
| :--- | :--- |
| `SUFFIX` | Fuerza el sufijo de un despliegue |
| `ENABLE_NAT=true` | Agrega NAT Gateway si la VM necesita salida (genera costo) |
| `ENABLE_CRR=true` | Habilita Cross Region Restore en el vault |
| `VM_SIZE`, `VM_IMAGE` | Cambian la VM; deben coincidir en arquitectura |
| `SKIP_PROBE=true` | Failover sin cliente SQL (no mide RTO/RPO) |

## Evidencias

Salidas reales en [`evidence/EVIDENCIA-CONSOLIDADA.md`](./evidence/EVIDENCIA-CONSOLIDADA.md), un bloque por prueba.

| Bloque | Contenido | Resultado registrado |
| :--- | :--- | :--- |
| `01-sql-failover-status.txt` | Failover, failback, RTO/RPO observados | `set-primary`: 34 s y 33 s. Escrituras confirmadas y presentes: 17/17 y 19/19 |
| `02-storage-gzrs-status.txt` | Regiones y SKU | GZRS: `centralus` y `eastus2` disponibles |
| `03-backup-job-completed.txt` | Respaldo bajo demanda | `Completed` en 26 min |
| `04-kv-secret-restored.txt` | Secreto en el vault secundario | Secreto habilitado en el destino |
| `05-sql-metrics.txt` | Métricas de ambos servidores | Disponibilidad 100 % (intervalos de 5 min); conexiones durante las pruebas y 1 error de sistema |
| `06d-sql-failover-activity-log.txt` | Operaciones de failover | `Succeeded` en las operaciones de failover y failback |
| `07-vm-restore-disks.txt` | Restauración de discos | `Completed` en 1 min 5 s |

El tiempo del comando `set-primary` no es el RTO. Para medir RTO y RPO, ejecuta `failover` sin `SKIP_PROBE` (usa `sqlcmd`; si en Cloud Shell no está en el `PATH`, el script lo busca en `/opt/mssql-tools18/bin`). `activity` consulta las últimas 6 horas y los eventos pueden tardar unos minutos en aparecer.

Los scripts ocultan GUIDs, correos e IPv4. Revisa igualmente la evidencia antes de publicarla.

## Hallazgos de la ejecución

| Hallazgo | Ajuste |
| :--- | :--- |
| Azure Backup rechazó la cuenta GZRS como destino temporal de la restauración | Los scripts crean una cuenta `Standard_LRS` |
| `sqlcmd` estaba instalado, pero fuera del `PATH` de la sesión | El script lo busca en `/opt/mssql-tools18/bin` |
| El Activity Log tarda unos minutos en registrar el resultado | Ejecutar `activity` después de las pruebas |
| Las métricas de 5 minutos no muestran las interrupciones de segundos | El RTO se mide con la sonda de escrituras |

## Costos y limpieza

- Generan consumo: la base `S0` y su réplica, Storage GZRS y una cuenta LRS para restaurar, la VM y su disco, Azure Backup, Log Analytics y, si lo activas, NAT Gateway.
- `03-cleanup.sh` solo informa éxito cuando comprueba que los grupos no existen, y purga los Key Vault del lab.
- El *soft delete* de Azure Backup puede retener el vault y su grupo. En ese caso el script elimina los demás recursos, informa limpieza incompleta y debes repetirlo al vencer la retención.

## Limitaciones

- No se prueba failover forzado, failover de Storage ni recuperación completa de una VM.
- Los Key Vault no tienen *purge protection* para permitir limpiar el lab; en producción debe activarse.
- SQL y Key Vault usan acceso público (SQL restringido por firewall). En producción evaluar Private Endpoints.
