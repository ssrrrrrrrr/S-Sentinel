#!/usr/bin/env bash
set -euo pipefail

TMP_DIR=".tmp/test-runtime-action-execution-result-rollback-target-revision"
RELEASE_ID="runtime-action-rollback-target-revision-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-$RELEASE_ID",
  "generatedBy": "test-runtime-action-execution-result-rollback-target-revision.sh",
  "generatedAt": "2026-05-27T09:33:00Z",
  "mode": "recommendation_only",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "APPROVED",
    "finalAction": "ROLLBACK_ROLLOUT"
  },
  "target": {
    "cluster": "local-dev",
    "namespace": "slo-rollout",
    "rolloutName": "demo-app",
    "service": "demo-app",
    "env": "dev"
  },
  "rollbackTarget": {
    "strategy": "explicit_revision",
    "targetRevision": 3,
    "source": "test_fixture"
  },
  "recommendation": {
    "recommendationStatus": "ACTION_RECOMMENDED",
    "recommendedAction": "ROLLBACK_ROLLOUT",
    "riskLevel": "critical",
    "confidence": "medium",
    "approvalRequired": true,
    "reasons": ["manual_rollback_target_revision_fixture"],
    "summary": "Synthetic fixture for rollback target revision."
  },
  "runtimeSnapshot": {
    "rolloutPhase": "Healthy",
    "strategy": "Canary",
    "currentStepIndex": 1,
    "stableRS": "demo-app-stable",
    "currentPodHash": "demo-app-new",
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
doc["approval"]["approvedBy"] = "test-runtime-action-execution-result-rollback-target-revision"
doc["approval"]["approvalDecision"] = "APPROVED_FOR_HIGH_RISK_ROLLBACK"
doc["approval"]["readyToExecute"] = False
doc["approval"]["willExecuteAfterApproval"] = False
path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PYAPPROVE

S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_ROLLBACK=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-$RELEASE_ID.json"

S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_ROLLBACK=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-execution-result.sh "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

python3 - "$TMP_DIR/runtime-action-request-$RELEASE_ID.json" "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json" "$TMP_DIR/runtime-action-execution-result-$RELEASE_ID.json" <<'PYASSERT'
import json
import sys

request_doc = json.load(open(sys.argv[1], encoding="utf-8"))
preflight_doc = json.load(open(sys.argv[2], encoding="utf-8"))
result_doc = json.load(open(sys.argv[3], encoding="utf-8"))

for doc in [request_doc, preflight_doc, result_doc]:
    target = doc["rollbackTarget"]
    assert target["strategy"] == "explicit_revision", doc
    assert target["targetRevision"] == 3, doc
    assert target["commandArgumentMode"] == "explicit_to_revision", doc
    assert target["usesArgoRolloutsUndo"] is True, doc
    assert target["usesGitOpsRollback"] is False, doc
    assert target["requiresGitOpsWrite"] is False, doc

action = result_doc["action"]
assert action["requestedAction"] == "ROLLBACK_ROLLOUT", result_doc
assert action["supportedAction"] is True, result_doc
assert action["implementedAction"] is True, result_doc
assert action["actionStatus"] == "READY_BUT_NOT_EXECUTED_FINAL_SWITCH_OFF", result_doc
assert action["commandMode"] == "kubectl_argo_rollouts_undo_to_revision", result_doc
assert action["commandPreviewArgs"] == ["kubectl", "argo", "rollouts", "undo", "demo-app", "-n", "slo-rollout", "--to-revision=3"], result_doc
assert result_doc["result"]["didRollback"] is False, result_doc
assert result_doc["guardrails"]["doesNotRollback"] is True, result_doc

print("PASS runtime action execution result rollback target revision")
PYASSERT
