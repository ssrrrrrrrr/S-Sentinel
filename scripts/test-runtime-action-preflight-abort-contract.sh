#!/usr/bin/env bash
set -euo pipefail

TMP_DIR=".tmp/test-runtime-action-preflight-abort-contract"
RELEASE_ID="runtime-action-abort-preflight-contract-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-$RELEASE_ID",
  "generatedBy": "test-runtime-action-preflight-abort-contract.sh",
  "generatedAt": "2026-05-27T07:08:08Z",
  "mode": "recommendation_only",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "APPROVED",
    "finalAction": "ABORT_ROLLOUT"
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
    "recommendedAction": "ABORT_ROLLOUT",
    "riskLevel": "medium",
    "confidence": "medium",
    "approvalRequired": false,
    "reasons": ["manual_abort_contract_fixture"],
    "summary": "Synthetic contract fixture for abort rollout preflight."
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
    "doesNotAbort": true,
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

python3 - "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json" <<'PY'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))

assert doc["request"]["requestedAction"] == "ABORT_ROLLOUT", doc
assert doc["request"]["approvalRequired"] is True, doc
assert doc["request"]["readyToExecute"] is False, doc
assert doc["request"]["willExecute"] is False, doc

preflight = doc["preflight"]
assert preflight["preflightStatus"] == "WAITING_APPROVAL", preflight
assert preflight["eligibilityStatus"] == "NOT_ELIGIBLE", preflight
assert preflight["eligibleForExecution"] is False, preflight
assert preflight["readyToExecute"] is False, preflight
assert preflight["willExecute"] is False, preflight
assert "abort_runtime_action_contract_only" not in preflight["blockingReasons"], preflight
assert "unsupported_runtime_action" not in preflight["blockingReasons"], preflight

checks = {item["name"]: item for item in preflight["checks"]}
assert checks["action_support"]["status"] == "PASS", checks

gate = doc["executionGate"]
assert gate["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_ABORT", gate
assert gate["operationGateEnabled"] is False, gate
assert gate["manualOperationGateEnabled"] is False, gate
assert gate["readyForControlledExecutor"] is False, gate
assert gate["willExecute"] is False, gate

guardrails = doc["guardrails"]
assert guardrails["preflightOnly"] is True, guardrails
assert guardrails["readOnly"] is True, guardrails
assert guardrails["willExecute"] is False, guardrails
assert guardrails["doesNotAbort"] is True, guardrails
assert guardrails["doesNotModifyKubernetes"] is True, guardrails

print("PASS runtime action preflight abort contract")
PY
