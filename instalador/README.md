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

## Ojo: es público

Cualquiera con la URL puede descargar. Es lo que quieres para que un cliente
se lo instale solo, pero significa que el ejecutable con tu servidor y tu Key
está accesible. La Key pública no es un secreto (va en todos los clientes),
pero no publiques la URL más de lo necesario.

Si quisieras cerrarlo, este recurso sí admitiría Basic Auth recreándolo como
*application* desde el repo — pero entonces el cliente tendría que teclear
usuario y contraseña para bajarlo.
