# rdgen — generador de clientes RustDesk personalizados

Auto-hospedado. Genera instaladores de RustDesk con el servidor, la Key y la marca
ya dentro, para no configurar cada equipo a mano.

- Upstream: [bryangerlach/rdgen](https://github.com/bryangerlach/rdgen) (GPL-3.0)
- Fork: [AngelGzS/rdgen](https://github.com/AngelGzS/rdgen)

## Cómo funciona

rdgen **no compila nada**. Es una interfaz Django que dispara los workflows de
GitHub Actions del fork; el build corre en los runners de GitHub (30-45 min) y el
artefacto se devuelve al servidor rdgen vía `GENURL`.

Por eso **rdgen tiene que ser alcanzable desde internet**: si no, Actions no puede
entregar el ejecutable. No sirve dejarlo solo en la red interna.

## ⚠️ Seguridad — leer antes de desplegar

El upstream **no tiene autenticación ni CSRF**:

- `rdgenerator/views.py` y `api_views.py`: cero `login_required` / `IsAuthenticated`.
- `rdgen/settings.py`: `django.middleware.csrf.CsrfViewMiddleware` está comentado.

Publicado tal cual, cualquiera que dé con la URL puede lanzar builds (quemando tus
minutos de GitHub Actions) y generar clientes apuntando a tu servidor RustDesk.

**No lo despliegues con el dominio público hasta resolver esto.** Ver «Pendiente»
más abajo.

## Cambios respecto al compose del upstream

| Upstream | Aquí | Por qué |
|---|---|---|
| `ports: 8000:8000` | `expose: 8000` | El 8000 del host es **Coolify**. Publicarlo lo tumba. Traefik lo sirve con TLS. |
| bind mounts `./exe`, `./png`, `./temp_zips` | volúmenes con nombre | Coolify no maneja bien rutas relativas. |
| secretos en claro en el YAML | variables de entorno | No van al repo. |

## Estado del despliegue

| Pieza | Estado |
|---|---|
| Fork `AngelGzS/rdgen` | ✅ creado |
| GitHub Actions en el fork | ✅ habilitado (13 workflows) |
| Secret `GENURL` | ✅ `https://rdgen.zionnet.com.mx` |
| Secret `ZIP_PASSWORD` | ✅ generado |
| Recurso en Coolify | ✅ `dgkgccwok4c48c4ssw0wgkks` (proyecto rustdesk, **sin desplegar**) |
| `RDGEN_HOST`, `GH_USER`, `RDGEN_SECRET_KEY`, `RDGEN_ZIP_PASSWORD` | ✅ puestas |
| `SERVICE_FQDN_RDGEN_8000` | ✅ puesta |
| `GH_BEARER` | ❌ **pendiente** — token fine-grained, lo tienes que crear tú |
| DNS `rdgen.zionnet.com.mx` | ❌ **pendiente** — registro A al VPS |
| Protección de acceso | ❌ **pendiente** — ver abajo |

## Pendiente: crear el token de GitHub

1. GitHub → foto de perfil → Settings → Developer Settings
2. Personal access tokens → **Fine-grained tokens** → Generate new token
3. Repository access → **Only select repositories** → `AngelGzS/rdgen`
4. Permissions → Repository permissions → **Actions: Read and write**
5. Copia el token y pégalo en la variable `GH_BEARER` del recurso en Coolify

## Pendiente: protección de acceso

Coolify 4.0.0-beta.463 **no ofrece Basic Auth para servicios de tipo compose**
(solo para *applications*). Opciones, sin resolver todavía:

1. Recrear el recurso como *application* apuntando a este repo
   (`docker_compose_location: /rdgen/docker-compose.yml`), que sí expone el toggle
   de Basic Auth.
2. Añadir labels de Traefik `basicauth` al compose, con el riesgo de que Coolify
   sobrescriba el `middlewares` del router que genera.
3. Levantarlo solo cuando se vaya a generar un cliente y apagarlo después. Es el
   modo de uso real (se usa unas pocas veces al año), y reduce la ventana a casi cero.

## Uso, una vez arriba

1. Entrar a `https://rdgen.zionnet.com.mx`
2. Rellenar servidor, Key, nombre de la app e icono
3. Lanzar el build y esperar 30-45 min
4. Descargar el `.exe` (viene en un zip protegido con `ZIP_PASSWORD`)

Notas del upstream: iconos cuadrados (256x256), y sin acentos ni caracteres
especiales en el nombre de la app ni del archivo.

### Datos de tu servidor

```
ID Server:    rustdesk.zionnet.com.mx
Relay Server: rustdesk.zionnet.com.mx
API Server:   https://rustdesk-panel.zionnet.com.mx
Key:          BZ7q4kmCfxn90MqWjs9+M3DGUIwYWfhg5UtgfNPnH88=
```
