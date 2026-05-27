#!/usr/bin/env bash
set -euo pipefail

TMP_DIR=".tmp/test-runtime-action-request-promote-contract"
RELEASE_ID="runtime-action-promote-request-contract-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-$RELEASE_ID",
  "generatedBy": "test-runtime-action-request-promote-contract.sh",
  "generatedAt": "2026-05-27T07:07:07Z",
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
    "summary": "Synthetic contract fixture for promote rollout request."
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

python3 - "$TMP_DIR/runtime-action-request-$RELEASE_ID.json" <<'PY'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))

assert doc["request"]["requestedAction"] == "PROMOTE_ROLLOUT", doc
assert doc["request"]["requestStatus"] == "PENDING_APPROVAL", doc
assert doc["request"]["lifecycleStage"] == "WAITING_APPROVAL", doc
assert doc["request"]["approvalRequired"] is True, doc
assert doc["request"]["readyToExecute"] is False, doc
assert doc["request"]["willExecute"] is False, doc

binding = doc["recommendationBinding"]
assert binding["recommendedAction"] == "PROMOTE_ROLLOUT", binding
assert binding["allowedToRequest"] is True, binding
assert binding["blockingReasons"] == [], binding

guardrails = doc["guardrails"]
assert guardrails["requestOnly"] is True, guardrails
assert guardrails["willExecute"] is False, guardrails
assert guardrails["doesNotPromote"] is True, guardrails
assert guardrails["doesNotModifyKubernetes"] is True, guardrails

print("PASS runtime action request promote contract")
PY
