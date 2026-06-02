# RustDesk Server (self-hosted) en Coolify

Servidor RustDesk open source desplegable como **Docker Compose** en Coolify.
Componentes:

- **hbbs** — ID/Rendezvous server: registro de IDs, heartbeat y NAT hole-punching.
- **hbbr** — Relay server: reenvía el tráfico cuando la conexión directa P2P falla.

---

## 1. Requisitos previos

- Una instancia de **Coolify** corriendo en un VPS con **IP pública**.
- Acceso para abrir puertos en el firewall (cloud + host).
- Un subdominio con registro **A** apuntando a la IP pública del VPS.

## 2. Puertos a abrir en el firewall

| Puerto  | Protocolo | Servicio | Uso                              |
|---------|-----------|----------|----------------------------------|
| 21115   | TCP       | hbbs     | NAT type test                    |
| 21116   | TCP       | hbbs     | Registro de ID / heartbeat       |
| **21116** | **UDP** | hbbs     | **Hole punching (imprescindible)** |
| 21117   | TCP       | hbbr     | Relay                            |
| 21118   | TCP       | hbbs     | Cliente web (opcional)           |
| 21119   | TCP       | hbbr     | Relay cliente web (opcional)     |

> ⚠️ El **UDP 21116** es el que más se olvida. Sin él los clientes no se registran.
> Si el VPS está en un cloud (Hetzner/AWS/etc.), abre los puertos **tanto en el firewall del cloud como en el del SO** (ufw/firewalld).

Ejemplo con `ufw`:

```bash
ufw allow 21115:21119/tcp
ufw allow 21116/udp
```

## 3. DNS

Crea un registro **A**:

```
rustdesk.tu-dominio.com.   A   <IP_PUBLICA_DEL_VPS>
```

> No uses CNAME a un proxy (Cloudflare en modo proxy NO funciona: RustDesk usa TCP/UDP crudos, no HTTP). Si usas Cloudflare, deja el registro en **DNS only** (nube gris).

## 4. Despliegue en Coolify

1. En Coolify: **+ New Resource → Docker Compose** (Empty / desde repo Git).
2. Pega el contenido de `docker-compose.yml`.
3. En **Environment Variables**, define:
   - `RUSTDESK_RELAY_HOST` = `rustdesk.tu-dominio.com`
4. **NO** asignes un dominio/FQDN al servicio en Coolify: no queremos que el proxy
   (Traefik) intercepte estos puertos. Se exponen directos al host vía `ports:`.
5. **Deploy**.

## 5. Obtener la clave pública (necesaria para los clientes)

Al primer arranque, hbbs/hbbr generan un par de claves en `/root` (volumen `rustdesk-data`).
Los clientes necesitan la **clave pública** para conexiones cifradas.

Desde el host del VPS:

```bash
docker exec rustdesk-hbbs cat /root/id_ed25519.pub
```

Copia ese string (es la "Key" que se pega en el cliente).

## 6. Configurar el cliente RustDesk

En el cliente: **⋮ → Network / Red → ID/Relay Server**:

- **ID Server:**    `rustdesk.tu-dominio.com`
- **Relay Server:** `rustdesk.tu-dominio.com`
- **API Server:**   (vacío en la versión open source)
- **Key:**          `<contenido de id_ed25519.pub>`

## 7. Verificación

```bash
# Contenedores arriba
docker ps | grep rustdesk

# hbbs escuchando en 21116 TCP y UDP
ss -tulnp | grep 2111
```

En los logs de hbbs deberías ver el registro de los clientes cuando conecten.

---

## Notas

- **Persistencia:** la clave vive en el volumen `rustdesk-data`. No lo borres o cambiará
  la Key y todos los clientes tendrán que reconfigurarse.
- **Backup:** respalda `id_ed25519` e `id_ed25519.pub` del volumen.
- **Pro:** si en el futuro quieres consola web de admin / control de acceso, se migra a
  `rustdesk/rustdesk-server-pro` (requiere licencia).
