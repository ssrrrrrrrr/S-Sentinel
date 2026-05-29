#!/usr/bin/env bash
set -euo pipefail

PORT="${S_SENTINEL_PORTAL_WEB_PORT:-18081}"
LOG_FILE="${S_SENTINEL_PORTAL_WEB_LOG:-/tmp/s-sentinel-portal-web.log}"

echo "===== listening ====="
ss -lntp | grep ":${PORT}" || true

echo "===== config ====="
curl -sS "http://127.0.0.1:${PORT}/config.json" || true
echo

echo "===== api sample ====="
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

if curl -sS "http://127.0.0.1:${PORT}/api/releases/latest" -o "$tmp_file"; then
  head -c 300 "$tmp_file"
else
  echo "failed to fetch /api/releases/latest"
fi
echo

echo "===== log ====="
tail -30 "$LOG_FILE" 2>/dev/null || true
