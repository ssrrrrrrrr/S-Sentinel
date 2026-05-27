#!/usr/bin/env bash
set -euo pipefail

TMP_DIR=".tmp/test-runtime-action-execution-result-promote-executor-not-implemented"
RELEASE_ID="runtime-action-promote-executor-not-implemented-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-$RELEASE_ID",
  "generatedBy": "test-runtime-action-execution-result-promote-executor-not-implemented.sh",
  "generatedAt": "2026-05-27T08:08:08Z",
  "mode": "recommendation_only",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "APPROVED",
    "finalAction": "PROMOTE_ROLLOUT"
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
    "recommendedAction": "PROMOTE_ROLLOUT",
    "riskLevel": "high",
    "confidence": "medium",
    "approvalRequired": true,
    "reasons": ["manual_promote_executor_not_implemented_fixture"],
    "summary": "Synthetic fixture for promote rollout executor-not-implemented gate."
  },
  "runtimeSnapshot": {
    "rolloutPhase": "Healthy",
    "strategy": "Canary",
    "currentStepIndex": 1,
    "replicas": 3,
    "readyReplicas": 3,
    "availableReplicas": 3,
    "paused": false,
    "degraded": false,
    "analysisStatus": "Successful"
  },
  "evidenceRefs": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-$RELEASE_ID.json",
    "sourceRolloutRuntimeInspectId": "rti-$RELEASE_ID"
  },
  "guardrails": {
    "readOnly": true,
    "recommendationOnly": true,
    "willExecute": false,
    "doesNotPause": true,
    "doesNotResume": true,
    "doesNotPromote": true,
    "doesNotAbort": true,
    "doesNotRollback": true,
    "doesNotModifyKubernetes": true,
    "doesNotModifyGitOps": true,
    "doesNotCommitOrPush": true
  }
}
JSON

RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json"

echo "===== approve promote request fixture ====="
python3 - "$TMP_DIR/runtime-action-request-$RELEASE_ID.json" <<'PYAPPROVE'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
doc = json.loads(path.read_text(encoding="utf-8"))

doc["request"]["requestStatus"] = "READY_FOR_PREFLIGHT"
doc["request"]["lifecycleStage"] = "READY_FOR_PREFLIGHT"

doc.setdefault("approval", {})
doc["approval"]["required"] = True
doc["approval"]["status"] = "APPROVED"
doc["approval"]["approved"] = True
doc["approval"]["approvedBy"] = "test-runtime-action-execution-result-promote-executor-not-implemented"
doc["approval"]["approvalDecision"] = "APPROVED_FOR_HIGH_RISK_PROMOTE"
doc["approval"]["readyToExecute"] = False
doc["approval"]["willExecuteAfterApproval"] = False

path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PYAPPROVE

S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_PROMOTE=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-$RELEASE_ID.json"

S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_PROMOTE=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
S_SENTINEL_RUNTIME_PROMOTE_EXECUTE=true \
RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-execution-result.sh "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

python3 - "$TMP_DIR/runtime-action-execution-result-$RELEASE_ID.json" <<'PYASSERT'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))

action = doc["action"]
assert action["requestedAction"] == "PROMOTE_ROLLOUT", doc
assert action["supportedAction"] is True, doc
assert action["implementedAction"] is False, doc
assert action["actionStatus"] == "BLOCKED_EXECUTOR_NOT_IMPLEMENTED", doc
assert action["commandWillExecute"] is False, doc
assert action["commandMode"] == "unsupported_runtime_action_command", doc
assert action["commandPreviewArgs"] == [], doc
assert action["commandExitCode"] is None, doc

write_gate = doc["writeGate"]
assert write_gate["preflightPassed"] is True, write_gate
assert write_gate["globalGateEnabled"] is True, write_gate
assert write_gate["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_PROMOTE", write_gate
assert write_gate["operationGateEnabled"] is True, write_gate
assert write_gate["approvalGateEnabled"] is True, write_gate
assert write_gate["finalExecuteEnv"] == "S_SENTINEL_RUNTIME_PROMOTE_EXECUTE", write_gate
assert write_gate["finalExecuteEnabled"] is True, write_gate
assert write_gate["overallGateStatus"] == "BLOCKED_EXECUTOR_NOT_IMPLEMENTED", write_gate
assert write_gate["writeAllowed"] is False, write_gate
assert write_gate["willExecute"] is False, write_gate

result = doc["result"]
assert result["requestedAction"] == "PROMOTE_ROLLOUT", result
assert result["executionStatus"] == "NOT_EXECUTED", result
assert result["actionStatus"] == "BLOCKED_EXECUTOR_NOT_IMPLEMENTED", result
assert result["readyForExecutor"] is False, result
assert result["willExecute"] is False, result
assert result["didPromote"] is False, result
assert result["didPause"] is False, result
assert result["didResume"] is False, result
assert result["didAbort"] is False, result
assert result["didRollback"] is False, result
assert result["attemptedKubernetesMutation"] is False, result
assert result["mutatedKubernetes"] is False, result
assert result["mutatedGitOps"] is False, result

verification = doc["postActionVerification"]
assert verification["requestedAction"] == "PROMOTE_ROLLOUT", verification
assert verification["verificationStatus"] == "NOT_RUN", verification
assert verification["desiredStateObserved"] is False, verification
assert verification["pauseVerified"] is False, verification
assert verification["resumeVerified"] is False, verification

executor = doc["executor"]
assert executor["dryRunOnly"] is True, executor
assert executor["readOnly"] is True, executor
assert executor["willExecute"] is False, executor
assert executor["mutatesKubernetes"] is False, executor
assert executor["mutatesGitOps"] is False, executor

receipt = doc["receipt"]
assert receipt["attemptedModifyKubernetes"] is False, receipt
assert receipt["didModifyKubernetes"] is False, receipt
assert receipt["didModifyGitOps"] is False, receipt

guardrails = doc["guardrails"]
assert guardrails["willExecute"] is False, guardrails
assert guardrails["doesNotModifyKubernetes"] is True, guardrails
assert guardrails["doesNotModifyGitOps"] is True, guardrails
assert guardrails["doesNotCommitOrPush"] is True, guardrails

print("PASS runtime action execution result promote executor not implemented")
PYASSERT
