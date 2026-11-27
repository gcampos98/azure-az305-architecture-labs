# Evidencia Técnica Consolidada — az305-lab01c

> Salidas sanitizadas automáticamente (sin GUIDs, correos ni direcciones IPv4).

<!-- BEGIN:01-backup-restore.txt -->
## Bloque: `01-backup-restore.txt`
- **Generado (UTC):** `2026-11-27T14:26:54Z`

```text
Origen: kv1c-pri-5a25c7 (eastus)
Destino: kv1c-dr-5a25c7 (westus2)
secret db-connection-string: respaldo cifrado de 4092 bytes; restauradas 2 versiones
key cmk-app: respaldo cifrado de 9785 bytes; restauradas 2 versiones
Archivos de respaldo locales eliminados: sí
```
<!-- END:01-backup-restore.txt -->

<!-- BEGIN:02-verification.txt -->
## Bloque: `02-verification.txt`
- **Generado (UTC):** `2026-11-27T14:27:22Z`

```text
Secreto: 2 versiones con el mismo identificador y el mismo SHA-256: sí
Clave: 2 versiones; lo cifrado en origen se descifra en destino: sí
```
<!-- END:02-verification.txt -->

<!-- BEGIN:03-independence.txt -->
## Bloque: `03-independence.txt`
- **Generado (UTC):** `2026-11-27T14:27:38Z`

```text
Se creó una versión nueva del secreto en el origen.
Versiones en origen: 3
Versiones en destino: 2
La copia restaurada no se sincroniza (no es replicación): sí
```
<!-- END:03-independence.txt -->

<!-- BEGIN:04-cross-geography.txt -->
## Bloque: `04-cross-geography.txt`
- **Generado (UTC):** `2026-11-27T14:37:12Z`

```text
Origen: eastus   Intento de destino: brazilsouth
Escritura de control en el destino (permisos correctos): sí
Restauración rechazada: sí
Secreto presente en el destino: no
Mensaje devuelto por Azure:
ERROR: (Malformed backup blob) Cannot decrypt backup blob.
Code: Malformed backup blob
Message: Cannot decrypt backup blob.
```
<!-- END:04-cross-geography.txt -->
