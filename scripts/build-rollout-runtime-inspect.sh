#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-docs/release-reports}"
mkdir -p "$OUTPUT_DIR"

MODE="${S_SENTINEL_ROLLOUT_INSPECT_MODE:-fixture}"
RELEASE_ID="${S_SENTINEL_RELEASE_ID:-runtime-inspect-smoke}"
SERVICE="${S_SENTINEL_SERVICE:-demo-app}"
ENVIRONMENT="${S_SENTINEL_ENV:-dev}"
NAMESPACE="${S_SENTINEL_NAMESPACE:-slo-rollout}"
ROLLOUT_NAME="${S_SENTINEL_ROLLOUT_NAME:-demo-app}"
CLUSTER_CONTEXT="${S_SENTINEL_CLUSTER_CONTEXT:-local-dev}"

if [ "$MODE" != "fixture" ] && [ "$MODE" != "live-readonly" ]; then
  echo "ERROR: unsupported S_SENTINEL_ROLLOUT_INSPECT_MODE=$MODE" >&2
  echo "Supported modes: fixture, live-readonly" >&2
  exit 1
fi

ROLLOUT_JSON=""
ANALYSIS_JSON=""
PODS_JSON=""

if [ "$MODE" = "live-readonly" ]; then
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is required for live-readonly rollout inspect" >&2
    exit 1
  fi

  CLUSTER_CONTEXT="${S_SENTINEL_CLUSTER_CONTEXT:-$(kubectl config current-context 2>/dev/null || echo local-dev)}"

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  ROLLOUT_JSON="$TMP_DIR/rollout.json"
  ANALYSIS_JSON="$TMP_DIR/analysisruns.json"
  PODS_JSON="$TMP_DIR/pods.json"

  kubectl -n "$NAMESPACE" get rollout "$ROLLOUT_NAME" -o json > "$ROLLOUT_JSON"
  kubectl -n "$NAMESPACE" get analysisrun -o json > "$ANALYSIS_JSON" 2>/dev/null || printf '{"items":[]}\n' > "$ANALYSIS_JSON"
  kubectl -n "$NAMESPACE" get pods -l "app=$SERVICE" -o json > "$PODS_JSON" 2>/dev/null || printf '{"items":[]}\n' > "$PODS_JSON"
fi

python3 - \
  "$OUTPUT_DIR" \
  "$RELEASE_ID" \
  "$SERVICE" \
  "$ENVIRONMENT" \
  "$NAMESPACE" \
  "$ROLLOUT_NAME" \
  "$MODE" \
  "$CLUSTER_CONTEXT" \
  "$ROLLOUT_JSON" \
  "$ANALYSIS_JSON" \
  "$PODS_JSON" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

output_dir = Path(sys.argv[1])
release_id = sys.argv[2]
service = sys.argv[3]
env = sys.argv[4]
namespace = sys.argv[5]
rollout_name = sys.argv[6]
mode = sys.argv[7]
cluster_context = sys.argv[8]
rollout_json = sys.argv[9]
analysis_json = sys.argv[10]
pods_json = sys.argv[11]

generated_at = datetime.now(timezone.utc).isoformat()

def read_json(path):
    if not path:
        return {}
    return json.loads(Path(path).read_text(encoding="utf-8"))

def condition_status(conditions, condition_type):
    for item in conditions or []:
        if item.get("type") == condition_type:
            return item.get("status"), item.get("reason"), item.get("message")
    return None, None, None

def infer_strategy(spec):
    strategy = spec.get("strategy") or {}
    if "canary" in strategy:
        return "Canary"
    if "blueGreen" in strategy:
        return "BlueGreen"
    return "Unknown"

def latest_analysis_for_rollout(items):
    matched = []
    for item in items:
        meta = item.get("metadata") or {}
        labels = meta.get("labels") or {}
        owners = meta.get("ownerReferences") or []
        owned_by_rollout = any(owner.get("kind") == "Rollout" and owner.get("name") == rollout_name for owner in owners)
        labeled_for_service = labels.get("app") == service
        if owned_by_rollout or labeled_for_service:
            matched.append(item)

    matched.sort(key=lambda x: (x.get("metadata") or {}).get("creationTimestamp") or "")
    return matched[-1] if matched else None

def pod_ready(pod):
    statuses = ((pod.get("status") or {}).get("containerStatuses") or [])
    return bool(statuses) and all(s.get("ready") is True for s in statuses)

if mode == "fixture":
    doc = {
        "schemaVersion": "runtime.rollout.inspect/v1alpha1",
        "rolloutRuntimeInspectId": "rti-" + release_id,
        "generatedBy": "build-rollout-runtime-inspect.sh",
        "generatedAt": generated_at,
        "mode": "fixture_rollout_runtime_inspect",
        "release": {
            "releaseId": release_id,
            "service": service,
            "env": env,
            "namespace": namespace,
            "policyDecision": "REQUIRE_HUMAN_APPROVAL",
            "finalAction": "STOP_PROMOTION",
        },
        "target": {
            "cluster": cluster_context,
            "namespace": namespace,
            "rolloutName": rollout_name,
            "service": service,
            "env": env,
        },
        "rollout": {
            "name": rollout_name,
            "namespace": namespace,
            "phase": "Progressing",
            "strategy": "Canary",
            "currentStepIndex": 2,
            "replicas": 3,
            "updatedReplicas": 1,
            "readyReplicas": 3,
            "availableReplicas": 3,
            "desiredWeight": 20,
            "actualWeight": 20,
            "paused": False,
            "specPaused": False,
            "statusPaused": False,
            "pauseConditions": [],
            "degraded": False,
            "message": "Fixture rollout inspect snapshot; no Kubernetes command executed.",
        },
        "analysis": {
            "analysisRunName": "demo-app-analysis-" + release_id,
            "status": "Running",
            "successful": 0,
            "failed": 0,
            "inconclusive": 0,
        },
        "pods": {
            "selector": "app=" + service,
            "podCount": 3,
            "readyPodCount": 3,
            "runningPodCount": 3,
        },
        "guardrails": {
            "readOnly": True,
            "dryRunOnly": True,
            "willExecute": False,
            "doesNotPause": True,
            "doesNotResume": True,
            "doesNotPromote": True,
            "doesNotAbort": True,
            "doesNotRollback": True,
            "doesNotModifyKubernetes": True,
        },
    }
else:
    rollout_obj = read_json(rollout_json)
    analysis_obj = read_json(analysis_json)
    pods_obj = read_json(pods_json)

    meta = rollout_obj.get("metadata") or {}
    spec = rollout_obj.get("spec") or {}
    status = rollout_obj.get("status") or {}
    conditions = status.get("conditions") or []

    paused_status, paused_reason, paused_message = condition_status(conditions, "Paused")
    healthy_status, healthy_reason, healthy_message = condition_status(conditions, "Healthy")

    latest_analysis = latest_analysis_for_rollout(analysis_obj.get("items") or [])
    analysis_status = latest_analysis.get("status") if latest_analysis else {}
    analysis_meta = latest_analysis.get("metadata") if latest_analysis else {}
    run_summary = analysis_status.get("runSummary") or {}

    pods = pods_obj.get("items") or []
    running_pods = [p for p in pods if (p.get("status") or {}).get("phase") == "Running"]
    ready_pods = [p for p in pods if pod_ready(p)]

    phase = status.get("phase") or "Unknown"
    spec_paused = spec.get("paused") is True
    pause_conditions = status.get("pauseConditions") or []
    status_paused = paused_status == "True" or bool(pause_conditions)
    paused = spec_paused or status_paused
    degraded = phase == "Degraded"

    doc = {
        "schemaVersion": "runtime.rollout.inspect/v1alpha1",
        "rolloutRuntimeInspectId": "rti-" + release_id,
        "generatedBy": "build-rollout-runtime-inspect.sh",
        "generatedAt": generated_at,
        "mode": "live_readonly_rollout_runtime_inspect",
        "release": {
            "releaseId": release_id,
            "service": service,
            "env": env,
            "namespace": namespace,
            "policyDecision": "REQUIRE_HUMAN_APPROVAL",
            "finalAction": "STOP_PROMOTION",
        },
        "target": {
            "cluster": cluster_context,
            "namespace": namespace,
            "rolloutName": rollout_name,
            "service": service,
            "env": env,
        },
        "rollout": {
            "name": meta.get("name") or rollout_name,
            "namespace": meta.get("namespace") or namespace,
            "phase": phase,
            "strategy": infer_strategy(spec),
            "currentStepIndex": status.get("currentStepIndex"),
            "replicas": status.get("replicas") or spec.get("replicas"),
            "updatedReplicas": status.get("updatedReplicas"),
            "readyReplicas": status.get("readyReplicas"),
            "availableReplicas": status.get("availableReplicas"),
            "desiredWeight": None,
            "actualWeight": None,
            "paused": paused,
            "specPaused": spec_paused,
            "statusPaused": status_paused,
            "pauseConditions": pause_conditions,
            "degraded": degraded,
            "currentPodHash": status.get("currentPodHash"),
            "stableRS": status.get("stableRS"),
            "observedGeneration": status.get("observedGeneration"),
            "healthyCondition": {
                "status": healthy_status,
                "reason": healthy_reason,
                "message": healthy_message,
            },
            "pausedCondition": {
                "status": paused_status,
                "reason": paused_reason,
                "message": paused_message,
            },
            "message": "Live read-only rollout inspect snapshot; only kubectl get commands were executed.",
        },
        "analysis": {
            "analysisRunName": analysis_meta.get("name"),
            "status": analysis_status.get("phase") or "NotFound",
            "successful": run_summary.get("successful"),
            "failed": run_summary.get("failed"),
            "inconclusive": run_summary.get("inconclusive"),
        },
        "pods": {
            "selector": "app=" + service,
            "podCount": len(pods),
            "readyPodCount": len(ready_pods),
            "runningPodCount": len(running_pods),
        },
        "guardrails": {
            "readOnly": True,
            "dryRunOnly": True,
            "willExecute": False,
            "doesNotPause": True,
            "doesNotResume": True,
            "doesNotPromote": True,
            "doesNotAbort": True,
            "doesNotRollback": True,
            "doesNotModifyKubernetes": True,
        },
    }

output = output_dir / f"rollout-runtime-inspect-{release_id}.json"
latest = output_dir / "rollout-runtime-inspect-latest.json"

text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
