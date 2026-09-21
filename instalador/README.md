# Descarga de instaladores

Sirve los clientes RustDesk personalizados en
**https://rustdesk-panel.zionnet.com.mx/instalador/**

nginx con `autoindex`, así que la página es el listado de lo que haya en el
volumen. Sin índice que mantener a mano.

## Por qué comparte dominio con el panel

Traefik prioriza por longitud de regla: `PathPrefix(/instalador)` gana sobre el
`PathPrefix(/)` del panel. Coolify quita el prefijo, así que nginx recibe `/`.
Verificado: el panel sigue respondiendo 200 en `/_admin/`.

El dominio hay que ponerlo en la **UI de Coolify** (servicio → Settings →
Domains). Ni la API de servicios ni la variable mágica `SERVICE_FQDN_*`
funcionan si se añaden después de crear el recurso.

## Subir un instalador

El volumen es `n48sccg4o8gok04so4scgw8o_instalador-files`:

```bash
CONT=$(docker ps --format '{{.Names}}' | grep '^instalador-')
docker cp ./ZionDesk.exe "$CONT":/srv/
docker exec "$CONT" ls -lh /srv
```

Queda disponible al instante en
`https://rustdesk-panel.zionnet.com.mx/instalador/ZionDesk.exe`

## Acceso

Protegido con Basic Auth. Usuario **zion**; la contraseña está en la variable
`INSTALADOR_HTPASSWD_B64` del recurso en Coolify (hash apr1, no reversible) y
en el gestor de contraseñas del equipo.

El Basic Auth lo hace **nginx**, no Coolify: su toggle no existe para servicios
de tipo compose, y añadir middlewares de Traefik a mano es frágil porque
Coolify regenera los labels del router en cada deploy.

El contenedor **falla al arrancar si la variable falta**, para que un despiste
de configuración no deje la ruta abierta.

### Dos trampas, ya resueltas

- **El hash va en base64.** Empieza por `$apr1$` y docker compose interpola las
  variables del `.env`, así que `$apr1` se expandía a vacío y el htpasswd
  acababa siendo `zion:` sin hash — es decir, sin protección real.
- **`chmod 640` y `chown root:nginx`.** El worker de nginx corre como `nginx`,
  no como root: con `600` no puede leer el archivo y responde 500 en vez de
  pedir credenciales.

### Cambiar la contraseña

```bash
python -c "from passlib.hash import apr_md5_crypt as h; import base64,getpass;   print(base64.b64encode(('zion:'+h.hash(getpass.getpass())).encode()).decode())"
```

Pega el resultado en `INSTALADOR_HTPASSWD_B64` y redespliega.

### Comprobar

```bash
curl -o /dev/null -w '%{http_code}
' https://rustdesk-panel.zionnet.com.mx/instalador/          # 401
curl -o /dev/null -w '%{http_code}
' -u zion:LA_PASS https://rustdesk-panel.zionnet.com.mx/instalador/  # 200
```
