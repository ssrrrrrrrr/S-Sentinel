#!/bin/bash
set -euo pipefail

if [ $# -ne 4 ]; then
  echo "Usage: $0 <image_tag> <app_version> <fault_rate> <latency_ms>"
  echo "Example healthy: $0 v1-actions v1 0 0"
  echo "Example bad:     $0 v2-actions-bad v2 0.8 800"
  exit 1
fi

IMAGE_TAG="$1"
APP_VERSION="$2"
FAULT_RATE="$3"
LATENCY_MS="$4"

SLO_ERROR_RATE_THRESHOLD="${SLO_ERROR_RATE_THRESHOLD:-5}"
SLO_P95_SECONDS_THRESHOLD="${SLO_P95_SECONDS_THRESHOLD:-0.3}"
SLO_MIN_REQUEST_COUNT="${SLO_MIN_REQUEST_COUNT:-20}"

REGISTRY="192.168.30.11:30500"
IMAGE_NAME="sre/demo-app"
NAMESPACE="slo-rollout"
ROLLOUT_NAME="demo-app"

ROOT_DIR="$(git rev-parse --show-toplevel)"
APP_DIR="${ROOT_DIR}/demo-app"
DEPLOY_DIR="${ROOT_DIR}/deploy"
BASE_DIR="${ROOT_DIR}/deploy/base"

LOCAL_IMAGE="docker.io/library/demo-app:${IMAGE_TAG}"
REMOTE_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
TAR_FILE="demo-app-${IMAGE_TAG}.tar"

echo "========== GitOps Release Info =========="
echo "IMAGE_TAG:    ${IMAGE_TAG}"
echo "APP_VERSION:  ${APP_VERSION}"
echo "FAULT_RATE:   ${FAULT_RATE}"
echo "LATENCY_MS:   ${LATENCY_MS}"
echo "SLO_ERROR_RATE_THRESHOLD: ${SLO_ERROR_RATE_THRESHOLD}"
echo "SLO_P95_SECONDS_THRESHOLD: ${SLO_P95_SECONDS_THRESHOLD}"
echo "SLO_MIN_REQUEST_COUNT: ${SLO_MIN_REQUEST_COUNT}"
echo "REMOTE_IMAGE: ${REMOTE_IMAGE}"
echo "BASE_DIR:     ${BASE_DIR}"
echo "========================================="

cd "${APP_DIR}"

echo "[1/7] Prepare Go build cache..."
export HOME="${HOME:-/tmp/slo-runner-home}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/slo-runner-cache}"
export GOCACHE="${GOCACHE:-/tmp/slo-go-build-cache}"
export GOMODCACHE="${GOMODCACHE:-/tmp/slo-go-mod-cache}"

mkdir -p "$HOME" "$XDG_CACHE_HOME" "$GOCACHE" "$GOMODCACHE"

echo "[2/7] Build Go binary..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o demo-app main.go

echo "[2/7] Build image tar..."
python3 build-image.py "${IMAGE_TAG}" "${APP_VERSION}" "${FAULT_RATE}" "${LATENCY_MS}"

echo "[3/7] Import image into containerd..."
ctr -n k8s.io images import "${TAR_FILE}"

echo "[4/7] Tag and push image to private registry..."
ctr -n k8s.io images tag --force "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"
ctr -n k8s.io images push --plain-http "${REMOTE_IMAGE}"

echo "[5/7] Render GitOps manifests into deploy/base..."

cat > "${BASE_DIR}/analysis.yaml" <<EOF_ANALYSIS
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: demo-app-error-rate
  namespace: ${NAMESPACE}
spec:
  metrics:
  - name: request-count
    interval: 20s
    count: 3
    failureLimit: 1
    successCondition: result[0] >= ${SLO_MIN_REQUEST_COUNT}
    provider:
      prometheus:
        address: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090
        query: |
          (
            sum(increase(demo_http_requests_total{namespace="${NAMESPACE}",version="${IMAGE_TAG}"}[1m]))
            or on() vector(0)
          )

  - name: error-rate
    interval: 20s
    count: 3
    failureLimit: 1
    successCondition: result[0] < ${SLO_ERROR_RATE_THRESHOLD}
    provider:
      prometheus:
        address: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090
        query: |
          (
            (
              sum(rate(demo_http_requests_total{namespace="${NAMESPACE}",version="${IMAGE_TAG}",status=~"5.."}[1m]))
              or vector(0)
            )
            /
            clamp_min(
              (
                sum(rate(demo_http_requests_total{namespace="${NAMESPACE}",version="${IMAGE_TAG}"}[1m]))
                or vector(0)
              ),
              0.001
            )
          ) * 100

  - name: p95-latency
    interval: 20s
    count: 3
    failureLimit: 1
    successCondition: isNaN(result[0]) || result[0] < ${SLO_P95_SECONDS_THRESHOLD}
    provider:
      prometheus:
        address: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090
        query: |
          (
            histogram_quantile(
              0.95,
              sum(rate(demo_http_request_duration_seconds_bucket{namespace="${NAMESPACE}",version="${IMAGE_TAG}"}[1m])) by (le)
            )
            or on() vector(0)
          )
EOF_ANALYSIS

cat > "${BASE_DIR}/rollout.yaml" <<EOF_ROLLOUT
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: ${ROLLOUT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: demo-app
spec:
  replicas: 3
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
        version: ${IMAGE_TAG}
    spec:
      containers:
      - name: demo-app
        image: ${REMOTE_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: VERSION
          value: "${APP_VERSION}"
        - name: RELEASE_TAG
          value: "${IMAGE_TAG}"
        - name: FAULT_RATE
          value: "${FAULT_RATE}"
        - name: LATENCY_MS
          value: "${LATENCY_MS}"
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 3
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause:
          duration: 30s
      - analysis:
          templates:
          - templateName: demo-app-error-rate
      - setWeight: 50
      - pause:
          duration: 30s
      - analysis:
          templates:
          - templateName: demo-app-error-rate
      - setWeight: 100
EOF_ROLLOUT

cd "${ROOT_DIR}"

echo "[6/7] Validate kustomize render..."
kubectl kustomize "${DEPLOY_DIR}" >/tmp/slo-rollout-rendered.yaml
grep -q "name: request-count" /tmp/slo-rollout-rendered.yaml
grep -q "version=\"${IMAGE_TAG}\"" /tmp/slo-rollout-rendered.yaml
echo "Kustomize render OK."

echo "[7/7] Commit and push GitOps changes..."

echo "===== Generate ChangeContext ====="
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

CHANGE_CONTEXT_OUTPUT_DIR="${CHANGE_CONTEXT_OUTPUT_DIR:-docs/release-reports}"
if [ -d /data/nfs/slo-rollout-watcher/reports ] && [ -z "${CHANGE_CONTEXT_OUTPUT_DIR_OVERRIDE:-}" ]; then
  CHANGE_CONTEXT_OUTPUT_DIR="/data/nfs/slo-rollout-watcher/reports"
fi

BASE_REF="${CHANGE_CONTEXT_BASE_REF:-HEAD}" \
OUTPUT_DIR="$CHANGE_CONTEXT_OUTPUT_DIR" \
APP_NAME="demo-app" \
NAMESPACE="slo-rollout" \
./scripts/generate-change-context.sh || {
  echo "WARN: generate-change-context.sh failed, continue release"
}

echo "ChangeContext output dir: $CHANGE_CONTEXT_OUTPUT_DIR"
# Derive real release result from Rollout phase
ROLLOUT_PHASE="$(kubectl -n "$NAMESPACE" get rollout "$ROLLOUT_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [ -z "$ROLLOUT_PHASE" ]; then
  RELEASE_RESULT="IN_PROGRESS"
  RELEASE_REASON="Rollout phase not available yet"
elif [ "$ROLLOUT_PHASE" = "Healthy" ]; then
  RELEASE_RESULT="PASS"
  RELEASE_REASON="Rollout is Healthy"
elif [ "$ROLLOUT_PHASE" = "Degraded" ]; then
  RELEASE_RESULT="FAIL"
  RELEASE_REASON="Rollout is Degraded"
elif [ "$ROLLOUT_PHASE" = "Paused" ]; then
  RELEASE_RESULT="IN_PROGRESS"
  RELEASE_REASON="Rollout is Paused"
else
  RELEASE_RESULT="IN_PROGRESS"
  RELEASE_REASON="Rollout phase: ${ROLLOUT_PHASE}"
fi

echo "Rollout phase: ${ROLLOUT_PHASE:-unknown}, mapped result: ${RELEASE_RESULT}"
echo "DEBUG report inputs: RELEASE_RESULT=${RELEASE_RESULT}, RELEASE_REASON=${RELEASE_REASON}"
export RELEASE_RESULT RELEASE_REASON

METRICS_ENV="$(IMAGE_TAG="$IMAGE_TAG" NAMESPACE="$NAMESPACE" ./scripts/collect-release-metrics.sh || true)"
eval "$METRICS_ENV"
echo "Observed: req_1m=${OBS_REQUEST_COUNT_1M:-unknown}, err_rate=${OBS_ERROR_RATE_PERCENT:-unknown}, p95=${OBS_P95_LATENCY_SECONDS:-unknown}"
IMAGE_TAG="$IMAGE_TAG" \
APP_VERSION="$APP_VERSION" \
NAMESPACE="$NAMESPACE" \
ROLLOUT_NAME="$ROLLOUT_NAME" \
SLO_ERROR_RATE_THRESHOLD="$SLO_ERROR_RATE_THRESHOLD" \
SLO_P95_SECONDS_THRESHOLD="$SLO_P95_SECONDS_THRESHOLD" \
SLO_MIN_REQUEST_COUNT="$SLO_MIN_REQUEST_COUNT" \
  OBS_REQUEST_COUNT_1M="${OBS_REQUEST_COUNT_1M:-unknown}" \
  OBS_ERROR_RATE_PERCENT="${OBS_ERROR_RATE_PERCENT:-unknown}" \
  OBS_P95_LATENCY_SECONDS="${OBS_P95_LATENCY_SECONDS:-unknown}" \
OUTPUT_DIR="$CHANGE_CONTEXT_OUTPUT_DIR" \
./scripts/write-release-report.sh || {
  echo "WARN: write-release-report.sh failed, continue release"
}

git add "${BASE_DIR}/analysis.yaml" "${BASE_DIR}/rollout.yaml"
if [ -d "${CHANGE_CONTEXT_OUTPUT_DIR}" ]; then
  git add -f "${CHANGE_CONTEXT_OUTPUT_DIR}"/*.md 2>/dev/null || true
fi

if git diff --cached --quiet; then
  echo "No GitOps changes to commit."
else
  git config user.name "sre-demo"
  git config user.email "sre-demo@example.com"
  git commit -m "release: ${IMAGE_TAG}"
  git push origin main
fi

echo "Release GitOps update finished."
