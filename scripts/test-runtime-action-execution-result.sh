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

assert doc["executor"]["executorName"] == "runtime-rollout-executor", doc
assert doc["executor"]["executorType"] == "controlled_runtime_executor", doc
assert doc["executor"]["dryRunOnly"] is True, doc
assert doc["executor"]["readOnly"] is True, doc
assert doc["executor"]["willExecute"] is False, doc
assert doc["executor"]["mutatesKubernetes"] is False, doc
assert doc["executor"]["mutatesGitOps"] is False, doc

actor = doc["actorBoundary"]
assert actor["boundaryVersion"] == "runtime.action.actor-boundary/v1alpha1", doc
assert actor["requester"]["sourceRuntimeActionRequestId"] == "rarq-" + release_id, doc
assert actor["requester"]["canApprove"] is False, doc
assert actor["requester"]["canExecute"] is False, doc
assert actor["approval"]["approvalRequired"] is True, doc
assert actor["approval"]["approved"] is False, doc
assert actor["executorIdentity"]["executorName"] == "runtime-rollout-executor", doc
assert actor["executorIdentity"]["runtimeIdentity"] == "local-shell-operator", doc
assert actor["executorIdentity"]["kubernetesIdentity"] == "kubectl-current-context", doc
assert actor["rbacBoundary"]["watcherServiceAccount"] == "release-rollout-watcher", doc
assert actor["rbacBoundary"]["watcherRbacMode"] == "read_only_get_list_watch", doc
assert actor["rbacBoundary"]["watcherCanMutateKubernetes"] is False, doc
assert actor["rbacBoundary"]["executorRequiresKubernetesWrite"] is True, doc
assert actor["rbacBoundary"]["executorWasAllowedToMutateKubernetes"] is False, doc
assert actor["rbacBoundary"]["mutatedKubernetes"] is False, doc
assert actor["rbacBoundary"]["mutatedGitOps"] is False, doc
assert actor["separationOfDuties"]["requesterIsExecutor"] is False, doc
assert actor["separationOfDuties"]["approverIsExecutor"] is False, doc
assert actor["separationOfDuties"]["approvalRequiredBeforeExecution"] is True, doc
assert actor["separationOfDuties"]["approvalGateEnabled"] is False, doc
assert actor["separationOfDuties"]["finalExecuteSwitchRequired"] is True, doc
assert actor["separationOfDuties"]["finalExecuteSwitchEnabled"] is False, doc

recovery = doc["recoveryBoundary"]
assert recovery["boundaryVersion"] == "runtime.action.recovery-boundary/v1alpha1", doc
assert recovery["idempotency"]["idempotencyKey"] == f"{release_id}:PAUSE_ROLLOUT:rap-{release_id}", doc
assert recovery["idempotency"]["correlationId"] == "rap-" + release_id, doc
assert recovery["idempotency"]["duplicatePolicy"] == "same_preflight_same_action_is_duplicate", doc
assert recovery["idempotency"]["samePreflightReexecutionAllowed"] is False, doc
assert recovery["idempotency"]["requiresFreshPreflightForRetry"] is True, doc
assert recovery["retry"]["automaticRetryAllowed"] is False, doc
assert recovery["retry"]["manualRetryAllowed"] is True, doc
assert recovery["retry"]["maxAutomaticAttempts"] == 1, doc
assert recovery["retry"]["currentAttempt"] == 1, doc
assert recovery["retry"]["retryRequiresOperatorReview"] is True, doc
assert recovery["retry"]["retryRequiresFreshEvidence"] is True, doc
assert recovery["failureRecovery"]["executionStatus"] == "NOT_EXECUTED", doc
assert recovery["failureRecovery"]["failureMode"] == "not_executed", doc
assert recovery["failureRecovery"]["recoveryRequired"] is False, doc
assert recovery["failureRecovery"]["recoveryStatus"] == "NO_RECOVERY_REQUIRED", doc
assert recovery["failureRecovery"]["safeToRetryWithoutFreshPreflight"] is False, doc
assert recovery["failureRecovery"]["safeToRetryAfterFreshPreflight"] is True, doc
assert recovery["evidenceWrite"]["receiptStatus"] == "RECORDED", doc
assert recovery["evidenceWrite"]["wroteEvidence"] is True, doc
assert recovery["evidenceWrite"]["commandResultCaptured"] is False, doc
assert recovery["evidenceWrite"]["postActionObservationCaptured"] is False, doc

safety = doc["executionSafetyBoundary"]
assert safety["boundaryVersion"] == "runtime.action.execution-safety-boundary/v1alpha1", doc
assert safety["defaultPolicy"]["defaultOff"] is True, doc
assert safety["defaultPolicy"]["denyByDefault"] is True, doc
assert safety["defaultPolicy"]["requiresFreshPreflight"] is True, doc
assert safety["defaultPolicy"]["requiresExplicitGlobalGate"] is True, doc
assert safety["defaultPolicy"]["requiresExplicitOperationGate"] is True, doc
assert safety["defaultPolicy"]["requiresApprovalGate"] is True, doc
assert safety["defaultPolicy"]["requiresFinalExecuteSwitch"] is True, doc
assert safety["operationRisk"]["requestedAction"] == "PAUSE_ROLLOUT", doc
assert safety["operationRisk"]["riskLevel"] == "medium_high", doc
assert safety["operationRisk"]["highRiskAction"] is False, doc
assert safety["operationRisk"]["runtimeMutatingAction"] is True, doc
assert safety["operationRisk"]["mutatesKubernetesByDesign"] is True, doc
assert safety["operationRisk"]["mutatesGitOpsByDesign"] is False, doc
assert safety["gateMatrix"]["globalGateEnabled"] is False, doc
assert safety["gateMatrix"]["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_PAUSE", doc
assert safety["gateMatrix"]["operationGateEnabled"] is False, doc
assert safety["gateMatrix"]["approvalGateEnabled"] is False, doc
assert safety["gateMatrix"]["finalExecuteEnv"] == "S_SENTINEL_RUNTIME_PAUSE_EXECUTE", doc
assert safety["gateMatrix"]["finalExecuteEnabled"] is False, doc
assert safety["safetyDecision"]["allRuntimeGatesEnabled"] is False, doc
assert safety["safetyDecision"]["directExecutionAllowed"] is False, doc
assert safety["safetyDecision"]["willExecute"] is False, doc
assert safety["safetyDecision"]["defaultOffEnforced"] is True, doc
assert safety["safetyDecision"]["blockedByDefaultOff"] is True, doc
assert "preflight_not_passed" in safety["safetyDecision"]["blockingReasons"], doc
assert "global_runtime_execution_gate_disabled" in safety["safetyDecision"]["blockingReasons"], doc
assert "operation_runtime_gate_disabled" in safety["safetyDecision"]["blockingReasons"], doc
assert "approval_gate_disabled" in safety["safetyDecision"]["blockingReasons"], doc
assert "final_execute_switch_disabled" in safety["safetyDecision"]["blockingReasons"], doc

assert doc["action"]["requestedAction"] == "PAUSE_ROLLOUT", doc
assert doc["action"]["supportedAction"] is True, doc
assert doc["action"]["actionStatus"] == "BLOCKED_BY_PREFLIGHT", doc
assert doc["action"]["commandWillExecute"] is False, doc
assert doc["action"]["commandMode"] == "kubectl_patch_rollout_spec_paused", doc
assert doc["action"]["commandPreviewArgs"][:6] == ["kubectl", "-n", "slo-rollout", "patch", "rollout", "demo-app"], doc

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
assert doc["afterSnapshot"]["observationMode"] == "not_executed", doc
assert doc["afterSnapshot"]["commandExitCode"] is None, doc
assert doc["afterSnapshot"]["pausedAssumedFromCommandSuccess"] is False, doc
assert doc["afterSnapshot"]["postActionRolloutGetAttempted"] is False, doc
assert doc["afterSnapshot"]["postActionRolloutGetSucceeded"] is False, doc

verification = doc["postActionVerification"]
assert verification["verificationType"] == "runtime_action_post_action_verification", doc
assert verification["verificationStatus"] == "NOT_RUN", doc
assert verification["requestedAction"] == "PAUSE_ROLLOUT", doc
assert verification["commandSucceeded"] is False, doc
assert verification["postActionObserved"] is False, doc
assert verification["desiredStateObserved"] is False, doc
assert verification["pauseVerified"] is False, doc
assert verification["expectedPaused"] is True, doc
assert verification["observedPaused"] is False, doc
assert verification["observedSpecPaused"] is False, doc
assert verification["observedStatusPaused"] is False, doc
assert "runtime_action_not_executed" in verification["blockingReasons"], doc
assert verification["warningReasons"] == [], doc

assert doc["result"]["executionStatus"] == "NOT_EXECUTED", doc
assert doc["result"]["actionStatus"] == "BLOCKED_BY_PREFLIGHT", doc
assert doc["result"]["requestedAction"] == "PAUSE_ROLLOUT", doc
assert doc["result"]["verificationStatus"] == "NOT_RUN", doc
assert doc["result"]["pauseVerified"] is False, doc
assert doc["result"]["postActionObserved"] is False, doc
assert doc["result"]["desiredStateObserved"] is False, doc
assert doc["result"]["didPause"] is False, doc
assert doc["result"]["didResume"] is False, doc
assert doc["result"]["didPromote"] is False, doc
assert doc["result"]["didAbort"] is False, doc
assert doc["result"]["didRollback"] is False, doc
assert doc["result"]["attemptedKubernetesMutation"] is False, doc
assert doc["result"]["mutatedKubernetes"] is False, doc
assert doc["result"]["mutatedGitOps"] is False, doc
assert doc["result"]["readyForExecutor"] is False, doc
assert doc["result"]["willExecute"] is False, doc

assert doc["receipt"]["receiptType"] == "runtime_action_execution_result", doc
assert doc["receipt"]["receiptStatus"] == "RECORDED", doc
assert doc["receipt"]["wroteEvidence"] is True, doc
assert doc["receipt"]["didPause"] is False, doc
assert doc["receipt"]["verificationStatus"] == "NOT_RUN", doc
assert doc["receipt"]["pauseVerified"] is False, doc
assert doc["receipt"]["attemptedModifyKubernetes"] is False, doc
assert doc["receipt"]["didModifyKubernetes"] is False, doc
assert doc["receipt"]["didModifyGitOps"] is False, doc

assert doc["evidenceRefs"]["sourceRuntimeActionPreflightId"] == "rap-" + release_id, doc
assert doc["evidenceRefs"]["sourceRuntimeActionRequestId"] == "rarq-" + release_id, doc
assert doc["evidenceRefs"]["sourceRuntimeActionRecommendationId"] == "rar-" + release_id, doc
assert doc["evidenceRefs"]["sourceRolloutRuntimeInspectId"] == "rti-" + release_id, doc

assert doc["guardrails"]["contractOnly"] is False, doc
assert doc["guardrails"]["readOnly"] is True, doc
assert doc["guardrails"]["dryRunOnly"] is True, doc
assert doc["guardrails"]["willExecute"] is False, doc
assert doc["guardrails"]["postActionVerified"] is False, doc
assert doc["guardrails"]["doesNotPause"] is True, doc
assert doc["guardrails"]["doesNotModifyKubernetes"] is True, doc
assert doc["guardrails"]["doesNotModifyGitOps"] is True, doc
assert doc["guardrails"]["doesNotCommitOrPush"] is True, doc

print("PASS runtime action execution result")
PY
