#!/usr/bin/env bash
set -euo pipefail

TMP_DIR=".tmp/test-runtime-action-preflight-promote-manual-gate"
RELEASE_ID="runtime-action-promote-preflight-manual-gate-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-$RELEASE_ID",
  "generatedBy": "test-runtime-action-preflight-promote-manual-gate.sh",
  "generatedAt": "2026-05-27T07:18:18Z",
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
    "reasons": ["manual_promote_gate_fixture"],
    "summary": "Synthetic manual-gated fixture for promote rollout preflight."
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
doc["approval"]["approvedBy"] = "test-runtime-action-preflight-promote-manual-gate"
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

python3 - "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json" <<'PYASSERT'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))

assert doc["request"]["requestedAction"] == "PROMOTE_ROLLOUT", doc
assert doc["request"]["requestStatus"] == "READY_FOR_PREFLIGHT", doc
assert doc["request"]["lifecycleStage"] == "READY_FOR_PREFLIGHT", doc
assert doc["request"]["approvalRequired"] is True, doc
assert doc["request"]["approved"] is True, doc
assert doc["request"]["readyToExecute"] is True, doc
assert doc["request"]["willExecute"] is False, doc

preflight = doc["preflight"]
assert preflight["preflightStatus"] == "PREFLIGHT_PASSED", preflight
assert preflight["eligibilityStatus"] == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR", preflight
assert preflight["eligibleForExecution"] is True, preflight
assert preflight["readyToExecute"] is True, preflight
assert preflight["willExecute"] is False, preflight
assert preflight["blockingReasons"] == [], preflight
assert preflight["approvalReasons"] == [], preflight

gate = doc["executionGate"]
assert gate["globalGateEnabled"] is True, gate
assert gate["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_PROMOTE", gate
assert gate["operationGateEnabled"] is True, gate
assert gate["promoteGateEnabled"] is True, gate
assert gate["approvalGateEnabled"] is True, gate
assert gate["manualPromoteGateEnabled"] is True, gate
assert gate["manualOperationGateEnabled"] is True, gate
assert gate["readyForControlledExecutor"] is True, gate
assert gate["willExecute"] is False, gate

guardrails = doc["guardrails"]
assert guardrails["preflightOnly"] is True, guardrails
assert guardrails["readOnly"] is True, guardrails
assert guardrails["willExecute"] is False, guardrails
assert guardrails["doesNotPromote"] is True, guardrails
assert guardrails["doesNotModifyKubernetes"] is True, guardrails

print("PASS runtime action preflight promote manual gate")
PYASSERT
