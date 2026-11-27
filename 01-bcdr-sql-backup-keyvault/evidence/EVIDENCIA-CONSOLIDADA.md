# Evidencia Técnica Consolidada — AZ-305

> Salidas sanitizadas automáticamente (sin GUIDs, correos ni direcciones IPv4).

<!-- BEGIN:02-storage-gzrs-status.txt -->
## Bloque: `02-storage-gzrs-status.txt`
- **Generado (UTC):** `2026-11-27T22:01:58Z`

```text
Cuenta              SKU            RegionPrimaria    EstadoPri    RegionSecundaria    EstadoSec
------------------  -------------  ----------------  -----------  ------------------  -----------
stgaz305gzrs3b4e88  Standard_GZRS  centralus         available    eastus2             available
```
<!-- END:02-storage-gzrs-status.txt -->

<!-- BEGIN:04-kv-secret-restored.txt -->
## Bloque: `04-kv-secret-restored.txt`
- **Generado (UTC):** `2026-11-27T22:02:14Z`

```text
VaultSecundario                                                                                                Habilitado    UltimaActualizacion
-------------------------------------------------------------------------------------------------------------  ------------  -------------------------
https://kv-az305-sec-3b4e88.vault.azure.net/secrets/lab01-bcdr-secret-3b4e88/a4e6c8dc6b6d485bb1288c87c07be791  True          2026-11-27T22:02:07+00:00
```
<!-- END:04-kv-secret-restored.txt -->

<!-- BEGIN:01-sql-failover-status.txt -->
## Bloque: `01-sql-failover-status.txt`
- **Generado (UTC):** `2026-11-27T22:04:23Z`

```text
Prueba de failover planificado: fog-az305-3b4e88 (db-ventas-critica)

[FAILOVER] destino: sql-az305-sec-3b4e88
Duración del comando set-primary (s): 55
RTO y RPO: no medidos (SKIP_PROBE=true)
Grupo             RolDestino    EstadoReplicacion    Politica
----------------  ------------  -------------------  ----------
fog-az305-3b4e88  Primary       CATCH_UP             Manual

[FAILBACK] destino: sql-az305-pri-3b4e88
Duración del comando set-primary (s): 33
RTO y RPO: no medidos (SKIP_PROBE=true)
Grupo             RolDestino    EstadoReplicacion    Politica
----------------  ------------  -------------------  ----------
fog-az305-3b4e88  Primary       CATCH_UP             Manual
```
<!-- END:01-sql-failover-status.txt -->

<!-- BEGIN:05-sql-metrics.txt -->
## Bloque: `05-sql-metrics.txt`
- **Generado (UTC):** `2026-11-27T22:04:32Z`

```text

Servidor: sql-az305-pri-3b4e88
Timestamp             Name                                Average    Total
--------------------  ----------------------------------  ---------  -------
2026-11-27T20:04:00Z  Availability                        100.0
2026-11-27T20:09:00Z  Availability                        100.0
2026-11-27T20:14:00Z  Availability                        100.0
2026-11-27T20:19:00Z  Availability                        100.0
2026-11-27T20:24:00Z  Availability                        100.0
2026-11-27T20:29:00Z  Availability                        100.0
2026-11-27T20:34:00Z  Availability                        100.0
2026-11-27T20:39:00Z  Availability                        100.0
2026-11-27T20:44:00Z  Availability                        100.0
2026-11-27T20:49:00Z  Availability                        100.0
2026-11-27T20:54:00Z  Availability                        100.0
2026-11-27T20:59:00Z  Availability                        100.0
2026-11-27T21:04:00Z  Availability                        100.0
2026-11-27T21:09:00Z  Availability                        100.0
2026-11-27T21:14:00Z  Availability                        100.0
2026-11-27T21:19:00Z  Availability                        100.0
2026-11-27T21:24:00Z  Availability                        100.0
2026-11-27T21:29:00Z  Availability                        100.0
2026-11-27T21:34:00Z  Availability                        100.0
2026-11-27T21:39:00Z  Availability                        100.0
2026-11-27T21:44:00Z  Availability                        100.0
2026-11-27T21:49:00Z  Availability                        100.0
2026-11-27T21:54:00Z  Availability                        100.0
2026-11-27T21:59:00Z  Availability                        100.0
2026-11-27T20:04:00Z  Successful Connections                         0.0
2026-11-27T20:09:00Z  Successful Connections                         0.0
2026-11-27T20:14:00Z  Successful Connections                         0.0
2026-11-27T20:19:00Z  Successful Connections                         0.0
2026-11-27T20:24:00Z  Successful Connections                         0.0
2026-11-27T20:29:00Z  Successful Connections                         0.0
2026-11-27T20:34:00Z  Successful Connections                         0.0
2026-11-27T20:39:00Z  Successful Connections                         0.0
2026-11-27T20:44:00Z  Successful Connections                         0.0
2026-11-27T20:49:00Z  Successful Connections                         0.0
2026-11-27T20:54:00Z  Successful Connections                         0.0
2026-11-27T20:59:00Z  Successful Connections                         0.0
2026-11-27T21:04:00Z  Successful Connections                         0.0
2026-11-27T21:09:00Z  Successful Connections                         0.0
2026-11-27T21:14:00Z  Successful Connections                         0.0
2026-11-27T21:19:00Z  Successful Connections                         0.0
2026-11-27T21:24:00Z  Successful Connections                         0.0
2026-11-27T21:29:00Z  Successful Connections                         0.0
2026-11-27T21:34:00Z  Successful Connections                         0.0
2026-11-27T21:39:00Z  Successful Connections                         0.0
2026-11-27T21:44:00Z  Successful Connections                         0.0
2026-11-27T21:49:00Z  Successful Connections                         0.0
2026-11-27T21:54:00Z  Successful Connections                         0.0
2026-11-27T21:59:00Z  Successful Connections                         0.0
2026-11-27T20:04:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:09:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:14:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:19:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:24:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:29:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:34:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:39:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:44:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:49:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:54:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:59:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:04:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:09:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:14:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:19:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:24:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:29:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:34:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:39:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:44:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:49:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:54:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:59:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:04:00Z  Blocked by Firewall                            0.0
2026-11-27T20:09:00Z  Blocked by Firewall                            0.0
2026-11-27T20:14:00Z  Blocked by Firewall                            0.0
2026-11-27T20:19:00Z  Blocked by Firewall                            0.0
2026-11-27T20:24:00Z  Blocked by Firewall                            0.0
2026-11-27T20:29:00Z  Blocked by Firewall                            0.0
2026-11-27T20:34:00Z  Blocked by Firewall                            0.0
2026-11-27T20:39:00Z  Blocked by Firewall                            0.0
2026-11-27T20:44:00Z  Blocked by Firewall                            0.0
2026-11-27T20:49:00Z  Blocked by Firewall                            0.0
2026-11-27T20:54:00Z  Blocked by Firewall                            0.0
2026-11-27T20:59:00Z  Blocked by Firewall                            0.0
2026-11-27T21:04:00Z  Blocked by Firewall                            0.0
2026-11-27T21:09:00Z  Blocked by Firewall                            0.0
2026-11-27T21:14:00Z  Blocked by Firewall                            0.0
2026-11-27T21:19:00Z  Blocked by Firewall                            0.0
2026-11-27T21:24:00Z  Blocked by Firewall                            0.0
2026-11-27T21:29:00Z  Blocked by Firewall                            0.0
2026-11-27T21:34:00Z  Blocked by Firewall                            0.0
2026-11-27T21:39:00Z  Blocked by Firewall                            0.0
2026-11-27T21:44:00Z  Blocked by Firewall                            0.0
2026-11-27T21:49:00Z  Blocked by Firewall                            0.0
2026-11-27T21:54:00Z  Blocked by Firewall                            0.0
2026-11-27T21:59:00Z  Blocked by Firewall                            0.0
2026-11-27T20:04:00Z  Deadlocks                                      0.0
2026-11-27T20:09:00Z  Deadlocks                                      0.0
2026-11-27T20:14:00Z  Deadlocks                                      0.0
2026-11-27T20:19:00Z  Deadlocks                                      0.0
2026-11-27T20:24:00Z  Deadlocks                                      0.0
2026-11-27T20:29:00Z  Deadlocks                                      0.0
2026-11-27T20:34:00Z  Deadlocks                                      0.0
2026-11-27T20:39:00Z  Deadlocks                                      0.0
2026-11-27T20:44:00Z  Deadlocks                                      0.0
2026-11-27T20:49:00Z  Deadlocks                                      0.0
2026-11-27T20:54:00Z  Deadlocks                                      0.0
2026-11-27T20:59:00Z  Deadlocks                                      0.0
2026-11-27T21:04:00Z  Deadlocks                                      0.0
2026-11-27T21:09:00Z  Deadlocks                                      0.0
2026-11-27T21:14:00Z  Deadlocks                                      0.0
2026-11-27T21:19:00Z  Deadlocks                                      0.0
2026-11-27T21:24:00Z  Deadlocks                                      0.0
2026-11-27T21:29:00Z  Deadlocks                                      0.0
2026-11-27T21:34:00Z  Deadlocks                                      0.0
2026-11-27T21:39:00Z  Deadlocks                                      0.0
2026-11-27T21:44:00Z  Deadlocks                                      0.0
2026-11-27T21:49:00Z  Deadlocks                                      0.0
2026-11-27T21:54:00Z  Deadlocks                                      0.0
2026-11-27T21:59:00Z  Deadlocks                                      0.0

Servidor: sql-az305-sec-3b4e88
Timestamp             Name                                Average    Total
--------------------  ----------------------------------  ---------  -------
2026-11-27T20:04:00Z  Availability                        100.0
2026-11-27T20:09:00Z  Availability                        100.0
2026-11-27T20:14:00Z  Availability                        100.0
2026-11-27T20:19:00Z  Availability                        100.0
2026-11-27T20:24:00Z  Availability                        100.0
2026-11-27T20:29:00Z  Availability                        100.0
2026-11-27T20:34:00Z  Availability                        100.0
2026-11-27T20:39:00Z  Availability                        100.0
2026-11-27T20:44:00Z  Availability                        100.0
2026-11-27T20:49:00Z  Availability                        100.0
2026-11-27T20:54:00Z  Availability                        100.0
2026-11-27T20:59:00Z  Availability                        100.0
2026-11-27T21:04:00Z  Availability                        100.0
2026-11-27T21:09:00Z  Availability                        100.0
2026-11-27T21:14:00Z  Availability                        100.0
2026-11-27T21:19:00Z  Availability                        100.0
2026-11-27T21:24:00Z  Availability                        100.0
2026-11-27T21:29:00Z  Availability                        100.0
2026-11-27T21:34:00Z  Availability                        100.0
2026-11-27T21:39:00Z  Availability                        100.0
2026-11-27T21:44:00Z  Availability                        100.0
2026-11-27T21:49:00Z  Availability                        100.0
2026-11-27T21:54:00Z  Availability                        100.0
2026-11-27T21:59:00Z  Availability                        100.0
2026-11-27T20:04:00Z  Successful Connections                         0.0
2026-11-27T20:09:00Z  Successful Connections                         0.0
2026-11-27T20:14:00Z  Successful Connections                         0.0
2026-11-27T20:19:00Z  Successful Connections                         0.0
2026-11-27T20:24:00Z  Successful Connections                         0.0
2026-11-27T20:29:00Z  Successful Connections                         0.0
2026-11-27T20:34:00Z  Successful Connections                         0.0
2026-11-27T20:39:00Z  Successful Connections                         0.0
2026-11-27T20:44:00Z  Successful Connections                         0.0
2026-11-27T20:49:00Z  Successful Connections                         0.0
2026-11-27T20:54:00Z  Successful Connections                         0.0
2026-11-27T20:59:00Z  Successful Connections                         0.0
2026-11-27T21:04:00Z  Successful Connections                         0.0
2026-11-27T21:09:00Z  Successful Connections                         0.0
2026-11-27T21:14:00Z  Successful Connections                         0.0
2026-11-27T21:19:00Z  Successful Connections                         0.0
2026-11-27T21:24:00Z  Successful Connections                         0.0
2026-11-27T21:29:00Z  Successful Connections                         0.0
2026-11-27T21:34:00Z  Successful Connections                         0.0
2026-11-27T21:39:00Z  Successful Connections                         0.0
2026-11-27T21:44:00Z  Successful Connections                         0.0
2026-11-27T21:49:00Z  Successful Connections                         0.0
2026-11-27T21:54:00Z  Successful Connections                         0.0
2026-11-27T21:59:00Z  Successful Connections                         0.0
2026-11-27T20:04:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:09:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:14:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:19:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:24:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:29:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:34:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:39:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:44:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:49:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:54:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:59:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:04:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:09:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:14:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:19:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:24:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:29:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:34:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:39:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:44:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:49:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:54:00Z  Failed Connections : System Errors             0.0
2026-11-27T21:59:00Z  Failed Connections : System Errors             0.0
2026-11-27T20:04:00Z  Blocked by Firewall                            0.0
2026-11-27T20:09:00Z  Blocked by Firewall                            0.0
2026-11-27T20:14:00Z  Blocked by Firewall                            0.0
2026-11-27T20:19:00Z  Blocked by Firewall                            0.0
2026-11-27T20:24:00Z  Blocked by Firewall                            0.0
2026-11-27T20:29:00Z  Blocked by Firewall                            0.0
2026-11-27T20:34:00Z  Blocked by Firewall                            0.0
2026-11-27T20:39:00Z  Blocked by Firewall                            0.0
2026-11-27T20:44:00Z  Blocked by Firewall                            0.0
2026-11-27T20:49:00Z  Blocked by Firewall                            0.0
2026-11-27T20:54:00Z  Blocked by Firewall                            0.0
2026-11-27T20:59:00Z  Blocked by Firewall                            0.0
2026-11-27T21:04:00Z  Blocked by Firewall                            0.0
2026-11-27T21:09:00Z  Blocked by Firewall                            0.0
2026-11-27T21:14:00Z  Blocked by Firewall                            0.0
2026-11-27T21:19:00Z  Blocked by Firewall                            0.0
2026-11-27T21:24:00Z  Blocked by Firewall                            0.0
2026-11-27T21:29:00Z  Blocked by Firewall                            0.0
2026-11-27T21:34:00Z  Blocked by Firewall                            0.0
2026-11-27T21:39:00Z  Blocked by Firewall                            0.0
2026-11-27T21:44:00Z  Blocked by Firewall                            0.0
2026-11-27T21:49:00Z  Blocked by Firewall                            0.0
2026-11-27T21:54:00Z  Blocked by Firewall                            0.0
2026-11-27T21:59:00Z  Blocked by Firewall                            0.0
2026-11-27T20:04:00Z  Deadlocks                                      0.0
2026-11-27T20:09:00Z  Deadlocks                                      0.0
2026-11-27T20:14:00Z  Deadlocks                                      0.0
2026-11-27T20:19:00Z  Deadlocks                                      0.0
2026-11-27T20:24:00Z  Deadlocks                                      0.0
2026-11-27T20:29:00Z  Deadlocks                                      0.0
2026-11-27T20:34:00Z  Deadlocks                                      0.0
2026-11-27T20:39:00Z  Deadlocks                                      0.0
2026-11-27T20:44:00Z  Deadlocks                                      0.0
2026-11-27T20:49:00Z  Deadlocks                                      0.0
2026-11-27T20:54:00Z  Deadlocks                                      0.0
2026-11-27T20:59:00Z  Deadlocks                                      0.0
2026-11-27T21:04:00Z  Deadlocks                                      0.0
2026-11-27T21:09:00Z  Deadlocks                                      0.0
2026-11-27T21:14:00Z  Deadlocks                                      0.0
2026-11-27T21:19:00Z  Deadlocks                                      0.0
2026-11-27T21:24:00Z  Deadlocks                                      0.0
2026-11-27T21:29:00Z  Deadlocks                                      0.0
2026-11-27T21:34:00Z  Deadlocks                                      0.0
2026-11-27T21:39:00Z  Deadlocks                                      0.0
2026-11-27T21:44:00Z  Deadlocks                                      0.0
2026-11-27T21:49:00Z  Deadlocks                                      0.0
2026-11-27T21:54:00Z  Deadlocks                                      0.0
2026-11-27T21:59:00Z  Deadlocks                                      0.0
```
<!-- END:05-sql-metrics.txt -->

<!-- BEGIN:06d-sql-failover-activity-log.txt -->
## Bloque: `06d-sql-failover-activity-log.txt`
- **Generado (UTC):** `2026-11-27T22:04:47Z`

```text
Hora | Operacion | Estado | Grupo
2026-11-27T22:02:23.679914Z | Microsoft.Sql/servers/failoverGroups/failover/action | Accepted | rg-az305-bcdr-sec
2026-11-27T22:02:23.4142761Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | rg-az305-bcdr-sec
```
<!-- END:06d-sql-failover-activity-log.txt -->

<!-- BEGIN:03-backup-job-completed.txt -->
## Bloque: `03-backup-job-completed.txt`
- **Generado (UTC):** `2026-11-27T23:02:00Z`

```text
Operacion    Estado     Inicio                        Fin                           Duracion
-----------  ---------  ----------------------------  ----------------------------  ----------------
Backup       Completed  2026-11-27T22:04:52.0587485Z  2026-11-27T23:01:03.0988994Z  PT56M11.0401509S
```
<!-- END:03-backup-job-completed.txt -->
