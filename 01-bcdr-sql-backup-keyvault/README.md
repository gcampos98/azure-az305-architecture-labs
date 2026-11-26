# Laboratorio 01: Continuidad Empresarial y Recuperación ante Desastres (BCDR)

> **Estado del laboratorio:** En progreso / En revisión (correcciones técnicas de auditoría en curso).  
> **Enfoque AZ-305:** Continuidad del negocio, almacenamiento de datos y monitoreo/observabilidad.

## Arquitectura de Referencia

En `centralus`, el almacenamiento con **GZRS** (`Standard_GZRS`) mantiene **3 copias síncronas entre zonas de disponibilidad (ZRS)** en la región primaria y **3 copias asíncronas en una única ubicación (LRS)** en la región secundaria emparejada (`eastus2`). Para **Azure SQL Database**, un *Auto-Failover Group* replica hacia una región secundaria (`westus3` en este laboratorio) con endpoints de lectura/escritura y solo lectura. Para **Azure Key Vault**, las copias cifradas de secretos, claves y certificados se restauran dentro de la **misma suscripción y geografía**.

```mermaid
flowchart LR
    subgraph PRI["Región Primaria: centralus"]
        VM["VM ARM64 (sin IP pública / sin SSH abierto)"]
        RSV["Recovery Services Vault"]
        SQL1["Azure SQL Server (Primario)"]
        KV1["Key Vault (RBAC)"]
        STG1["Storage Account GZRS (3 copias ZRS)"]
        LAW["Log Analytics Workspace"]
    end

    subgraph PAIR["Región Emparejada: eastus2"]
        STG2["Réplica GZRS (3 copias LRS)"]
        BK_PAIR["DR / Réplica de Respaldo"]
    end

    subgraph SEC["Región Secundaria SQL / DR: westus3"]
        SQL2["Azure SQL Server (Secundario)"]
        KV2["Key Vault destino (misma geografía)"]
    end

    VM --> RSV
    RSV -. "Réplica / DR" .-> BK_PAIR
    SQL1 <-->|"Auto-Failover Group"| SQL2
    STG1 -->|"Réplica asíncrona GZRS"| STG2
    KV1 -. "Backup/Restore (misma suscripción y geografía)" .-> KV2
    VM --> LAW
    SQL1 --> LAW
    KV1 --> LAW
