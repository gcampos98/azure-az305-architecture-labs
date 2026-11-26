# Laboratorio 01: Arquitectura de Continuidad Empresarial y Recuperación ante Desastres (BCDR) en Azure

![Azure](https://img.shields.io/badge/Microsoft%20Azure-AZ--305-0078D4?logo=microsoftazure&logoColor=white)
![IaC](https://img.shields.io/badge/Automation-Azure%20CLI-4EAA25?logo=gnubash&logoColor=white)
![Domain](https://img.shields.io/badge/Domain-Business%20Continuity%20%26%20DR-orange)

## 1. Caso de Negocio y Objetivo Arquitectónico

Diseñar e implementar una arquitectura resiliente multi-región dentro de la **Geografía de Estados Unidos** (`centralus` como región primaria y `westus3` como región secundaria de DR) capaz de garantizar **RPO/RTO bajos** para datos transaccionales, protección contra fallos zonales y regionales para almacenamiento no estructurado, respaldo automatizado de cargas IaaS y recuperación intrageográfica de secretos criptográficos, operando bajo restricciones estrictas de cuota (4 vCPUs por región) y gobernanza FinOps[cite: 2, 3].

---

## 2. Diagrama de Arquitectura

```mermaid
flowchart TB
    subgraph GeoUS["Geografía: United States"]
        subgraph Pri["Región Primaria: Central US (rg-az305-bcdr-pri)"]
            SQL_P[("Azure SQL Server Pri<br/>db-ventas-critica (S0)")]
            STG_P["Storage Account V2<br/>SKU: Standard_GZRS<br/>(3 copias síncronas ZRS)"]
            VM_P["Ubuntu VM<br/>Standard_B1s (1 vCPU)"]
            RSV_P["Recovery Services Vault<br/>(DefaultPolicy Backup)"]
            KV_P["Azure Key Vault Pri<br/>(CadenaConexionProd)"]
            
            VM_P -->|Backup diario / On-demand| RSV_P
        end

        subgraph Sec["Región Secundaria DR: West US 3 (rg-az305-bcdr-sec)"]
            SQL_S[("Azure SQL Server Sec<br/>Réplica Geo-sincronizada")]
            STG_S["Réplica Storage Secundaria<br/>(3 copias asíncronas LRS)"]
            KV_S["Azure Key Vault Sec<br/>(Secreto Restaurado)"]
        end

        FOG["SQL Auto-Failover Group<br/>fog-az305-xxxx.database.windows.net<br/>(Endpoint Único R/W)"]

        SQL_P <-->|Replicación Asíncrona & Failover| FOG
        FOG <-->|Promoción R/W en DR| SQL_S
        STG_P -.->|Replicación Geo-Asíncrona| STG_S
        KV_P -.->|Backup cifrado & Restore<br/>Misma Suscripción / Geografía| KV_S
    end

---
## 3. Decisiones de Arquitectura (ADR — Criterios Examen AZ-305)

| Componente | Tecnología Seleccionada | Alternativa Descartada | Justificación Técnica (AZ-305) |
| :--- | :--- | :--- | :--- |
| **Base de Datos Relacional PaaS** | **Azure SQL Auto-Failover Group** | Active Geo-Replication / Zone Redundancy | *Active Geo-Replication* solo proporciona réplicas de lectura y exige conmutación manual; *Zone Redundancy* solo protege dentro de una misma región. **Auto-Failover Groups** mantiene capacidad de **lectura y escritura** tras un fallo regional sin cambiar cadenas de conexión mediante un endpoint único (`*.database.windows.net`). |
| **Almacenamiento de Objetos** | **Standard GZRS** | LRS / ZRS / GRS | Combina la alta disponibilidad síncrona entre 3 Zonas de Disponibilidad en la región primaria (**ZRS**) con replicación asíncrona hacia una región secundaria con 3 copias adicionales (**LRS**), totalizando **6 copias**. |
| **Protección de Cargas IaaS** | **Azure Backup (Recovery Services Vault)** | Snapshots manuales no gestionados | Automatiza políticas de retención a corto y largo plazo (LTR) y aislamiento mediante *Soft Delete* contra eliminación accidental o ransomware. |
| **Gestión de Secretos DR** | **Key Vault Backup & Restore** | Replicación manual en texto plano | Los respaldos de Key Vault se exportan como blobs cifrados que solo pueden restaurarse dentro de la **misma suscripción y misma geografía de Azure** (`centralus` → `westus3`). |
