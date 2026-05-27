#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-execution-result-resume-contract"
PREFLIGHT_TMP_DIR=".tmp/test-runtime-action-preflight-resume-manual-gate"
RELEASE_ID="runtime-action-resume-preflight-manual-gate-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "===== build source resume preflight fixture ====="
bash scripts/test-runtime-action-preflight-resume-manual-gate.sh

echo "===== build resume execution result with final switch off ====="
S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_RESUME=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-execution-result.sh "$PREFLIGHT_TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

echo "===== assert resume execution result contract ====="
python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-resume-preflight-manual-gate-smoke"
doc = json.loads(Path(f".tmp/test-runtime-action-execution-result-resume-contract/runtime-action-execution-result-{release_id}.json").read_text(encoding="utf-8"))

assert doc["schemaVersion"] == "runtime.action.execution.result/v1alpha1", doc
assert doc["runtimeActionExecutionResultId"] == "raer-" + release_id, doc
assert doc["sourceRuntimeActionPreflightId"] == "rap-" + release_id, doc
assert doc["sourceRuntimeActionRequestId"] == "rarq-" + release_id, doc

assert doc["action"]["requestedAction"] == "RESUME_ROLLOUT", doc
assert doc["action"]["supportedAction"] is True, doc
assert doc["action"]["actionStatus"] == "READY_BUT_NOT_EXECUTED_FINAL_SWITCH_OFF", doc
assert doc["action"]["commandWillExecute"] is False, doc
assert doc["action"]["commandMode"] == "kubectl_patch_rollout_spec_paused_false", doc
assert doc["action"]["commandPreviewArgs"][:6] == ["kubectl", "-n", "slo-rollout", "patch", "rollout", "demo-app"], doc
assert '{"spec":{"paused":false}}' in doc["action"]["commandPreviewArgs"], doc

assert doc["writeGate"]["preflightRequired"] is True, doc
assert doc["writeGate"]["preflightStatus"] == "PREFLIGHT_PASSED", doc
assert doc["writeGate"]["eligibilityStatus"] == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR", doc
assert doc["writeGate"]["preflightPassed"] is True, doc
assert doc["writeGate"]["globalGateEnabled"] is True, doc
assert doc["writeGate"]["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_RESUME", doc
assert doc["writeGate"]["operationGateEnabled"] is True, doc
assert doc["writeGate"]["resumeGateEnabled"] is True, doc
assert doc["writeGate"]["approvalGateEnabled"] is True, doc
assert doc["writeGate"]["finalExecuteEnv"] == "S_SENTINEL_RUNTIME_RESUME_EXECUTE", doc
assert doc["writeGate"]["finalExecuteEnabled"] is False, doc
assert doc["writeGate"]["operation"] == "RESUME_ROLLOUT", doc
assert doc["writeGate"]["overallGateStatus"] == "READY_BUT_NOT_EXECUTED_FINAL_SWITCH_OFF", doc
assert doc["writeGate"]["writeAllowed"] is False, doc
assert doc["writeGate"]["willExecute"] is False, doc

verification = doc["postActionVerification"]
assert verification["verificationStatus"] == "NOT_RUN", doc
assert verification["requestedAction"] == "RESUME_ROLLOUT", doc
assert verification["commandSucceeded"] is False, doc
assert verification["postActionObserved"] is False, doc
assert verification["desiredStateObserved"] is False, doc
assert verification["pauseVerified"] is False, doc
assert verification["resumeVerified"] is False, doc
assert verification["expectedPaused"] is False, doc
assert "runtime_action_not_executed" in verification["blockingReasons"], doc

assert doc["result"]["executionStatus"] == "NOT_EXECUTED", doc
assert doc["result"]["actionStatus"] == "READY_BUT_NOT_EXECUTED_FINAL_SWITCH_OFF", doc
assert doc["result"]["requestedAction"] == "RESUME_ROLLOUT", doc
assert doc["result"]["verificationStatus"] == "NOT_RUN", doc
assert doc["result"]["pauseVerified"] is False, doc
assert doc["result"]["resumeVerified"] is False, doc
assert doc["result"]["didPause"] is False, doc
assert doc["result"]["didResume"] is False, doc
assert doc["result"]["attemptedKubernetesMutation"] is False, doc
assert doc["result"]["mutatedKubernetes"] is False, doc
assert doc["result"]["willExecute"] is False, doc

assert doc["receipt"]["didPause"] is False, doc
assert doc["receipt"]["didResume"] is False, doc
assert doc["receipt"]["verificationStatus"] == "NOT_RUN", doc
assert doc["receipt"]["pauseVerified"] is False, doc
assert doc["receipt"]["resumeVerified"] is False, doc
assert doc["receipt"]["attemptedModifyKubernetes"] is False, doc
assert doc["receipt"]["didModifyKubernetes"] is False, doc

assert doc["guardrails"]["readOnly"] is True, doc
assert doc["guardrails"]["dryRunOnly"] is True, doc
assert doc["guardrails"]["willExecute"] is False, doc
assert doc["guardrails"]["postActionVerified"] is False, doc
assert doc["guardrails"]["doesNotPause"] is True, doc
assert doc["guardrails"]["doesNotResume"] is True, doc
assert doc["guardrails"]["doesNotModifyKubernetes"] is True, doc

print("PASS runtime action execution result resume contract")
PY
