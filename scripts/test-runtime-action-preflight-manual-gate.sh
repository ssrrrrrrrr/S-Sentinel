#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-preflight-manual-gate"
RELEASE_ID="runtime-action-pause-preflight-manual-gate-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "===== build degraded PAUSE_ROLLOUT request chain ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="$RELEASE_ID" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-runtime-action-preflight-manual-gate/rollout-runtime-inspect-runtime-action-pause-preflight-manual-gate-smoke.json")
data = json.loads(p.read_text(encoding="utf-8"))

data["rollout"]["phase"] = "Degraded"
data["rollout"]["degraded"] = True
data["rollout"]["readyReplicas"] = 1
data["analysis"]["status"] = "Failed"
data["analysis"]["failed"] = 1
data["pods"]["readyPodCount"] = 1

p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-$RELEASE_ID.json"

RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json"

echo "===== approve request fixture for manual gate ====="
python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-runtime-action-preflight-manual-gate/runtime-action-request-runtime-action-pause-preflight-manual-gate-smoke.json")
data = json.loads(p.read_text(encoding="utf-8"))

data["request"]["requestStatus"] = "READY_FOR_PREFLIGHT"
data["request"]["lifecycleStage"] = "READY_FOR_PREFLIGHT"
data["approval"]["status"] = "APPROVED"
data["approval"]["approved"] = True
data["approval"]["approvalDecision"] = "APPROVED_FOR_LOW_RISK_PAUSE"
data["approval"]["readyToExecute"] = False
data["approval"]["willExecuteAfterApproval"] = False

p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

echo "===== build manual-gated preflight ====="
S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_PAUSE=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-$RELEASE_ID.json"

echo "===== assert manual-gated preflight ====="
python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-pause-preflight-manual-gate-smoke"
doc = json.loads(Path(f".tmp/test-runtime-action-preflight-manual-gate/runtime-action-preflight-{release_id}.json").read_text(encoding="utf-8"))

assert doc["schemaVersion"] == "runtime.action.preflight/v1alpha1", doc
assert doc["runtimeActionPreflightId"] == "rap-" + release_id, doc
assert doc["request"]["requestedAction"] == "PAUSE_ROLLOUT", doc
assert doc["request"]["requestStatus"] == "READY_FOR_PREFLIGHT", doc
assert doc["request"]["lifecycleStage"] == "READY_FOR_PREFLIGHT", doc
assert doc["request"]["approved"] is True, doc
assert doc["request"]["readyToExecute"] is True, doc
assert doc["request"]["willExecute"] is False, doc

assert doc["executionGate"]["globalGateEnabled"] is True, doc
assert doc["executionGate"]["operationGateEnabled"] is True, doc
assert doc["executionGate"]["approvalGateEnabled"] is True, doc
assert doc["executionGate"]["manualPauseGateEnabled"] is True, doc
assert doc["executionGate"]["readyForControlledExecutor"] is True, doc
assert doc["executionGate"]["willExecute"] is False, doc

assert doc["preflight"]["preflightStatus"] == "PREFLIGHT_PASSED", doc
assert doc["preflight"]["eligibilityStatus"] == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR", doc
assert doc["preflight"]["eligibleForExecution"] is True, doc
assert doc["preflight"]["readyToExecute"] is True, doc
assert doc["preflight"]["willExecute"] is False, doc
assert doc["preflight"]["blockingReasons"] == [], doc
assert doc["preflight"]["approvalReasons"] == [], doc

assert doc["guardrails"]["preflightOnly"] is True, doc
assert doc["guardrails"]["readOnly"] is True, doc
assert doc["guardrails"]["willExecute"] is False, doc
assert doc["guardrails"]["doesNotPause"] is True, doc
assert doc["guardrails"]["doesNotModifyKubernetes"] is True, doc

print("PASS runtime action preflight manual gate")
PY
