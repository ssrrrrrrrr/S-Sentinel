#!/usr/bin/env bash
set -euo pipefail

TMP_DIR=".tmp/test-runtime-action-execution-result-promote-contract"
RELEASE_ID="runtime-action-promote-execution-contract-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-$RELEASE_ID",
  "generatedBy": "test-runtime-action-execution-result-promote-contract.sh",
  "generatedAt": "2026-05-27T07:09:09Z",
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
    "riskLevel": "medium",
    "confidence": "medium",
    "approvalRequired": false,
    "reasons": ["manual_promote_contract_fixture"],
    "summary": "Synthetic contract fixture for promote rollout execution result."
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

RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-$RELEASE_ID.json"

RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-execution-result.sh "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

python3 - "$TMP_DIR/runtime-action-execution-result-$RELEASE_ID.json" <<'PY'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))

assert doc["action"]["requestedAction"] == "PROMOTE_ROLLOUT", doc
assert doc["action"]["supportedAction"] is True, doc
assert doc["action"]["implementedAction"] is True, doc
assert doc["action"]["actionStatus"] == "BLOCKED_BY_PREFLIGHT", doc
assert doc["action"]["commandWillExecute"] is False, doc
assert doc["action"]["commandMode"] == "kubectl_argo_rollouts_promote", doc
assert doc["action"]["commandPreviewArgs"] == ["kubectl", "argo", "rollouts", "promote", "demo-app", "-n", "slo-rollout"], doc

write_gate = doc["writeGate"]
assert write_gate["operation"] == "PROMOTE_ROLLOUT", write_gate
assert write_gate["writeAllowed"] is False, write_gate
assert write_gate["willExecute"] is False, write_gate

verification = doc["postActionVerification"]
assert verification["requestedAction"] == "PROMOTE_ROLLOUT", verification
assert verification["verificationStatus"] == "NOT_RUN", verification
assert verification["pauseVerified"] is False, verification
assert verification["resumeVerified"] is False, verification
assert verification["desiredStateObserved"] is False, verification

result = doc["result"]
assert result["requestedAction"] == "PROMOTE_ROLLOUT", result
assert result["executionStatus"] == "NOT_EXECUTED", result
assert result["didPause"] is False, result
assert result["didResume"] is False, result
assert result["attemptedKubernetesMutation"] is False, result
assert result["mutatedKubernetes"] is False, result
assert result["mutatedGitOps"] is False, result

guardrails = doc["guardrails"]
assert guardrails["willExecute"] is False, guardrails
assert guardrails["doesNotModifyKubernetes"] is True, guardrails
assert guardrails["doesNotModifyGitOps"] is True, guardrails
assert guardrails["doesNotCommitOrPush"] is True, guardrails

print("PASS runtime action execution result promote contract")
PY
