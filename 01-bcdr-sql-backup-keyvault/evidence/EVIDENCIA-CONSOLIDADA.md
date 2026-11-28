# Evidencia Técnica Consolidada — AZ-305

> Salidas sanitizadas automáticamente (sin GUIDs, correos ni direcciones IPv4).

<!-- BEGIN:02-storage-gzrs-status.txt -->
## Bloque: `02-storage-gzrs-status.txt`
- **Generado (UTC):** `2026-11-28T15:13:19Z`

```text
Cuenta              SKU            RegionPrimaria    EstadoPri    RegionSecundaria    EstadoSec
------------------  -------------  ----------------  -----------  ------------------  -----------
stgaz305gzrs0f772b  Standard_GZRS  centralus         available    eastus2             available
```
<!-- END:02-storage-gzrs-status.txt -->

<!-- BEGIN:04-kv-secret-restored.txt -->
## Bloque: `04-kv-secret-restored.txt`
- **Generado (UTC):** `2026-11-28T15:13:26Z`

```text
VaultSecundario                                                                                                Habilitado    UltimaActualizacion
-------------------------------------------------------------------------------------------------------------  ------------  -------------------------
https://kv-az305-sec-0f772b.vault.azure.net/secrets/lab01-bcdr-secret-0f772b/0d59e59b1a7a4b7bb7ce47950b51b24b  True          2026-11-28T14:08:28+00:00
```
<!-- END:04-kv-secret-restored.txt -->

<!-- BEGIN:01-sql-failover-status.txt -->
## Bloque: `01-sql-failover-status.txt`
- **Generado (UTC):** `2026-11-28T15:15:53Z`

```text
Prueba de failover planificado: fog-az305-0f772b (db-ventas-critica)

[FAILOVER] destino: sql-az305-sec-0f772b
Duración del comando set-primary (s): 34
Mayor brecha entre escrituras confirmadas, RTO observado (s): 8
Escrituras confirmadas durante la prueba: 17
Filas nuevas en el nuevo primario: 17
Escrituras confirmadas perdidas, RPO observado: 0
hora_utc resultado servidor
15:13:38Z OK sql-az305-pri-0f772b
15:13:40Z OK sql-az305-pri-0f772b
15:13:42Z OK sql-az305-pri-0f772b
15:13:45Z OK sql-az305-pri-0f772b
15:13:47Z OK sql-az305-pri-0f772b
15:13:50Z OK sql-az305-pri-0f772b
15:13:52Z OK sql-az305-pri-0f772b
15:13:55Z OK sql-az305-pri-0f772b
15:13:57Z OK sql-az305-pri-0f772b
15:13:59Z OK sql-az305-pri-0f772b
15:14:02Z OK sql-az305-pri-0f772b
15:14:04Z OK sql-az305-pri-0f772b
15:14:07Z FAIL -
15:14:09Z FAIL -
15:14:12Z OK sql-az305-sec-0f772b
15:14:14Z FAIL -
15:14:16Z OK sql-az305-sec-0f772b
15:14:19Z OK sql-az305-sec-0f772b
15:14:21Z OK sql-az305-sec-0f772b
15:14:23Z OK sql-az305-sec-0f772b
15:14:26Z FAIL -
Grupo             RolDestino    EstadoReplicacion    Politica
----------------  ------------  -------------------  ----------
fog-az305-0f772b  Primary       CATCH_UP             Manual

[FAILBACK] destino: sql-az305-pri-0f772b
Duración del comando set-primary (s): 33
Mayor brecha entre escrituras confirmadas, RTO observado (s): 7
Escrituras confirmadas durante la prueba: 19
Filas nuevas en el nuevo primario: 19
Escrituras confirmadas perdidas, RPO observado: 0
hora_utc resultado servidor
15:15:01Z OK sql-az305-sec-0f772b
15:15:03Z OK sql-az305-sec-0f772b
15:15:06Z OK sql-az305-sec-0f772b
15:15:08Z OK sql-az305-sec-0f772b
15:15:10Z OK sql-az305-sec-0f772b
15:15:13Z OK sql-az305-sec-0f772b
15:15:15Z OK sql-az305-sec-0f772b
15:15:17Z OK sql-az305-sec-0f772b
15:15:20Z OK sql-az305-sec-0f772b
15:15:22Z OK sql-az305-sec-0f772b
15:15:25Z OK sql-az305-sec-0f772b
15:15:27Z OK sql-az305-sec-0f772b
15:15:30Z FAIL -
15:15:32Z FAIL -
15:15:34Z OK sql-az305-pri-0f772b
15:15:37Z OK sql-az305-pri-0f772b
15:15:39Z OK sql-az305-pri-0f772b
15:15:41Z OK sql-az305-pri-0f772b
15:15:44Z OK sql-az305-pri-0f772b
15:15:46Z OK sql-az305-pri-0f772b
15:15:49Z OK sql-az305-pri-0f772b
Grupo             RolDestino    EstadoReplicacion    Politica
----------------  ------------  -------------------  ----------
fog-az305-0f772b  Primary       CATCH_UP             Manual
```
<!-- END:01-sql-failover-status.txt -->

<!-- BEGIN:05-sql-metrics.txt -->
## Bloque: `05-sql-metrics.txt`
- **Generado (UTC):** `2026-11-28T15:51:00Z`

```text

Servidor: sql-az305-pri-0f772b
Timestamp             Name                                Average    Total
--------------------  ----------------------------------  ---------  -------
2026-11-28T13:50:00Z  Availability                        100.0
2026-11-28T13:55:00Z  Availability                        100.0
2026-11-28T14:00:00Z  Availability                        100.0
2026-11-28T14:05:00Z  Availability                        100.0
2026-11-28T14:10:00Z  Availability                        100.0
2026-11-28T14:15:00Z  Availability                        100.0
2026-11-28T14:20:00Z  Availability                        100.0
2026-11-28T14:25:00Z  Availability                        100.0
2026-11-28T14:30:00Z  Availability                        100.0
2026-11-28T14:35:00Z  Availability                        100.0
2026-11-28T14:40:00Z  Availability                        100.0
2026-11-28T14:45:00Z  Availability                        100.0
2026-11-28T14:50:00Z  Availability                        100.0
2026-11-28T14:55:00Z  Availability                        100.0
2026-11-28T15:00:00Z  Availability                        100.0
2026-11-28T15:05:00Z  Availability                        100.0
2026-11-28T15:10:00Z  Availability                        100.0
2026-11-28T15:15:00Z  Availability                        100.0
2026-11-28T15:20:00Z  Availability                        100.0
2026-11-28T15:25:00Z  Availability                        100.0
2026-11-28T15:30:00Z  Availability                        100.0
2026-11-28T15:35:00Z  Availability                        100.0
2026-11-28T15:40:00Z  Availability                        100.0
2026-11-28T15:45:00Z  Availability                        100.0
2026-11-28T13:50:00Z  Successful Connections                         0.0
2026-11-28T13:55:00Z  Successful Connections                         0.0
2026-11-28T14:00:00Z  Successful Connections                         0.0
2026-11-28T14:05:00Z  Successful Connections                         0.0
2026-11-28T14:10:00Z  Successful Connections                         0.0
2026-11-28T14:15:00Z  Successful Connections                         20.0
2026-11-28T14:20:00Z  Successful Connections                         0.0
2026-11-28T14:25:00Z  Successful Connections                         0.0
2026-11-28T14:30:00Z  Successful Connections                         0.0
2026-11-28T14:35:00Z  Successful Connections                         0.0
2026-11-28T14:40:00Z  Successful Connections                         0.0
2026-11-28T14:45:00Z  Successful Connections                         0.0
2026-11-28T14:50:00Z  Successful Connections                         0.0
2026-11-28T14:55:00Z  Successful Connections                         0.0
2026-11-28T15:00:00Z  Successful Connections                         0.0
2026-11-28T15:05:00Z  Successful Connections                         0.0
2026-11-28T15:10:00Z  Successful Connections                         12.0
2026-11-28T15:15:00Z  Successful Connections                         16.0
2026-11-28T15:20:00Z  Successful Connections                         0.0
2026-11-28T15:25:00Z  Successful Connections                         0.0
2026-11-28T15:30:00Z  Successful Connections                         0.0
2026-11-28T15:35:00Z  Successful Connections                         0.0
2026-11-28T15:40:00Z  Successful Connections                         0.0
2026-11-28T15:45:00Z  Successful Connections                         0.0
2026-11-28T13:50:00Z  Failed Connections : System Errors             0.0
2026-11-28T13:55:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:00:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:05:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:10:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:15:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:20:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:25:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:30:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:35:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:40:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:45:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:50:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:55:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:00:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:05:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:10:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:15:00Z  Failed Connections : System Errors             1.0
2026-11-28T15:20:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:25:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:30:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:35:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:40:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:45:00Z  Failed Connections : System Errors             0.0
2026-11-28T13:50:00Z  Blocked by Firewall                            0.0
2026-11-28T13:55:00Z  Blocked by Firewall                            0.0
2026-11-28T14:00:00Z  Blocked by Firewall                            0.0
2026-11-28T14:05:00Z  Blocked by Firewall                            0.0
2026-11-28T14:10:00Z  Blocked by Firewall                            0.0
2026-11-28T14:15:00Z  Blocked by Firewall                            0.0
2026-11-28T14:20:00Z  Blocked by Firewall                            0.0
2026-11-28T14:25:00Z  Blocked by Firewall                            0.0
2026-11-28T14:30:00Z  Blocked by Firewall                            0.0
2026-11-28T14:35:00Z  Blocked by Firewall                            0.0
2026-11-28T14:40:00Z  Blocked by Firewall                            0.0
2026-11-28T14:45:00Z  Blocked by Firewall                            0.0
2026-11-28T14:50:00Z  Blocked by Firewall                            0.0
2026-11-28T14:55:00Z  Blocked by Firewall                            0.0
2026-11-28T15:00:00Z  Blocked by Firewall                            0.0
2026-11-28T15:05:00Z  Blocked by Firewall                            0.0
2026-11-28T15:10:00Z  Blocked by Firewall                            0.0
2026-11-28T15:15:00Z  Blocked by Firewall                            0.0
2026-11-28T15:20:00Z  Blocked by Firewall                            0.0
2026-11-28T15:25:00Z  Blocked by Firewall                            0.0
2026-11-28T15:30:00Z  Blocked by Firewall                            0.0
2026-11-28T15:35:00Z  Blocked by Firewall                            0.0
2026-11-28T15:40:00Z  Blocked by Firewall                            0.0
2026-11-28T15:45:00Z  Blocked by Firewall                            0.0
2026-11-28T13:50:00Z  Deadlocks                                      0.0
2026-11-28T13:55:00Z  Deadlocks                                      0.0
2026-11-28T14:00:00Z  Deadlocks                                      0.0
2026-11-28T14:05:00Z  Deadlocks                                      0.0
2026-11-28T14:10:00Z  Deadlocks                                      0.0
2026-11-28T14:15:00Z  Deadlocks                                      0.0
2026-11-28T14:20:00Z  Deadlocks                                      0.0
2026-11-28T14:25:00Z  Deadlocks                                      0.0
2026-11-28T14:30:00Z  Deadlocks                                      0.0
2026-11-28T14:35:00Z  Deadlocks                                      0.0
2026-11-28T14:40:00Z  Deadlocks                                      0.0
2026-11-28T14:45:00Z  Deadlocks                                      0.0
2026-11-28T14:50:00Z  Deadlocks                                      0.0
2026-11-28T14:55:00Z  Deadlocks                                      0.0
2026-11-28T15:00:00Z  Deadlocks                                      0.0
2026-11-28T15:05:00Z  Deadlocks                                      0.0
2026-11-28T15:10:00Z  Deadlocks                                      0.0
2026-11-28T15:15:00Z  Deadlocks                                      0.0
2026-11-28T15:20:00Z  Deadlocks                                      0.0
2026-11-28T15:25:00Z  Deadlocks                                      0.0
2026-11-28T15:30:00Z  Deadlocks                                      0.0
2026-11-28T15:35:00Z  Deadlocks                                      0.0
2026-11-28T15:40:00Z  Deadlocks                                      0.0
2026-11-28T15:45:00Z  Deadlocks                                      0.0

Servidor: sql-az305-sec-0f772b
Timestamp             Name                                Average    Total
--------------------  ----------------------------------  ---------  -------
2026-11-28T13:50:00Z  Availability                        100.0
2026-11-28T13:55:00Z  Availability                        100.0
2026-11-28T14:00:00Z  Availability                        100.0
2026-11-28T14:05:00Z  Availability                        100.0
2026-11-28T14:10:00Z  Availability                        100.0
2026-11-28T14:15:00Z  Availability                        100.0
2026-11-28T14:20:00Z  Availability                        100.0
2026-11-28T14:25:00Z  Availability                        100.0
2026-11-28T14:30:00Z  Availability                        100.0
2026-11-28T14:35:00Z  Availability                        100.0
2026-11-28T14:40:00Z  Availability                        100.0
2026-11-28T14:45:00Z  Availability                        100.0
2026-11-28T14:50:00Z  Availability                        100.0
2026-11-28T14:55:00Z  Availability                        100.0
2026-11-28T15:00:00Z  Availability                        100.0
2026-11-28T15:05:00Z  Availability                        100.0
2026-11-28T15:10:00Z  Availability                        100.0
2026-11-28T15:15:00Z  Availability                        100.0
2026-11-28T15:20:00Z  Availability                        100.0
2026-11-28T15:25:00Z  Availability                        100.0
2026-11-28T15:30:00Z  Availability                        100.0
2026-11-28T15:35:00Z  Availability                        100.0
2026-11-28T15:40:00Z  Availability                        100.0
2026-11-28T15:45:00Z  Availability                        100.0
2026-11-28T13:50:00Z  Successful Connections                         0.0
2026-11-28T13:55:00Z  Successful Connections                         0.0
2026-11-28T14:00:00Z  Successful Connections                         0.0
2026-11-28T14:05:00Z  Successful Connections                         0.0
2026-11-28T14:10:00Z  Successful Connections                         0.0
2026-11-28T14:15:00Z  Successful Connections                         29.0
2026-11-28T14:20:00Z  Successful Connections                         0.0
2026-11-28T14:25:00Z  Successful Connections                         0.0
2026-11-28T14:30:00Z  Successful Connections                         0.0
2026-11-28T14:35:00Z  Successful Connections                         0.0
2026-11-28T14:40:00Z  Successful Connections                         0.0
2026-11-28T14:45:00Z  Successful Connections                         0.0
2026-11-28T14:50:00Z  Successful Connections                         0.0
2026-11-28T14:55:00Z  Successful Connections                         0.0
2026-11-28T15:00:00Z  Successful Connections                         0.0
2026-11-28T15:05:00Z  Successful Connections                         0.0
2026-11-28T15:10:00Z  Successful Connections                         0.0
2026-11-28T15:15:00Z  Successful Connections                         18.0
2026-11-28T15:20:00Z  Successful Connections                         0.0
2026-11-28T15:25:00Z  Successful Connections                         0.0
2026-11-28T15:30:00Z  Successful Connections                         0.0
2026-11-28T15:35:00Z  Successful Connections                         0.0
2026-11-28T15:40:00Z  Successful Connections                         0.0
2026-11-28T15:45:00Z  Successful Connections                         0.0
2026-11-28T13:50:00Z  Failed Connections : System Errors             0.0
2026-11-28T13:55:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:00:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:05:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:10:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:15:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:20:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:25:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:30:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:35:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:40:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:45:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:50:00Z  Failed Connections : System Errors             0.0
2026-11-28T14:55:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:00:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:05:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:10:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:15:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:20:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:25:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:30:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:35:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:40:00Z  Failed Connections : System Errors             0.0
2026-11-28T15:45:00Z  Failed Connections : System Errors             0.0
2026-11-28T13:50:00Z  Blocked by Firewall                            0.0
2026-11-28T13:55:00Z  Blocked by Firewall                            0.0
2026-11-28T14:00:00Z  Blocked by Firewall                            0.0
2026-11-28T14:05:00Z  Blocked by Firewall                            0.0
2026-11-28T14:10:00Z  Blocked by Firewall                            0.0
2026-11-28T14:15:00Z  Blocked by Firewall                            0.0
2026-11-28T14:20:00Z  Blocked by Firewall                            0.0
2026-11-28T14:25:00Z  Blocked by Firewall                            0.0
2026-11-28T14:30:00Z  Blocked by Firewall                            0.0
2026-11-28T14:35:00Z  Blocked by Firewall                            0.0
2026-11-28T14:40:00Z  Blocked by Firewall                            0.0
2026-11-28T14:45:00Z  Blocked by Firewall                            0.0
2026-11-28T14:50:00Z  Blocked by Firewall                            0.0
2026-11-28T14:55:00Z  Blocked by Firewall                            0.0
2026-11-28T15:00:00Z  Blocked by Firewall                            0.0
2026-11-28T15:05:00Z  Blocked by Firewall                            0.0
2026-11-28T15:10:00Z  Blocked by Firewall                            0.0
2026-11-28T15:15:00Z  Blocked by Firewall                            0.0
2026-11-28T15:20:00Z  Blocked by Firewall                            0.0
2026-11-28T15:25:00Z  Blocked by Firewall                            0.0
2026-11-28T15:30:00Z  Blocked by Firewall                            0.0
2026-11-28T15:35:00Z  Blocked by Firewall                            0.0
2026-11-28T15:40:00Z  Blocked by Firewall                            0.0
2026-11-28T15:45:00Z  Blocked by Firewall                            0.0
2026-11-28T13:50:00Z  Deadlocks                                      0.0
2026-11-28T13:55:00Z  Deadlocks                                      0.0
2026-11-28T14:00:00Z  Deadlocks                                      0.0
2026-11-28T14:05:00Z  Deadlocks                                      0.0
2026-11-28T14:10:00Z  Deadlocks                                      0.0
2026-11-28T14:15:00Z  Deadlocks                                      0.0
2026-11-28T14:20:00Z  Deadlocks                                      0.0
2026-11-28T14:25:00Z  Deadlocks                                      0.0
2026-11-28T14:30:00Z  Deadlocks                                      0.0
2026-11-28T14:35:00Z  Deadlocks                                      0.0
2026-11-28T14:40:00Z  Deadlocks                                      0.0
2026-11-28T14:45:00Z  Deadlocks                                      0.0
2026-11-28T14:50:00Z  Deadlocks                                      0.0
2026-11-28T14:55:00Z  Deadlocks                                      0.0
2026-11-28T15:00:00Z  Deadlocks                                      0.0
2026-11-28T15:05:00Z  Deadlocks                                      0.0
2026-11-28T15:10:00Z  Deadlocks                                      0.0
2026-11-28T15:15:00Z  Deadlocks                                      0.0
2026-11-28T15:20:00Z  Deadlocks                                      0.0
2026-11-28T15:25:00Z  Deadlocks                                      0.0
2026-11-28T15:30:00Z  Deadlocks                                      0.0
2026-11-28T15:35:00Z  Deadlocks                                      0.0
2026-11-28T15:40:00Z  Deadlocks                                      0.0
2026-11-28T15:45:00Z  Deadlocks                                      0.0
```
<!-- END:05-sql-metrics.txt -->

<!-- BEGIN:06d-sql-failover-activity-log.txt -->
## Bloque: `06d-sql-failover-activity-log.txt`
- **Generado (UTC):** `2026-11-28T15:51:09Z`

```text
Hora | Operacion | Estado | Grupo
2026-11-28T15:15:53.4148354Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-SEC
2026-11-28T15:15:53.4148354Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-PRI
2026-11-28T15:15:48.6102579Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | rg-az305-bcdr-pri
2026-11-28T15:15:23.4009094Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-SEC
2026-11-28T15:15:23.4009094Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-PRI
2026-11-28T15:15:17.8521807Z | Microsoft.Sql/servers/failoverGroups/failover/action | Accepted | rg-az305-bcdr-pri
2026-11-28T15:15:17.7584292Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | rg-az305-bcdr-pri
2026-11-28T15:14:43.7906995Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-SEC
2026-11-28T15:14:43.7906995Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-PRI
2026-11-28T15:14:27.4199621Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | rg-az305-bcdr-sec
2026-11-28T15:14:13.781319Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-SEC
2026-11-28T15:14:13.781319Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-PRI
2026-11-28T15:13:54.8468913Z | Microsoft.Sql/servers/failoverGroups/failover/action | Accepted | rg-az305-bcdr-sec
2026-11-28T15:13:54.6750158Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | rg-az305-bcdr-sec
2026-11-28T14:18:51.8513617Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-SEC
2026-11-28T14:18:51.8513617Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-PRI
2026-11-28T14:18:40.7980046Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | rg-az305-bcdr-pri
2026-11-28T14:18:21.8558506Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-SEC
2026-11-28T14:18:21.8558506Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-PRI
2026-11-28T14:18:09.6306178Z | Microsoft.Sql/servers/failoverGroups/failover/action | Accepted | rg-az305-bcdr-pri
2026-11-28T14:18:09.5524902Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | rg-az305-bcdr-pri
2026-11-28T14:17:43.1141783Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-SEC
2026-11-28T14:17:43.1141783Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | RG-AZ305-BCDR-PRI
2026-11-28T14:17:20.8530783Z | Microsoft.Sql/servers/failoverGroups/failover/action | Succeeded | rg-az305-bcdr-sec
2026-11-28T14:16:43.1050119Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-SEC
2026-11-28T14:16:43.1050119Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | RG-AZ305-BCDR-PRI
2026-11-28T14:16:37.1635884Z | Microsoft.Sql/servers/failoverGroups/failover/action | Accepted | rg-az305-bcdr-sec
2026-11-28T14:16:36.9760955Z | Microsoft.Sql/servers/failoverGroups/failover/action | Started | rg-az305-bcdr-sec
```
<!-- END:06d-sql-failover-activity-log.txt -->

<!-- BEGIN:03-backup-job-completed.txt -->
## Bloque: `03-backup-job-completed.txt`
- **Generado (UTC):** `2026-11-28T15:42:53Z`

```text
Operacion    Estado     Inicio                        Fin                           Duracion
-----------  ---------  ----------------------------  ----------------------------  ----------------
Backup       Completed  2026-11-28T15:16:15.0735453Z  2026-11-28T15:42:25.9090067Z  PT26M10.8354614S
```
<!-- END:03-backup-job-completed.txt -->

<!-- BEGIN:07-vm-restore-disks.txt -->
## Bloque: `07-vm-restore-disks.txt`
- **Generado (UTC):** `2026-11-28T16:02:40Z`

```text
Operacion    Estado     Inicio                        Fin                           Duracion
-----------  ---------  ----------------------------  ----------------------------  --------------
Restore      Completed  2026-11-28T16:01:32.3268773Z  2026-11-28T16:02:37.8072117Z  PT1M5.4803344S
```
<!-- END:07-vm-restore-disks.txt -->
