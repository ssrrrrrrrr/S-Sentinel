#!/usr/bin/env bash
set -euo pipefail

PORT="${S_SENTINEL_PORTAL_WEB_PORT:-18081}"

pkill -f "portal-static-proxy.py.*--port ${PORT}" 2>/dev/null || true
echo "Portal Web stopped on port ${PORT}"
