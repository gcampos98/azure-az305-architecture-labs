# Azure Solutions Architect Expert (AZ-305) — Architecture Labs

![Azure](https://img.shields.io/badge/Microsoft%20Azure-AZ--305-0078D4?logo=microsoftazure&logoColor=white)
![IaC](https://img.shields.io/badge/IaC-Azure%20CLI-4EAA25?logo=gnubash&logoColor=white)
![FinOps](https://img.shields.io/badge/FinOps-Cost%20Governed-success)

Repositorio de laboratorios prácticos diseñados para validar decisiones de arquitectura empresarial en Microsoft Azure bajo los dominios oficiales de la certificación **AZ-305 (Designing Microsoft Azure Infrastructure Solutions)**, operando con control estricto de cuotas (4 vCPUs por región) y destrucción auditada de recursos.

---

## Índice de Laboratorios

| # | Dominio AZ-305 | Laboratorio | Servicios Clave | Estado |
| :--- | :--- | :--- | :--- | :--- |
| **01** | Continuidad Empresarial (BCDR) | [`01-bcdr-sql-backup-keyvault`](./01-bcdr-sql-backup-keyvault) | Azure SQL Failover Groups, Storage GZRS, Azure Backup (RSV), Key Vault | En revisión |
| **01B** | Continuidad Empresarial (BCDR) | [`01b-bcdr-asr-azure-backup`](./01b-bcdr-asr-azure-backup) | Azure Site Recovery, Azure Backup con retención a largo plazo, Storage GZRS | En validación |
| **01C** | Continuidad Empresarial y Seguridad | [`01c-keyvault-backup-restore`](./01c-keyvault-backup-restore) | Azure Key Vault, RBAC, backup y restore entre regiones, Log Analytics | En validación |
| **02** | Redes e Hibridez | [`02-networking-hybrid-privatelink`](./02-networking-hybrid-privatelink) | VNet Peering, Service Endpoints vs. Private Endpoints, Network Watcher | Planificado |
| **03** | Integración de Datos | [`03-data-integration-adf-servicebus`](./03-data-integration-adf-servicebus) | Azure Data Factory, ADLS Gen2, Service Bus, Managed Identities | Planificado |

---

## Estándares de Implementación y Gobernanza

* **Automatización reproducible:** Cada laboratorio implementado separa aprovisionamiento (`01-deploy.sh`), pruebas (`02-test*.sh`) y destrucción ordenada (`03-cleanup.sh`). Las funciones comunes de 01B y 01C están en [`shared/`](./shared).
* **Calidad:** GitHub Actions revisa los scripts con ShellCheck en cada cambio.
* **Evidencia técnica sanitizada:** Se documentan salidas reales de consola y pruebas funcionales eliminando identificadores sensibles (`Subscription ID`, credenciales y secretos).
* **Gobernanza FinOps:** Se eligen SKUs de bajo costo cuando cumplen el objetivo del laboratorio (no todos son gratuitos). Al finalizar se ejecuta la limpieza y se verifica; los elementos en *soft delete* pueden persistir según la política del servicio.
