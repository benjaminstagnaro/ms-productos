#!/usr/bin/env bash
# Captura el dashboard de Grafana como imagen (evidencia de cada ejecución del pipeline).
# Usa el Chrome que ya trae el runner de GitHub en modo headless: no instala paquetes extra.
# Uso: scripts/observabilidad/capturar-dashboard.sh <url_grafana> <archivo.png> [rango]
set -euo pipefail

GRAFANA="${1:?URL de Grafana}"
SALIDA="${2:?archivo de salida}"
RANGO="${3:-now-30m}"
CHROME="$(command -v google-chrome || command -v chromium || command -v chromium-browser)"

"$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
  --window-size=1600,3200 --virtual-time-budget=25000 \
  --screenshot="$SALIDA" \
  "$GRAFANA/d/ms-productos-devops/?orgId=1&from=$RANGO&to=now&kiosk" 2>/dev/null
ls -lh "$SALIDA"
