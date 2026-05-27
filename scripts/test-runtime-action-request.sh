#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-request"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "===== build source rollout runtime inspect fixture ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="runtime-action-review-request-smoke" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

echo "===== build review recommendation ====="
RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-runtime-action-review-request-smoke.json"

echo "===== build review request ====="
RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-runtime-action-review-request-smoke.json"

echo "===== create failed runtime inspect fixture ====="
python3 - <<'PY'
import json
from pathlib import Path

src = Path(".tmp/test-runtime-action-request/rollout-runtime-inspect-runtime-action-review-request-smoke.json")
dst = Path(".tmp/test-runtime-action-request/rollout-runtime-inspect-runtime-action-pause-request-smoke.json")
data = json.loads(src.read_text(encoding="utf-8"))

data["rolloutRuntimeInspectId"] = "rti-runtime-action-pause-request-smoke"
data["release"]["releaseId"] = "runtime-action-pause-request-smoke"
data["rollout"]["phase"] = "Degraded"
data["rollout"]["degraded"] = True
data["rollout"]["readyReplicas"] = 1
data["analysis"]["status"] = "Failed"
data["analysis"]["failed"] = 1
data["pods"]["readyPodCount"] = 1

dst.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

echo "===== build pause recommendation ====="
RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-runtime-action-pause-request-smoke.json"

echo "===== build pause request ====="
RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-runtime-action-pause-request-smoke.json"

echo "===== create contract-only resume recommendation ====="
cat > "$TMP_DIR/runtime-action-recommendation-runtime-action-resume-request-smoke.json" <<'JSON'
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-runtime-action-resume-request-smoke",
  "generatedBy": "test-runtime-action-request.sh",
  "release": {
    "releaseId": "runtime-action-resume-request-smoke",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev"
  },
  "target": {
    "cluster": "local-dev",
    "namespace": "slo-rollout",
    "rolloutName": "demo-app",
    "service": "demo-app",
    "env": "dev"
  },
  "recommendation": {
    "recommendationStatus": "ACTION_RECOMMENDED",
    "recommendedAction": "RESUME_ROLLOUT",
    "riskLevel": "medium",
    "confidence": "medium",
    "approvalRequired": true,
    "reasons": ["rollout_paused_resume_requested"],
    "summary": "Contract-only resume action recommendation fixture."
  },
  "runtimeSnapshot": {
    "rolloutPhase": "Paused",
    "analysisStatus": "Unknown",
    "paused": true
  },
  "evidenceRefs": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-runtime-action-resume-request-smoke.json",
    "sourceRolloutRuntimeInspectId": "rti-runtime-action-resume-request-smoke"
  },
  "guardrails": {
    "readOnly": true,
    "recommendationOnly": true,
    "willExecute": false,
    "doesNotModifyKubernetes": true
  }
}
JSON

echo "===== build contract-only resume request ====="
RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-runtime-action-resume-request-smoke.json"

echo "===== assert runtime action requests ====="
python3 - <<'PY'
import json
from pathlib import Path

review = json.loads(Path(".tmp/test-runtime-action-request/runtime-action-request-runtime-action-review-request-smoke.json").read_text())
pause = json.loads(Path(".tmp/test-runtime-action-request/runtime-action-request-runtime-action-pause-request-smoke.json").read_text())
resume = json.loads(Path(".tmp/test-runtime-action-request/runtime-action-request-runtime-action-resume-request-smoke.json").read_text())

assert review["schemaVersion"] == "runtime.action.request/v1alpha1", review
assert review["runtimeActionRequestId"] == "rarq-runtime-action-review-request-smoke", review
assert review["mode"] == "request_only", review
assert review["request"]["requestedBy"] == "test-runtime-controller", review
assert review["request"]["requestedAction"] == "REQUIRE_REVIEW", review
assert review["request"]["requestStatus"] == "REVIEW_REQUIRED", review
assert review["request"]["lifecycleStage"] == "WAITING_REVIEW", review
assert review["request"]["approvalRequired"] is True, review
assert review["request"]["readyToExecute"] is False, review
assert review["request"]["willExecute"] is False, review
assert review["recommendationBinding"]["recommendedAction"] == "REQUIRE_REVIEW", review
assert review["recommendationBinding"]["allowedToRequest"] is True, review
assert review["approval"]["status"] == "NOT_APPROVED", review
assert review["approval"]["readyToExecute"] is False, review
assert review["guardrails"]["requestOnly"] is True, review
assert review["guardrails"]["readOnly"] is True, review
assert review["guardrails"]["willExecute"] is False, review
assert review["guardrails"]["doesNotModifyKubernetes"] is True, review
assert review["guardrails"]["doesNotPause"] is True, review

assert pause["runtimeActionRequestId"] == "rarq-runtime-action-pause-request-smoke", pause
assert pause["request"]["requestedAction"] == "PAUSE_ROLLOUT", pause
assert pause["request"]["requestStatus"] == "PENDING_APPROVAL", pause
assert pause["request"]["lifecycleStage"] == "WAITING_APPROVAL", pause
assert pause["request"]["riskLevel"] == "high", pause
assert pause["request"]["approvalRequired"] is True, pause
assert pause["request"]["readyToExecute"] is False, pause
assert pause["request"]["willExecute"] is False, pause
assert pause["recommendationBinding"]["recommendationStatus"] == "ACTION_RECOMMENDED", pause
assert pause["recommendationBinding"]["recommendedAction"] == "PAUSE_ROLLOUT", pause
assert pause["recommendationBinding"]["allowedToRequest"] is True, pause
assert pause["runtimeSnapshot"]["rolloutPhase"] == "Degraded", pause
assert pause["runtimeSnapshot"]["analysisStatus"] == "Failed", pause
assert pause["evidenceRefs"]["sourceRuntimeActionRecommendationId"] == "rar-runtime-action-pause-request-smoke", pause
assert pause["evidenceRefs"]["sourceRolloutRuntimeInspectId"] == "rti-runtime-action-pause-request-smoke", pause
assert pause["approval"]["status"] == "NOT_APPROVED", pause
assert pause["approval"]["approved"] is False, pause
assert pause["approval"]["readyToExecute"] is False, pause
assert pause["guardrails"]["requestOnly"] is True, pause
assert pause["guardrails"]["willExecute"] is False, pause
assert pause["guardrails"]["doesNotPause"] is True, pause
assert pause["guardrails"]["doesNotModifyKubernetes"] is True, pause

assert resume["runtimeActionRequestId"] == "rarq-runtime-action-resume-request-smoke", resume
assert resume["request"]["requestedAction"] == "RESUME_ROLLOUT", resume
assert resume["request"]["requestStatus"] == "PENDING_APPROVAL", resume
assert resume["request"]["lifecycleStage"] == "WAITING_APPROVAL", resume
assert resume["request"]["riskLevel"] == "medium", resume
assert resume["request"]["approvalRequired"] is True, resume
assert resume["request"]["readyToExecute"] is False, resume
assert resume["request"]["willExecute"] is False, resume
assert resume["recommendationBinding"]["recommendationStatus"] == "ACTION_RECOMMENDED", resume
assert resume["recommendationBinding"]["recommendedAction"] == "RESUME_ROLLOUT", resume
assert resume["recommendationBinding"]["allowedToRequest"] is True, resume
assert resume["runtimeSnapshot"]["rolloutPhase"] == "Paused", resume
assert resume["evidenceRefs"]["sourceRuntimeActionRecommendationId"] == "rar-runtime-action-resume-request-smoke", resume
assert resume["evidenceRefs"]["sourceRolloutRuntimeInspectId"] == "rti-runtime-action-resume-request-smoke", resume
assert resume["approval"]["status"] == "NOT_APPROVED", resume
assert resume["approval"]["approved"] is False, resume
assert resume["approval"]["readyToExecute"] is False, resume
assert resume["guardrails"]["requestOnly"] is True, resume
assert resume["guardrails"]["willExecute"] is False, resume
assert resume["guardrails"]["doesNotPause"] is True, resume
assert resume["guardrails"]["doesNotModifyKubernetes"] is True, resume

print("PASS runtime action request")
PY
