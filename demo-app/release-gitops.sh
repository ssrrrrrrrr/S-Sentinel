#!/bin/bash
set -euo pipefail

if [ $# -ne 4 ]; then
  echo "Usage: $0 <IMAGE_TAG> <APP_VERSION> <FAULT_RATE> <LATENCY_MS>"
  echo "Example healthy: $0 v1-gitops v1 0 0"
  echo "Example bad:     $0 v2-gitops-bad v2 0.8 800"
  exit 1
fi

IMAGE_TAG="$1"
APP_VERSION="$2"
FAULT_RATE="$3"
LATENCY_MS="$4"

REGISTRY="192.168.30.11:30500"
IMAGE_NAME="sre/demo-app"
NAMESPACE="slo-rollout"
ROLLOUT_NAME="demo-app"

ROOT_DIR="/root/slo-rollout-demo"
DEPLOY_DIR="${ROOT_DIR}/deploy"

LOCAL_IMAGE="docker.io/library/demo-app:${IMAGE_TAG}"
REMOTE_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
TAR_FILE="demo-app-${IMAGE_TAG}.tar"

echo "========== GitOps Release Info =========="
echo "IMAGE_TAG:   ${IMAGE_TAG}"
echo "APP_VERSION: ${APP_VERSION}"
echo "FAULT_RATE:  ${FAULT_RATE}"
echo "LATENCY_MS:  ${LATENCY_MS}"
echo "REMOTE:      ${REMOTE_IMAGE}"
echo "========================================="

echo "[1/6] Build Go binary..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o demo-app main.go

echo "[2/6] Build image tar..."
python3 build-image.py "${IMAGE_TAG}" "${APP_VERSION}" "${FAULT_RATE}" "${LATENCY_MS}"

echo "[3/6] Import image into containerd..."
ctr -n k8s.io images import "${TAR_FILE}"

echo "[4/6] Tag and push image to private registry..."
ctr -n k8s.io images tag --force "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"
ctr -n k8s.io images push --plain-http "${REMOTE_IMAGE}"

echo "[5/6] Render GitOps manifests..."

cat > "${DEPLOY_DIR}/analysis.yaml" <<YAML
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: demo-app-error-rate
  namespace: ${NAMESPACE}
spec:
  metrics:
    - name: error-rate
      interval: 20s
      count: 3
      failureLimit: 1
      successCondition: result[0] < 5
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
      successCondition: isNaN(result[0]) || result[0] < 0.3
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
YAML

cat > "${DEPLOY_DIR}/rollout.yaml" <<YAML
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
YAML

echo "[6/6] Git commit manifests..."
cd "${ROOT_DIR}"

git add deploy/analysis.yaml deploy/rollout.yaml
git commit -m "release ${IMAGE_TAG}" || echo "No git changes to commit"

echo
echo "GitOps release files updated."
echo
echo "Next step:"
echo "  cd ${ROOT_DIR}"
echo "  kubectl apply -k deploy"
echo
echo "Check:"
echo "  kubectl get rollout -n ${NAMESPACE}"
echo "  kubectl get analysisrun -n ${NAMESPACE}"
echo "  kubectl get pods -n ${NAMESPACE} -L version -o wide"
