#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-preflight"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "===== build review runtime action request ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="runtime-action-review-preflight-smoke" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-runtime-action-review-preflight-smoke.json"

RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-runtime-action-review-preflight-smoke.json"

echo "===== build review preflight ====="
RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-runtime-action-review-preflight-smoke.json"

echo "===== create degraded runtime action request ====="
python3 - <<'PY'
import json
from pathlib import Path

src = Path(".tmp/test-runtime-action-preflight/rollout-runtime-inspect-runtime-action-review-preflight-smoke.json")
dst = Path(".tmp/test-runtime-action-preflight/rollout-runtime-inspect-runtime-action-pause-preflight-smoke.json")
data = json.loads(src.read_text(encoding="utf-8"))

data["rolloutRuntimeInspectId"] = "rti-runtime-action-pause-preflight-smoke"
data["release"]["releaseId"] = "runtime-action-pause-preflight-smoke"
data["rollout"]["phase"] = "Degraded"
data["rollout"]["degraded"] = True
data["rollout"]["readyReplicas"] = 1
data["analysis"]["status"] = "Failed"
data["analysis"]["failed"] = 1
data["pods"]["readyPodCount"] = 1

dst.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-runtime-action-pause-preflight-smoke.json"

RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-runtime-action-pause-preflight-smoke.json"

echo "===== build pause preflight ====="
RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-runtime-action-pause-preflight-smoke.json"

echo "===== assert runtime action preflights ====="
python3 - <<'PY'
import json
from pathlib import Path

review = json.loads(Path(".tmp/test-runtime-action-preflight/runtime-action-preflight-runtime-action-review-preflight-smoke.json").read_text())
pause = json.loads(Path(".tmp/test-runtime-action-preflight/runtime-action-preflight-runtime-action-pause-preflight-smoke.json").read_text())

assert review["schemaVersion"] == "runtime.action.preflight/v1alpha1", review
assert review["runtimeActionPreflightId"] == "rap-runtime-action-review-preflight-smoke", review
assert review["mode"] == "read_only_runtime_action_preflight", review
assert review["sourceRuntimeActionRequestId"] == "rarq-runtime-action-review-preflight-smoke", review
assert review["request"]["requestedAction"] == "REQUIRE_REVIEW", review
assert review["request"]["requestStatus"] == "REVIEW_REQUIRED", review
assert review["preflight"]["preflightStatus"] == "WAITING_REVIEW", review
assert review["preflight"]["eligibilityStatus"] == "NEEDS_REVIEW", review
assert "human_review_required" in review["preflight"]["approvalReasons"], review
assert review["preflight"]["eligibleForExecution"] is False, review
assert review["preflight"]["readyToExecute"] is False, review
assert review["preflight"]["willExecute"] is False, review
assert review["guardrails"]["preflightOnly"] is True, review
assert review["guardrails"]["readOnly"] is True, review
assert review["guardrails"]["willExecute"] is False, review
assert review["guardrails"]["doesNotPause"] is True, review
assert review["guardrails"]["doesNotModifyKubernetes"] is True, review

assert pause["runtimeActionPreflightId"] == "rap-runtime-action-pause-preflight-smoke", pause
assert pause["sourceRuntimeActionRequestId"] == "rarq-runtime-action-pause-preflight-smoke", pause
assert pause["request"]["requestedAction"] == "PAUSE_ROLLOUT", pause
assert pause["request"]["requestStatus"] == "PENDING_APPROVAL", pause
assert pause["preflight"]["preflightStatus"] == "WAITING_APPROVAL", pause
assert pause["preflight"]["eligibilityStatus"] == "NOT_ELIGIBLE", pause
assert "human_approval_required" in pause["preflight"]["approvalReasons"], pause
assert pause["runtimeSnapshot"]["rolloutPhase"] == "Degraded", pause
assert pause["runtimeSnapshot"]["analysisStatus"] == "Failed", pause
assert pause["evidenceRefs"]["sourceRuntimeActionRequestId"] == "rarq-runtime-action-pause-preflight-smoke", pause
assert pause["evidenceRefs"]["sourceRuntimeActionRecommendationId"] == "rar-runtime-action-pause-preflight-smoke", pause
assert pause["evidenceRefs"]["sourceRolloutRuntimeInspectId"] == "rti-runtime-action-pause-preflight-smoke", pause
assert pause["preflight"]["eligibleForExecution"] is False, pause
assert pause["preflight"]["readyToExecute"] is False, pause
assert pause["preflight"]["willExecute"] is False, pause
assert pause["guardrails"]["preflightOnly"] is True, pause
assert pause["guardrails"]["willExecute"] is False, pause
assert pause["guardrails"]["doesNotPause"] is True, pause
assert pause["guardrails"]["doesNotModifyKubernetes"] is True, pause

print("PASS runtime action preflight")
PY
