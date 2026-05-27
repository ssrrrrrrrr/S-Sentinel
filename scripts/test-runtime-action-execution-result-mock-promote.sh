#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-execution-result-mock-promote"
RELEASE_ID="runtime-action-promote-execution-mock-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/fake-bin"

cat > "$TMP_DIR/fake-bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${S_SENTINEL_MOCK_KUBECTL_LOG}"

if [ "$#" -eq 6 ] \
  && [ "$1" = "argo" ] \
  && [ "$2" = "rollouts" ] \
  && [ "$3" = "promote" ] \
  && [ "$4" = "demo-app" ] \
  && [ "$5" = "-n" ] \
  && [ "$6" = "slo-rollout" ]; then
  echo "rollout 'demo-app' promoted"
  exit 0
fi

if [ "$#" -eq 7 ] \
  && [ "$1" = "-n" ] \
  && [ "$2" = "slo-rollout" ] \
  && [ "$3" = "get" ] \
  && [ "$4" = "rollout" ] \
  && [ "$5" = "demo-app" ] \
  && [ "$6" = "-o" ] \
  && [ "$7" = "json" ]; then
  cat <<'JSON'
{
  "metadata": {
    "name": "demo-app",
    "namespace": "slo-rollout"
  },
  "spec": {
    "replicas": 3,
    "paused": false
  },
  "status": {
    "phase": "Healthy",
    "currentStepIndex": 2,
    "replicas": 3,
    "updatedReplicas": 3,
    "readyReplicas": 3,
    "availableReplicas": 3,
    "observedGeneration": 14,
    "conditions": [
      {
        "type": "Healthy",
        "status": "True",
        "reason": "RolloutHealthy"
      },
      {
        "type": "Paused",
        "status": "False",
        "reason": "RolloutPromoted"
      }
    ]
  }
}
JSON
  exit 0
fi

echo "unexpected kubectl args: $*" >&2
exit 2
MOCK
chmod +x "$TMP_DIR/fake-bin/kubectl"

cat > "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "rar-$RELEASE_ID",
  "generatedBy": "test-runtime-action-execution-result-mock-promote.sh",
  "generatedAt": "2026-05-27T08:18:18Z",
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
    "reasons": ["manual_promote_mock_fixture"],
    "summary": "Synthetic mock fixture for controlled promote rollout execution."
  },
  "runtimeSnapshot": {
    "rolloutPhase": "Paused",
    "strategy": "Canary",
    "currentStepIndex": 1,
    "replicas": 3,
    "readyReplicas": 3,
    "availableReplicas": 3,
    "paused": true,
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
doc["approval"]["approvedBy"] = "test-runtime-action-execution-result-mock-promote"
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

PATH="$TMP_DIR/fake-bin:$PATH" \
S_SENTINEL_MOCK_KUBECTL_LOG="$TMP_DIR/kubectl.log" \
S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_PROMOTE=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
S_SENTINEL_RUNTIME_PROMOTE_EXECUTE=true \
RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
  bash scripts/build-runtime-action-execution-result.sh "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

python3 - <<'PYASSERT'
import json
from pathlib import Path

release_id = "runtime-action-promote-execution-mock-smoke"
doc = json.loads(Path(f".tmp/test-runtime-action-execution-result-mock-promote/runtime-action-execution-result-{release_id}.json").read_text(encoding="utf-8"))

assert doc["action"]["requestedAction"] == "PROMOTE_ROLLOUT", doc
assert doc["action"]["supportedAction"] is True, doc
assert doc["action"]["implementedAction"] is True, doc
assert doc["action"]["actionStatus"] == "EXECUTION_SUCCEEDED", doc
assert doc["action"]["commandWillExecute"] is True, doc
assert doc["action"]["commandExitCode"] == 0, doc
assert doc["action"]["commandMode"] == "kubectl_argo_rollouts_promote", doc
assert doc["action"]["commandPreviewArgs"] == ["kubectl", "argo", "rollouts", "promote", "demo-app", "-n", "slo-rollout"], doc
assert "promoted" in doc["action"]["commandStdout"], doc

assert doc["writeGate"]["preflightPassed"] is True, doc
assert doc["writeGate"]["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_PROMOTE", doc
assert doc["writeGate"]["operationGateEnabled"] is True, doc
assert doc["writeGate"]["approvalGateEnabled"] is True, doc
assert doc["writeGate"]["finalExecuteEnv"] == "S_SENTINEL_RUNTIME_PROMOTE_EXECUTE", doc
assert doc["writeGate"]["finalExecuteEnabled"] is True, doc
assert doc["writeGate"]["writeAllowed"] is True, doc
assert doc["writeGate"]["willExecute"] is True, doc

assert doc["afterSnapshot"]["observationMode"] == "live_readonly_rollout_get_after_action", doc
assert doc["afterSnapshot"]["postActionRolloutGetAttempted"] is True, doc
assert doc["afterSnapshot"]["postActionRolloutGetSucceeded"] is True, doc
assert doc["afterSnapshot"]["phase"] == "Healthy", doc
assert doc["afterSnapshot"]["currentStepIndex"] == 2, doc
assert doc["afterSnapshot"]["degraded"] is False, doc

verification = doc["postActionVerification"]
assert verification["verificationStatus"] == "VERIFIED", doc
assert verification["requestedAction"] == "PROMOTE_ROLLOUT", doc
assert verification["commandSucceeded"] is True, doc
assert verification["postActionObserved"] is True, doc
assert verification["desiredStateObserved"] is True, doc
assert verification["promoteVerified"] is True, doc
assert verification["promoteStepAdvanced"] is True, doc
assert verification["promotePhaseObserved"] is True, doc
assert verification["blockingReasons"] == [], doc

assert doc["result"]["executionStatus"] == "SUCCEEDED", doc
assert doc["result"]["verificationStatus"] == "VERIFIED", doc
assert doc["result"]["promoteVerified"] is True, doc
assert doc["result"]["didPromote"] is True, doc
assert doc["result"]["didPause"] is False, doc
assert doc["result"]["didResume"] is False, doc
assert doc["result"]["attemptedKubernetesMutation"] is True, doc
assert doc["result"]["mutatedKubernetes"] is True, doc
assert doc["result"]["mutatedGitOps"] is False, doc
assert doc["result"]["willExecute"] is True, doc

assert doc["receipt"]["didPromote"] is True, doc
assert doc["receipt"]["promoteVerified"] is True, doc
assert doc["receipt"]["attemptedModifyKubernetes"] is True, doc
assert doc["receipt"]["didModifyKubernetes"] is True, doc
assert doc["receipt"]["didModifyGitOps"] is False, doc

assert doc["guardrails"]["willExecute"] is True, doc
assert doc["guardrails"]["postActionVerified"] is True, doc
assert doc["guardrails"]["doesNotPromote"] is False, doc
assert doc["guardrails"]["doesNotModifyKubernetes"] is False, doc
assert doc["guardrails"]["doesNotModifyGitOps"] is True, doc
assert doc["guardrails"]["doesNotCommitOrPush"] is True, doc

log = Path(".tmp/test-runtime-action-execution-result-mock-promote/kubectl.log").read_text(encoding="utf-8")
assert "argo rollouts promote demo-app -n slo-rollout" in log, log
assert "-n slo-rollout get rollout demo-app -o json" in log, log

print("PASS runtime action execution result mock promote")
PYASSERT
