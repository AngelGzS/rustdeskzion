# RustDesk Server (self-hosted) en Coolify

Servidor RustDesk open source desplegable como **Docker Compose** en Coolify.
Componentes:

- **hbbs** — ID/Rendezvous server: registro de IDs, heartbeat y NAT hole-punching.
- **hbbr** — Relay server: reenvía el tráfico cuando la conexión directa P2P falla.
- **rustdesk-api** — API Server + **panel de admin web** ([lejianwen/rustdesk-api](https://github.com/lejianwen/rustdesk-api), open source). Opcional.

---

## 1. Requisitos previos

- Una instancia de **Coolify** corriendo en un VPS con **IP pública**.
- Acceso para abrir puertos en el firewall (cloud + host).
- Un subdominio con registro **A** apuntando a la IP pública del VPS.
- Si quieres el panel: un **segundo subdominio** (también registro A al mismo VPS).

## 2. Puertos a abrir en el firewall

| Puerto  | Protocolo | Servicio | Uso                              |
|---------|-----------|----------|----------------------------------|
| 21115   | TCP       | hbbs     | NAT type test                    |
| 21116   | TCP       | hbbs     | Registro de ID / heartbeat       |
| **21116** | **UDP** | hbbs     | **Hole punching (imprescindible)** |
| 21117   | TCP       | hbbr     | Relay                            |
| 21118   | TCP       | hbbs     | Cliente web (opcional)           |
| 21119   | TCP       | hbbr     | Relay cliente web (opcional)     |
| 80, 443 | TCP       | Traefik  | Panel de admin (ya abiertos por Coolify) |

> ⚠️ El **UDP 21116** es el que más se olvida. Sin él los clientes no se registran.
> Si el VPS está en un cloud (Hetzner/AWS/etc.), abre los puertos **tanto en el firewall del cloud como en el del SO** (ufw/firewalld).

El puerto **21114** del panel **no** se publica al host: entra por Traefik en 443.

Ejemplo con `ufw`:

```bash
ufw allow 21115:21119/tcp
ufw allow 21116/udp
```

## 3. DNS

Crea un registro **A** (y un segundo si usas el panel):

```
rustdesk.tu-dominio.com.         A   <IP_PUBLICA_DEL_VPS>
rustdesk-panel.tu-dominio.com.   A   <IP_PUBLICA_DEL_VPS>
```

> No uses CNAME a un proxy para el de **hbbs/hbbr** (Cloudflare en modo proxy NO
> funciona: RustDesk usa TCP/UDP crudos, no HTTP). Déjalo en **DNS only** (nube gris).
> El del **panel** sí es HTTP normal y puede ir proxeado si quieres.

## 4. Despliegue en Coolify

1. En Coolify: **+ New Resource → Docker Compose** (Empty / desde repo Git).
2. Pega el contenido de `docker-compose.yml`.
3. En **Environment Variables**, define las de `.env.example`.
4. **NO** asignes dominio/FQDN a `hbbs` ni a `hbbr`: no queremos que Traefik
   intercepte esos puertos. Se exponen directos al host vía `ports:`.
5. Al servicio **`rustdesk-api`** sí le asignas el dominio (`RUSTDESK_API_HOST`)
   en su campo **Domains**, apuntando al puerto **21114**.
6. **Deploy**.

> Si en el primer deploy aún no tienes la key, despliega sin `rustdesk-api`
> (o con `RUSTDESK_KEY` vacío), saca la key con el paso 5 y redespliega.

## 5. Obtener la clave pública (necesaria para los clientes)

Al primer arranque, hbbs/hbbr generan un par de claves en `/root` (volumen `rustdesk-data`).
Los clientes necesitan la **clave pública** para conexiones cifradas.

⚠️ **Coolify ignora `container_name:`** y genera nombres propios
(`hbbs-<uuid>-<timestamp>`), así que primero averigua el real:

```bash
docker ps --format '{{.Names}}\t{{.Image}}' | grep rustdesk
```

⚠️ La imagen `rustdesk/rustdesk-server` es **scratch**: no tiene shell ni `cat`,
por lo que `docker exec ... cat` falla con
`exec: "cat": executable file not found in $PATH`. Usa `docker cp`:

```bash
docker cp <nombre-real-de-hbbs>:/root/id_ed25519.pub /tmp/rustdesk.pub && cat /tmp/rustdesk.pub; echo
```

Alternativa leyendo el volumen desde el host (no depende del contenedor):

```bash
find /var/lib/docker/volumes -name 'id_ed25519.pub' -exec sh -c 'echo "== $1"; cat "$1"; echo' _ {} \;
```

Copia ese string (base64, ~44 chars, termina en `=`) **sin el salto de línea**.
Es la "Key" que se pega en el cliente y en `RUSTDESK_KEY`.

## 6. Configurar el cliente RustDesk

En el cliente: **⋮ → Network / Red → ID/Relay Server**:

- **ID Server:**    `rustdesk.tu-dominio.com`
- **Relay Server:** `rustdesk.tu-dominio.com`
- **API Server:**   `https://rustdesk-panel.tu-dominio.com` (vacío si no usas el panel)
- **Key:**          `<contenido de id_ed25519.pub>`

## 7. Verificación

```bash
# Contenedores arriba
docker ps | grep rustdesk

# hbbs escuchando en 21116 TCP y UDP
ss -tulnp | grep 2111

# Panel respondiendo
curl -I https://rustdesk-panel.tu-dominio.com/_admin/
```

En los logs de hbbs deberías ver el registro de los clientes cuando conecten.

## 8. Panel de admin

El servidor OSS (`hbbs` + `hbbr`) **no trae panel**: es solo broker de IDs y relay.
El servicio `rustdesk-api` lo añade: usuarios y grupos, libreta de direcciones
compartida, listado de dispositivos, cliente web y login OIDC.

- **URL:** `https://rustdesk-panel.tu-dominio.com/_admin/`
- **Usuario:** `admin`
- **Contraseña:** se genera en el primer arranque y **se imprime en los logs**
  del contenedor (en versiones antiguas era `admin`). Míralos en Coolify o con:

  ```bash
  docker logs $(docker ps -q -f ancestor=lejianwen/rustdesk-api:latest) 2>&1 | head -40
  ```

  Cámbiala en cuanto entres.

### Lo que NO cubre

`MUST_LOGIN` (obligar a iniciar sesión antes de poder conectar) requiere el fork
`lejianwen/rustdesk-server-s6`, que reemplaza a hbbs/hbbr oficiales. No lo usamos
aquí para no tocar un servidor que ya funciona y cuya key ya está generada.

### Alternativa oficial de pago

[RustDesk Server Pro](https://rustdesk.com/pricing/) trae consola web propia en el
puerto 21114, 2FA, logs de auditoría, generador de cliente personalizado y
OIDC/LDAP. Desde $9.90/mes (Individual: 1 usuario, 20 dispositivos). Se migra
cambiando la imagen a `rustdesk/rustdesk-server-pro` conservando el volumen de
claves, así que los clientes no se reconfiguran.

## 9. Seguridad

### `ENCRYPTED_ONLY=1` — relay abierto

Por defecto, **`hbbs` genera y exige clave, pero `hbbr` deja `KEY` vacío a
propósito** para simplificar el setup. Consecuencia: cualquiera que apunte su
cliente a `<tu-host>:21117` usa tu relay **sin tener tu Key** — tu ancho de banda,
gratis, para desconocidos.

El compose fija `ENCRYPTED_ONLY: "1"` en ambos servicios, lo que añade validación
de clave a los dos.

> ⚠️ Si ya tienes clientes desplegados **sin** la Key configurada, dejarán de
> conectar en cuanto actives esto. Ponles la Key primero.

### Panel: lo que protege y lo que no

| | Estado |
|---|---|
| Sesión de escritorio remoto | **Cifrada extremo a extremo entre clientes.** Ni el relay ni el panel ven el contenido. |
| `RUSTDESK_API_JWT_KEY` | Obligatoria. **Si queda vacía, el JWT no se activa.** Genera con `openssl rand -hex 32`. |
| Captcha | Activo tras 3 intentos fallidos. |
| Ban por IP | Activo tras 5 intentos. El default del proyecto es `0` = desactivado. |
| 2FA / TOTP | **No existe** en el panel OSS. Solo en RustDesk Server Pro. |
| Contraseña inicial de admin | Se imprime en los logs del primer arranque. **Cámbiala de inmediato.** |

Lo que queda expuesto a internet es la libreta de direcciones (el inventario de
equipos) y los logs de conexión. No es la sesion remota, pero tampoco es público:
usa una contraseña de admin fuerte y considera restringir el acceso al panel por
IP en Coolify si solo lo usa tu equipo.

### Backup

Dos volúmenes con datos irrecuperables. Ver **[docs/BACKUP.md](docs/BACKUP.md)**.

---

## Notas

- **Persistencia:** la clave vive en el volumen `rustdesk-data`. No lo borres o cambiará
  la Key y todos los clientes tendrán que reconfigurarse.
- **Backup:** ver [docs/BACKUP.md](docs/BACKUP.md). Respalda `rustdesk-data`
  (claves + `db_v2.sqlite3`) y `rustdesk-api-data` (usuarios y libreta del panel).
- **Base de datos:** ambas son SQLite. El panel acepta MySQL vía
  `RUSTDESK_API_GORM_TYPE=mysql`, innecesario a esta escala.
