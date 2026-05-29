#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PORT="${S_SENTINEL_PORTAL_WEB_PORT:-18081}"
API_HOST="${S_SENTINEL_PORTAL_API_HOST:-127.0.0.1}"
API_PORT="${S_SENTINEL_PORTAL_API_PORT:-18090}"
DIST_DIR="${S_SENTINEL_PORTAL_DIST_DIR:-web/dist}"
LOG_FILE="${S_SENTINEL_PORTAL_WEB_LOG:-/tmp/s-sentinel-portal-web.log}"

if [ ! -f "$DIST_DIR/index.html" ]; then
  echo "ERROR: $DIST_DIR/index.html not found."
  echo "Build frontend on Windows and upload web/dist first."
  exit 1
fi

pkill -f "portal-static-proxy.py.*--port ${PORT}" 2>/dev/null || true

nohup python3 scripts/portal-static-proxy.py \
  --host 0.0.0.0 \
  --port "$PORT" \
  --dist-dir "$DIST_DIR" \
  --api-host "$API_HOST" \
  --api-port "$API_PORT" \
  > "$LOG_FILE" 2>&1 &

sleep 1

echo "Portal Web started:"
echo "  URL:      http://$(hostname -I | awk '{print $1}'):${PORT}"
echo "  API:      ${API_HOST}:${API_PORT}"
echo "  dist:     ${DIST_DIR}"
echo "  log:      ${LOG_FILE}"
ss -lntp | grep ":${PORT}" || true
