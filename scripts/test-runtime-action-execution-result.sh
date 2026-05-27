#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-execution-result"
RELEASE_ID="runtime-action-pause-execution-result-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "===== build source rollout runtime inspect fixture ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="$RELEASE_ID" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

echo "===== make fixture degraded for PAUSE_ROLLOUT recommendation ====="
python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-runtime-action-execution-result/rollout-runtime-inspect-runtime-action-pause-execution-result-smoke.json")
data = json.loads(p.read_text(encoding="utf-8"))

data["rollout"]["phase"] = "Degraded"
data["rollout"]["degraded"] = True
data["rollout"]["readyReplicas"] = 1
data["analysis"]["status"] = "Failed"
data["analysis"]["failed"] = 1
data["pods"]["readyPodCount"] = 1

p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

echo "===== build recommendation/request/preflight chain ====="
RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-$RELEASE_ID.json"

RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json"

RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-$RELEASE_ID.json"

echo "===== build runtime action execution result contract fixture ====="
RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-execution-result.sh "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

echo "===== assert runtime action execution result ====="
python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-pause-execution-result-smoke"
doc = json.loads(Path(f".tmp/test-runtime-action-execution-result/runtime-action-execution-result-{release_id}.json").read_text(encoding="utf-8"))

assert doc["schemaVersion"] == "runtime.action.execution.result/v1alpha1", doc
assert doc["runtimeActionExecutionResultId"] == "raer-" + release_id, doc
assert doc["mode"] == "controlled_runtime_action_result", doc
assert doc["sourceRuntimeActionPreflightId"] == "rap-" + release_id, doc
assert doc["sourceRuntimeActionRequestId"] == "rarq-" + release_id, doc

assert doc["target"]["namespace"] == "slo-rollout", doc
assert doc["target"]["rolloutName"] == "demo-app", doc

assert doc["executor"]["executorName"] == "runtime-pause-executor", doc
assert doc["executor"]["executorType"] == "contract_fixture", doc
assert doc["executor"]["dryRunOnly"] is True, doc
assert doc["executor"]["readOnly"] is True, doc
assert doc["executor"]["willExecute"] is False, doc
assert doc["executor"]["mutatesKubernetes"] is False, doc
assert doc["executor"]["mutatesGitOps"] is False, doc

assert doc["action"]["requestedAction"] == "PAUSE_ROLLOUT", doc
assert doc["action"]["supportedAction"] is True, doc
assert doc["action"]["actionStatus"] == "BLOCKED_BY_PREFLIGHT", doc
assert doc["action"]["commandWillExecute"] is False, doc
assert doc["action"]["commandPreviewArgs"][:4] == ["kubectl", "argo", "rollouts", "pause"], doc

assert doc["writeGate"]["preflightRequired"] is True, doc
assert doc["writeGate"]["preflightStatus"] == "WAITING_APPROVAL", doc
assert doc["writeGate"]["eligibilityStatus"] == "NOT_ELIGIBLE", doc
assert doc["writeGate"]["preflightPassed"] is False, doc
assert doc["writeGate"]["globalGateEnabled"] is False, doc
assert doc["writeGate"]["operationGateEnabled"] is False, doc
assert doc["writeGate"]["operation"] == "PAUSE_ROLLOUT", doc
assert doc["writeGate"]["overallGateStatus"] == "BLOCKED_BY_PREFLIGHT", doc
assert doc["writeGate"]["writeAllowed"] is False, doc
assert doc["writeGate"]["willExecute"] is False, doc

assert doc["beforeSnapshot"]["rolloutPhase"] == "Degraded", doc
assert doc["beforeSnapshot"]["analysisStatus"] == "Failed", doc
assert doc["afterSnapshot"] is None, doc

assert doc["result"]["executionStatus"] == "NOT_EXECUTED", doc
assert doc["result"]["actionStatus"] == "BLOCKED_BY_PREFLIGHT", doc
assert doc["result"]["requestedAction"] == "PAUSE_ROLLOUT", doc
assert doc["result"]["didPause"] is False, doc
assert doc["result"]["didResume"] is False, doc
assert doc["result"]["didPromote"] is False, doc
assert doc["result"]["didAbort"] is False, doc
assert doc["result"]["didRollback"] is False, doc
assert doc["result"]["mutatedKubernetes"] is False, doc
assert doc["result"]["mutatedGitOps"] is False, doc
assert doc["result"]["readyForExecutor"] is False, doc
assert doc["result"]["willExecute"] is False, doc

assert doc["receipt"]["receiptType"] == "runtime_action_execution_result", doc
assert doc["receipt"]["receiptStatus"] == "RECORDED", doc
assert doc["receipt"]["wroteEvidence"] is True, doc
assert doc["receipt"]["didPause"] is False, doc
assert doc["receipt"]["didModifyKubernetes"] is False, doc
assert doc["receipt"]["didModifyGitOps"] is False, doc

assert doc["evidenceRefs"]["sourceRuntimeActionPreflightId"] == "rap-" + release_id, doc
assert doc["evidenceRefs"]["sourceRuntimeActionRequestId"] == "rarq-" + release_id, doc
assert doc["evidenceRefs"]["sourceRuntimeActionRecommendationId"] == "rar-" + release_id, doc
assert doc["evidenceRefs"]["sourceRolloutRuntimeInspectId"] == "rti-" + release_id, doc

assert doc["guardrails"]["contractOnly"] is True, doc
assert doc["guardrails"]["readOnly"] is True, doc
assert doc["guardrails"]["dryRunOnly"] is True, doc
assert doc["guardrails"]["willExecute"] is False, doc
assert doc["guardrails"]["doesNotPause"] is True, doc
assert doc["guardrails"]["doesNotModifyKubernetes"] is True, doc
assert doc["guardrails"]["doesNotModifyGitOps"] is True, doc
assert doc["guardrails"]["doesNotCommitOrPush"] is True, doc

print("PASS runtime action execution result")
PY
