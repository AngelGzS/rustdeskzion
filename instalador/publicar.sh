#!/usr/bin/env bash
# Publica el último cliente compilado en https://rustdesk-panel.zionnet.com.mx/instalador/
#
# Se ejecuta EN EL VPS. Modelo "pull": el VPS baja el artefacto de GitHub.
# Deliberadamente NO al revés: dar a GitHub Actions acceso SSH al VPS sería
# mucho más peligroso que un token de solo lectura aquí.
#
# Requiere un token fine-grained con acceso SOLO a AngelGzS/rdgen-zion y
# permisos de lectura en Actions, Contents y Metadata.
#
#   export GH_TOKEN=github_pat_xxx
#   ./publicar.sh
#
set -euo pipefail

REPO="${REPO:-AngelGzS/rdgen-zion}"
WORKFLOW="${WORKFLOW:-generator-windows.yml}"
ARTIFACT="${ARTIFACT:-rustdesk-custom-client-windows}"
: "${GH_TOKEN:?Falta GH_TOKEN. Ver la cabecera de este script.}"

for c in curl unzip docker; do
  command -v "$c" >/dev/null || { echo "Falta '$c'." >&2; exit 1; }
done

# jq si está; si no, python3
if command -v jq >/dev/null; then
  pick() { jq -r "$1"; }
elif command -v python3 >/dev/null; then
  pick() { python3 -c "
import json,sys
d=json.load(sys.stdin)
expr='''$1'''.strip()
if expr.startswith('.runs[0].id'): print(d['workflow_runs'][0]['id'] if d['workflow_runs'] else '')
else:
    m=[a for a in d['artifacts'] if a['name']=='$ARTIFACT']
    print(m[0]['archive_download_url'] if m else '')
"; }
else
  echo "Falta jq o python3." >&2; exit 1
fi

api() { curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

echo "==> Buscando el último build correcto de $WORKFLOW"
if command -v jq >/dev/null; then
  RUN=$(api "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW/runs?status=success&per_page=1" \
        | jq -r '.workflow_runs[0].id // empty')
else
  RUN=$(api "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW/runs?status=success&per_page=1" \
        | pick '.runs[0].id')
fi
[ -n "$RUN" ] || { echo "No hay ningún build correcto todavía." >&2; exit 1; }
echo "    run $RUN"

if command -v jq >/dev/null; then
  URL=$(api "https://api.github.com/repos/$REPO/actions/runs/$RUN/artifacts" \
        | jq -r --arg n "$ARTIFACT" '.artifacts[] | select(.name==$n) | .archive_download_url')
else
  URL=$(api "https://api.github.com/repos/$REPO/actions/runs/$RUN/artifacts" | pick 'artifact')
fi
[ -n "$URL" ] || { echo "El run $RUN no tiene el artefacto '$ARTIFACT' (¿caducó? duran 30 días)." >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "==> Descargando artefacto"
curl -fsSL -H "Authorization: Bearer $GH_TOKEN" "$URL" -o "$TMP/a.zip"
unzip -q -o "$TMP/a.zip" -d "$TMP/out"

shopt -s nullglob
FILES=("$TMP/out"/*.exe "$TMP/out"/*.msi)
[ ${#FILES[@]} -gt 0 ] || { echo "El artefacto no trae .exe ni .msi." >&2; exit 1; }

CONT=$(docker ps --format '{{.Names}}' | grep '^instalador-' | head -1)
[ -n "$CONT" ] || { echo "No encuentro el contenedor del instalador. ¿Está desplegado?" >&2; exit 1; }

echo "==> Copiando a $CONT:/srv"
for f in "${FILES[@]}"; do
  docker cp "$f" "$CONT":/srv/
  echo "    $(basename "$f")"
done

echo
echo "==> Publicado:"
docker exec "$CONT" ls -lh /srv
echo
echo "    https://rustdesk-panel.zionnet.com.mx/instalador/"
