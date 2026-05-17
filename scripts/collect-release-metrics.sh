#!/bin/bash
set -euo pipefail

PROM_ADDR="${PROM_ADDR:-http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090}"
NAMESPACE="${NAMESPACE:-slo-rollout}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required}"

q() {
  local query="$1"
  local out
  out="$(curl -fsG --data-urlencode "query=${query}" "${PROM_ADDR}/api/v1/query" 2>/dev/null || true)"
  if [ -z "$out" ]; then
    echo "unknown"
    return 0
  fi
  echo "$out" | sed -n 's/.*"result":[[][{].*"value":[[][^,]*,"\([^"]*\)".*/\1/p' | head -n 1
}

REQUEST_COUNT_1M="$(q "(sum(increase(demo_http_requests_total{namespace=\"${NAMESPACE}\",version=\"${IMAGE_TAG}\"}[1m])) or on() vector(0))")"
ERROR_RATE_PERCENT="$(q "(((sum(rate(demo_http_requests_total{namespace=\"${NAMESPACE}\",version=\"${IMAGE_TAG}\",status=~\"5..\"}[1m])) or vector(0)) / clamp_min((sum(rate(demo_http_requests_total{namespace=\"${NAMESPACE}\",version=\"${IMAGE_TAG}\"}[1m])) or vector(0)), 0.001))*100)")"
P95_LATENCY_SECONDS="$(q "(histogram_quantile(0.95, sum(rate(demo_http_request_duration_seconds_bucket{namespace=\"${NAMESPACE}\",version=\"${IMAGE_TAG}\"}[1m])) by (le)) or on() vector(0))")"

echo "OBS_REQUEST_COUNT_1M=${REQUEST_COUNT_1M}"
echo "OBS_ERROR_RATE_PERCENT=${ERROR_RATE_PERCENT}"
echo "OBS_P95_LATENCY_SECONDS=${P95_LATENCY_SECONDS}"
