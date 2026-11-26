# Azure Solutions Architect Expert (AZ-305) — Architecture Labs

![Azure](https://img.shields.io/badge/Microsoft%20Azure-AZ--305-0078D4?logo=microsoftazure&logoColor=white)
![IaC](https://img.shields.io/badge/IaC-Azure%20CLI-4EAA25?logo=gnubash&logoColor=white)
![FinOps](https://img.shields.io/badge/FinOps-Cost%20Governed-success)

Repositorio de laboratorios prácticos diseñados para validar decisiones de arquitectura empresarial en Microsoft Azure bajo los dominios oficiales de la certificación **AZ-305 (Designing Microsoft Azure Infrastructure Solutions)**, operando con control estricto de cuotas (4 vCPUs por región) y destrucción auditada de recursos.

---

## Índice de Laboratorios

| # | Dominio AZ-305 | Laboratorio | Servicios Clave | Estado |
| :--- | :--- | :--- | :--- | :--- |
| **01** | Continuidad Empresarial (BCDR) | [`01-bcdr-sql-backup-keyvault`](./01-bcdr-sql-backup-keyvault) | Azure SQL Auto-Failover Groups, Storage GZRS, Azure Backup (RSV), Key Vault DR | Completado |
| **02** | Redes e Hibridez | [`02-networking-hybrid-privatelink`](./02-networking-hybrid-privatelink) | VNet Peering, Service Endpoints vs. Private Endpoints, Network Watcher | En progreso |
| **03** | Integración de Datos | [`03-data-integration-adf-servicebus`](./03-data-integration-adf-servicebus) | Azure Data Factory, ADLS Gen2, Service Bus, Managed Identities | Pendiente |

---

## Estándares de Implementación y Gobernanza

* **Automatización reproducible:** Cada laboratorio contiene scripts desacoplados para aprovisionamiento (`01-deploy.sh`), validación de workloads (`02-test-workloads.sh`) y destrucción ordenada (`03-cleanup.sh`).
* **Evidencia técnica sanitizada:** Se documentan salidas reales de consola y pruebas funcionales eliminando identificadores sensibles (`Subscription ID`, credenciales y secretos).
* **Gobernanza FinOps:** Todos los entornos se aprovisionan priorizando SKUs de capa gratuita y se purgan completamente al finalizar cada sesión de pruebas.
