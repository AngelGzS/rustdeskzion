# Backup y restauración

Hay **dos volúmenes** con datos que no se pueden regenerar:

| Volumen | Contenido | Si lo pierdes… |
|---|---|---|
| `rustdesk-data` | `id_ed25519` / `.pub` + `db_v2.sqlite3` (IDs y peers registrados) | Cambia la Key → **todos los clientes hay que reconfigurarlos** |
| `rustdesk-api-data` | SQLite del panel: usuarios, libreta de direcciones, grupos, tags, logs de conexión | Pierdes el inventario de equipos y el histórico de accesos |

> Coolify prefija los volúmenes con el UUID del recurso
> (`t44kgw4cosc0gwkcg00ggwss_rustdesk-data`). Localiza los reales con:
>
> ```bash
> docker volume ls | grep rustdesk
> ```

## Backup manual

```bash
#!/bin/bash
set -euo pipefail
DEST=/var/backups/rustdesk
STAMP=$(date +%F)
mkdir -p "$DEST"

for VOL in $(docker volume ls -q | grep rustdesk); do
  docker run --rm \
    -v "$VOL":/data:ro \
    -v "$DEST":/backup \
    alpine tar czf "/backup/${VOL}-${STAMP}.tar.gz" -C /data .
done

# Conserva 30 días
find "$DEST" -name '*.tar.gz' -mtime +30 -delete
ls -lh "$DEST"
```

Guárdalo como `/usr/local/bin/rustdesk-backup.sh`, dale `chmod +x` y prográmalo:

```bash
echo '0 3 * * * /usr/local/bin/rustdesk-backup.sh >> /var/log/rustdesk-backup.log 2>&1' | crontab -
```

> **Saca los `.tar.gz` del VPS.** Un backup que vive en la misma máquina que
> respalda no es un backup. Sincronízalos a S3/rclone/otro host.

## Backup mínimo (solo la Key)

Lo imprescindible. Cabe en un gestor de contraseñas:

```bash
HBBS=$(docker ps --format '{{.Names}}' | grep '^hbbs-')
docker cp "$HBBS":/root/id_ed25519     /tmp/id_ed25519
docker cp "$HBBS":/root/id_ed25519.pub /tmp/id_ed25519.pub
cat /tmp/id_ed25519.pub; echo
```

⚠️ `id_ed25519` es la **clave privada**. Trátala como una contraseña: no la subas
al repo (el `.gitignore` ya cubre `*.pub`/`id_ed25519`, verifícalo antes de commitear).

## Restauración

Con el stack **parado** en Coolify:

```bash
VOL=t44kgw4cosc0gwkcg00ggwss_rustdesk-data   # el nombre real
ARCHIVO=/var/backups/rustdesk/${VOL}-2026-09-20.tar.gz

docker run --rm \
  -v "$VOL":/data \
  -v /var/backups/rustdesk:/backup:ro \
  alpine sh -c 'rm -rf /data/* && tar xzf /backup/'"$(basename "$ARCHIVO")"' -C /data'
```

Arranca el stack y verifica que la Key sigue siendo la misma:

```bash
docker cp "$(docker ps --format '{{.Names}}' | grep '^hbbs-')":/root/id_ed25519.pub - | tar xO
```

## Antes de migrar de VPS

Restaura `rustdesk-data` en el destino **antes** del primer arranque. Si dejas que
hbbs arranque en limpio, generará una key nueva y ya no podrás recuperar la vieja.
