# Laboratorio 01C: Respaldo y recuperación de secretos y claves en Azure Key Vault

> **Estado:** En validación. Los scripts pasan ShellCheck y pruebas contra un Azure simulado; falta la corrida real y su evidencia.
> **Dominio AZ-305:** continuidad del negocio y seguridad de secretos.

## Escenario

Un equipo necesita una copia independiente de un secreto y una clave en otra región y debe saber **dónde sí y dónde no** puede restaurarlos.

| Prueba | Resultado esperado |
| :--- | :--- |
| Restaurar de `eastus` a `westus2` | Funciona: misma suscripción y geografía |
| Valor y clave restaurados | Mismo SHA-256; lo cifrado en origen se descifra en destino |
| Cambiar el secreto en origen | El destino no cambia: no es replicación |
| Restaurar en `westeurope` | Azure lo rechaza: otra geografía |

## Habilidades demostradas

- Key Vault Standard con Azure RBAC y roles de datos específicos (*Secrets Officer* y *Crypto Officer*).
- Respaldo y restauración con todas las versiones, verificada sin mostrar el secreto.
- Pruebas negativas con un control que descarta fallos por permisos.
- Auditoría en Log Analytics y limpieza con purga verificada.

## Arquitectura

```mermaid
flowchart LR
    subgraph US["Geografía: Estados Unidos (misma suscripción)"]
        KV1["Key Vault en eastus: secreto + clave"]
        KV2["Key Vault en westus2: copia restaurada"]
    end
    subgraph EU["Geografía: Europa"]
        KV3["Key Vault en westeurope: prueba negativa"]
    end
    TMP["Archivo cifrado temporal (se elimina)"]
    LAW["Log Analytics: AZKVAuditLogs"]

    KV1 -->|"backup"| TMP
    TMP -->|"restore permitido"| KV2
    TMP --x|"restore rechazado"| KV3
    KV1 --> LAW
    KV2 --> LAW
```

## Reglas de respaldo y restauración

| Regla | Detalle |
| :--- | :--- |
| Destino | Un vault de la **misma suscripción** y la **misma geografía** de Azure |
| Formato | Blob cifrado que no puede descifrarse fuera de Azure |
| Alcance | Por objeto (no existe respaldo del vault completo en Standard) |
| Versiones | Hasta 500 por objeto |
| Vigencia | Copia de un momento: no se actualiza al rotar |
| Nombre | El destino no debe tener un objeto con ese nombre, activo o en *soft delete* |

Fuente: [confiabilidad de Azure Key Vault](https://learn.microsoft.com/azure/reliability/reliability-key-vault).

## Decisiones de arquitectura (ADR)

| Decisión | Elección | Motivo |
| :--- | :--- | :--- |
| Estrategia | Backup y restore como copia independiente | La replicación administrada hacia la región emparejada la controla Microsoft y, tras un failover, el vault queda en solo lectura |
| Segunda región | `westus2` | Está en la misma geografía que `eastus`; no es su región emparejada, así que agrega una copia en un lugar distinto |
| Nivel | Standard | Claves RSA protegidas por software; Premium agrega claves protegidas por HSM |
| Autorización | Azure RBAC | Rol por tipo de dato y alcance por vault |
| Archivos de respaldo | Temporales, permisos restringidos, borrado automático | Reducen la exposición |
| Purge protection | Desactivada | Permite limpiar y repetir el lab; en producción debe activarse |

## Ejecución en Azure Cloud Shell (Bash)

**Prerrequisitos:** rol para crear recursos, asignar roles y purgar Key Vault (por ejemplo, Owner de la suscripción).

```bash
cd 01c-keyvault-backup-restore
./scripts/01-deploy.sh          # reejecutable
./scripts/02-test.sh all        # o por pasos: backup-restore, verify, independence, cross-geo
./scripts/03-cleanup.sh         # pide escribir BORRAR y purga los vaults
```

La asignación de roles puede tardar en propagarse; los scripts reintentan.

| Subcomando adicional | Uso |
| :--- | :--- |
| `./scripts/02-test.sh reset-dr` | Borra y purga los objetos restaurados para repetir la restauración |

| Variable (antes del primer despliegue) | Valor por defecto |
| :--- | :--- |
| `LOC_PRI` | `eastus` |
| `LOC_DR` | `westus2` (misma geografía que `LOC_PRI`) |
| `LOC_FOREIGN` | `westeurope` (otra geografía) |
| `RG_PREFIX` | `rg-az305-1c` |

## Resultados y evidencia

| Archivo en `evidence/` | Qué prueba | Estado |
| :--- | :--- | :--- |
| `01-backup-restore.txt` | Respaldo y restauración entre regiones | Pendiente |
| `02-verification.txt` | Versiones, SHA-256 y descifrado | Pendiente |
| `03-independence.txt` | La copia no se sincroniza | Pendiente |
| `04-cross-geography.txt` | Rechazo entre geografías, con el mensaje de Azure | Pendiente |

Consultas KQL: [`queries/keyvault-audit.kql`](./queries/keyvault-audit.kql).

## Costos y limpieza

- Consumo bajo: operaciones de Key Vault e ingestión en Log Analytics.
- La limpieza elimina y **purga** los vaults, borra el workspace y los grupos, y solo informa éxito si lo verifica.

## Limitaciones

- La restricción de **suscripción** se documenta pero no se prueba (requiere una segunda suscripción).
- No se prueban certificados, claves en HSM ni Managed HSM.
- Los vaults usan acceso público; en producción evaluar Private Endpoints y firewall.
