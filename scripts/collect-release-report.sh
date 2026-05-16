#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-slo-rollout}"
ROLLOUT_NAME="${ROLLOUT_NAME:-demo-app}"
ARGO_NS="${ARGO_NS:-argocd}"
ARGO_APP="${ARGO_APP:-slo-rollout-demo}"
PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"

TS="$(date +%Y%m%d-%H%M%S)"
OUT="docs/release-reports/release-report-${TS}.md"

mkdir -p docs/release-reports

section() {
  echo "" >> "$OUT"
  echo "## $1" >> "$OUT"
  echo "" >> "$OUT"
}

run_cmd() {
  echo '```bash' >> "$OUT"
  echo "$*" >> "$OUT"
  echo '```' >> "$OUT"
  echo "" >> "$OUT"
  echo '```text' >> "$OUT"
  bash -c "$*" >> "$OUT" 2>&1 || true
  echo '```' >> "$OUT"
  echo "" >> "$OUT"
}

prom_query() {
  local title="$1"
  local query="$2"

  section "$title"

  echo '```promql' >> "$OUT"
  echo "$query" >> "$OUT"
  echo '```' >> "$OUT"
  echo "" >> "$OUT"

  echo '```json' >> "$OUT"
  curl -sG --connect-timeout 2 "${PROM_URL}/api/v1/query" \
    --data-urlencode "query=${query}" >> "$OUT" 2>&1 || echo "Prometheus not reachable at ${PROM_URL}" >> "$OUT"
  echo "" >> "$OUT"
  echo '```' >> "$OUT"
  echo "" >> "$OUT"
}

LATEST_AR="$(kubectl get analysisrun -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -n 1 | awk '{print $1}' || true)"
FAILED_AR="$(kubectl get analysisrun -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | awk '$2=="Failed"{print $1}' | tail -n 1 || true)"
TARGET_AR="${FAILED_AR:-$LATEST_AR}"

ROLLOUT_PHASE="$(kubectl get rollout "$ROLLOUT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
ROLLOUT_ABORT="$(kubectl get rollout "$ROLLOUT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.abort}' 2>/dev/null || true)"
CURRENT_VERSION="$(kubectl get rollout "$ROLLOUT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null || true)"
STABLE_RS="$(kubectl get rollout "$ROLLOUT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.stableRS}' 2>/dev/null || true)"
CURRENT_POD_HASH="$(kubectl get rollout "$ROLLOUT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentPodHash}' 2>/dev/null || true)"
ARGO_REVISION="$(kubectl get application "$ARGO_APP" -n "$ARGO_NS" -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)"
GIT_COMMIT="$(git log -1 --oneline 2>/dev/null || true)"

cat > "$OUT" <<REPORT
# SLO Rollout Release Report

Generated At: ${TS}

## Summary

| Item | Value |
|---|---|
| Namespace | ${NAMESPACE} |
| Rollout | ${ROLLOUT_NAME} |
| Rollout Phase | ${ROLLOUT_PHASE:-unknown} |
| Rollout Abort | ${ROLLOUT_ABORT:-false} |
| Current Desired Version | ${CURRENT_VERSION:-unknown} |
| Stable ReplicaSet | ${STABLE_RS:-unknown} |
| Current Pod Hash | ${CURRENT_POD_HASH:-unknown} |
| Target AnalysisRun | ${TARGET_AR:-none} |
| Argo CD Revision | ${ARGO_REVISION:-unknown} |
| Git Commit | ${GIT_COMMIT:-unknown} |

REPORT

section "Rollout Status"
run_cmd "kubectl get rollout ${ROLLOUT_NAME} -n ${NAMESPACE}"
run_cmd "kubectl describe rollout ${ROLLOUT_NAME} -n ${NAMESPACE}"

section "Pod Version Distribution"
run_cmd "kubectl get pods -n ${NAMESPACE} -L version -o wide"
run_cmd "kubectl get pods -n ${NAMESPACE} -o custom-columns=NAME:.metadata.name,VERSION:.metadata.labels.version,IMAGE:.spec.containers[0].image,STATUS:.status.phase"

section "AnalysisRun List"
run_cmd "kubectl get analysisrun -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp"

if [ -n "${TARGET_AR:-}" ]; then
  section "Target AnalysisRun Detail"
  run_cmd "kubectl describe analysisrun ${TARGET_AR} -n ${NAMESPACE}"
else
  section "Target AnalysisRun Detail"
  echo "No AnalysisRun found." >> "$OUT"
fi

section "Recent Kubernetes Events"
run_cmd "kubectl get events -n ${NAMESPACE} --sort-by=.lastTimestamp | tail -n 50"

section "AnalysisTemplate"
run_cmd "kubectl get analysistemplate -n ${NAMESPACE} -o yaml"

section "Argo CD Application"
run_cmd "kubectl get application ${ARGO_APP} -n ${ARGO_NS} -o yaml"

section "Local Git Status"
run_cmd "git status --short"
run_cmd "git log --oneline -5"

prom_query "Prometheus Request Count by Version and Status - 30m" \
'sum by (version,status) (increase(demo_http_requests_total{namespace="slo-rollout"}[30m]))'

prom_query "Prometheus Error Rate by Version - 30m" \
'(sum by (version) (increase(demo_http_requests_total{namespace="slo-rollout",status=~"5.."}[30m])) / clamp_min(sum by (version) (increase(demo_http_requests_total{namespace="slo-rollout"}[30m])), 1)) * 100'

prom_query "Prometheus P95 Latency by Version - 30m" \
'histogram_quantile(0.95, sum by (version, le) (rate(demo_http_request_duration_seconds_bucket{namespace="slo-rollout"}[5m])))'

echo "Report generated: $OUT"
