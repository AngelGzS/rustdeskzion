# Generador de clientes RustDesk personalizados

Compila un RustDesk con **nuestro servidor, nuestra Key y nuestra marca** ya
embebidos, para no configurar equipo por equipo.

- Repo: **[AngelGzS/rdgen-zion](https://github.com/AngelGzS/rdgen-zion)** (privado)
- Basado en [bryangerlach/rdgen](https://github.com/bryangerlach/rdgen) (GPL-3.0)

## Sin servidor rdgen

El diseño original monta una app Django pública: el workflow baja la config de
`GENURL` y devuelve el `.exe` por POST a `GENURL/save_custom_client`. Esa app
**no tiene autenticación ni CSRF**, así que no la exponemos. No hay ningún
recurso rdgen desplegado en Coolify.

En su lugar el workflow está parcheado:

| Original | Aquí |
|---|---|
| Baja la config de `GENURL` | La construye desde el secret `CLIENT_CONFIG_JSON` |
| Devuelve el `.exe` por POST | Lo publica con `actions/upload-artifact` |
| POST a `GENURL/cleanzip` | Eliminado |

El cifrado del zip intermedio se mantiene igual (`ZIP_PASSWORD`), así que el
resto del workflow —700 líneas— queda intacto.

## Por qué un repo privado y no un fork

**Un fork de un repo público en GitHub es siempre público**; no existe la
opción de hacerlo privado. Eso dejaría a la vista los logs de build y los
artefactos. Por eso `rdgen-zion` es un repo privado normal con el código
copiado, no un fork.

Coste: los repos privados gastan cuota de Actions. Un build de Windows son
~45 min y los runners Windows cuentan x2, o sea ~90 min de los 2000/mes del
plan gratuito. Da para unos 20 builds al mes.

> Si algún día hay que reindexar los workflows tras mover el repo: GitHub solo
> indexa los de `workflow_dispatch` cuando llegan en un push que los modifica.
> Un commit vacío no basta; hay que tocar los archivos.

## Generar un cliente

```bash
gh workflow run generator-windows.yml -R AngelGzS/rdgen-zion -f version=1.4.6
gh run watch -R AngelGzS/rdgen-zion
```

Tarda 30-45 min. Luego, **en el VPS**:

```bash
export GH_TOKEN=github_pat_xxx     # fine-grained, solo lectura sobre rdgen-zion
../instalador/publicar.sh
```

Queda en https://rustdesk-panel.zionnet.com.mx/instalador/

## Las dos variantes

| | 64 bits | 32 bits |
|---|---|---|
| Workflow | `generator-windows.yml` | `generator-windows-x86.yml` |
| Target | `x86_64-pc-windows-msvc` | `i686-pc-windows-msvc` |
| Interfaz | Flutter | **sciter** |
| Artefacto | `rustdesk-custom-client-windows` | `rustdesk-custom-client-windows-x86` |
| Para | Windows 10/11 | **Windows 7** de las sucursales |

Los dos están parcheados igual. Para publicar el de 32 bits hay que decirle a
`publicar.sh` cuál bajar:

```bash
WORKFLOW=generator-windows-x86.yml ARTIFACT=rustdesk-custom-client-windows-x86 GH_TOKEN=github_pat_xxx ../instalador/publicar.sh
```

### El campo `custom` no es opcional

`CLIENT_CONFIG_JSON` tiene una clave `custom` con **base64 de un JSON**. Dejarla
vacía parece inocuo y no lo es: de ahí sale `app-name`, que decide la ruta de
instalación, los accesos directos, el servicio y el registro. Sin ella el cliente
se instala como `C:\Program Files\RustDesk`, no crea accesos directos y queda
pidiendo que lo instales otra vez. Los `sed` del workflow solo cambian recursos
cosméticos del ejecutable, no el nombre interno.

De ahí sale también la contraseña permanente.

```json
{
  "app-name": "ZionDesk",
  "password": "...",
  "default-settings":  { "verification-method": "use-permanent-password" },
  "override-settings": { "custom-rendezvous-server": "...", "relay-server": "...",
                         "api-server": "...", "key": "..." }
}
```

`default-settings` se puede cambiar en el equipo; `override-settings` no. Por eso
la contraseña va en el primero y la infraestructura en el segundo.

Esto funciona porque rdgen parchea RustDesk para saltarse la verificación de
firma de ese archivo (es un mecanismo de la versión Pro). **Cada workflow usa un
parche distinto y escribe un nombre de archivo distinto** — son coherentes entre
sí, pero no los mezcles:

| | Parche | Archivo |
|---|---|---|
| x64 | `allowCustom.py` | `custom_.txt` |
| x86 | `allowCustom.diff` | `custom.txt` |

### ⚠️ Windows 7 no está garantizado

RustDesk publica builds x86-sciter hasta 1.4.6, pero **sus desarrolladores han
dicho que no van a arreglar problemas de Windows 7** («sistema muerto»), y hay
reportes de fallos con `1.4.3-x86-sciter` justo en Windows 7 SP1 de 32 bits.

Si 1.4.6 no arranca en una sucursal, se prueba una versión anterior sin tocar
nada más:

```bash
gh workflow run generator-windows-x86.yml -R AngelGzS/rdgen-zion -f version=1.3.9
```

Probar **siempre** en la VM copia de sucursal antes de desplegar a una tienda.

## Cambiar la configuración del cliente

Está en el secret `CLIENT_CONFIG_JSON`. Para editarlo:

```bash
gh secret set CLIENT_CONFIG_JSON -R AngelGzS/rdgen-zion < client_config.json
```

Dos trampas del formato, ya resueltas en la config actual:

- `decrypt-secrets` **descarta las claves vacías**. Si `iconlink_url` va en
  blanco, la variable no existe y la condición `!= 'false'` se cumple, así que
  los pasos de icono se ejecutan y fallan. Hay que poner el string `"false"`.
- `urlLink` y `downloadLink` llevan los valores por defecto de rustdesk
  (`https://rustdesk.com`, `https://rustdesk.com/download`) precisamente para
  que esos pasos de `sed` se salten.

Config actual: servidor `rustdesk.zionnet.com.mx`, app **ZionDesk**, empresa
**Zion Net**, sin icono personalizado.

## ⚠️ Verificar cada build

El paso que inyecta servidor y Key es `continue-on-error: true` en el upstream.
**Si falla, el build termina en verde pero el cliente apunta a los servidores
públicos de RustDesk.** Nunca des por bueno el ✅ sin comprobarlo:

```bash
strings ZionDesk.exe | grep -F 'rustdesk.zionnet.com.mx'
```

Si no sale nada, el build salió mal aunque GitHub lo marque correcto.
