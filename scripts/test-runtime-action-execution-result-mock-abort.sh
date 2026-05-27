#!/usr/bin/env bash
set -euo pipefail

SRC_DIR=".tmp/test-runtime-action-preflight-abort-contract"
TMP_DIR=".tmp/test-runtime-action-execution-result-mock-abort"
SRC_RELEASE_ID="runtime-action-abort-preflight-contract-smoke"
RELEASE_ID="runtime-action-abort-execution-mock-smoke"

rm -rf "$TMP_DIR"
bash scripts/test-runtime-action-preflight-abort-contract.sh >/tmp/s-sentinel-abort-preflight-contract.log

SRC_PREFLIGHT="$SRC_DIR/runtime-action-preflight-${SRC_RELEASE_ID}.json"
DST_PREFLIGHT="$TMP_DIR/runtime-action-preflight-${RELEASE_ID}.json"
OUT="$TMP_DIR/runtime-action-execution-result-${RELEASE_ID}.json"
MOCK_BIN="$TMP_DIR/bin"

mkdir -p "$TMP_DIR" "$MOCK_BIN"
cp "$SRC_PREFLIGHT" "$DST_PREFLIGHT"

python3 - "$DST_PREFLIGHT" "$RELEASE_ID" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
release_id = sys.argv[2]
doc = json.loads(path.read_text(encoding="utf-8"))

def patch(value):
    if isinstance(value, list):
        return [patch(v) for v in value]
    if not isinstance(value, dict):
        if isinstance(value, str):
            return value.replace("runtime-action-abort-preflight-contract-smoke", release_id)
        return value

    out = {}
    for k, v in value.items():
        v = patch(v)

        if k == "releaseId" and isinstance(v, str):
            v = release_id
        if k == "runtimeActionPreflightId":
            v = f"rap-{release_id}"
        if k == "sourceRuntimeActionRequestId":
            v = f"rarq-{release_id}"
        if k == "sourceRolloutRuntimeInspectId":
            v = f"rti-{release_id}"
        if k in {"requestedAction", "recommendedAction", "operation", "finalAction"}:
            v = "ABORT_ROLLOUT"
        if k == "preflightStatus":
            v = "PREFLIGHT_PASSED"
        if k == "preflightPassed":
            v = True
        if k == "eligibilityStatus":
            v = "ELIGIBLE_FOR_CONTROLLED_EXECUTOR"
        if k == "eligibleForExecution":
            v = True
        if k == "readyToExecute":
            v = True
        if k == "willExecute":
            v = False
        if k == "operationGateEnv":
            v = "S_SENTINEL_ALLOW_RUNTIME_ABORT"
        if k == "operationGateEnabled":
            v = True
        if k == "abortGateEnabled":
            v = True
        if k == "approvalGateEnabled":
            v = True
        if k == "manualAbortGateEnabled":
            v = True
        if k == "manualOperationGateEnabled":
            v = True
        if k == "finalExecuteEnv":
            v = "S_SENTINEL_RUNTIME_ABORT_EXECUTE"
        if k == "finalExecuteEnabled":
            v = True
        if k == "policyDecision":
            v = "APPROVED"

        out[k] = v
    return out

doc = patch(doc)

target = doc.setdefault("target", {})
target["namespace"] = "slo-rollout"
target["rolloutName"] = "demo-app"
target["service"] = "demo-app"
target["env"] = "dev"

preflight = doc.setdefault("preflight", {})
preflight["preflightStatus"] = "PREFLIGHT_PASSED"
preflight["preflightPassed"] = True
preflight["eligibilityStatus"] = "ELIGIBLE_FOR_CONTROLLED_EXECUTOR"
preflight["eligibleForExecution"] = True
preflight["readyToExecute"] = True
preflight["willExecute"] = False

snapshot = doc.setdefault("runtimeSnapshot", {})
snapshot["rolloutPhase"] = "Progressing"
snapshot["analysisStatus"] = "Running"
snapshot["currentStepIndex"] = 1
snapshot["paused"] = False
snapshot["degraded"] = False

guardrails = doc.setdefault("guardrails", {})
guardrails["willExecute"] = False
guardrails["doesNotAbort"] = True
guardrails["doesNotRollback"] = True
guardrails["doesNotModifyGitOps"] = True

path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

cat > "$MOCK_BIN/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "argo rollouts abort demo-app -n slo-rollout" ]]; then
  echo "rollout 'demo-app' aborted"
  exit 0
fi

if [[ "$*" == "-n slo-rollout get rollout demo-app -o json" ]]; then
  cat <<'JSON'
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "Rollout",
  "metadata": {
    "name": "demo-app",
    "namespace": "slo-rollout",
    "generation": 61
  },
  "spec": {
    "replicas": 3,
    "paused": false
  },
  "status": {
    "phase": "Degraded",
    "message": "RolloutAborted: Rollout aborted update to revision 61",
    "currentStepIndex": 0,
    "replicas": 3,
    "readyReplicas": 3,
    "availableReplicas": 3,
    "observedGeneration": 61,
    "currentPodHash": "newhash",
    "stableRS": "stablehash"
  }
}
JSON
  exit 0
fi

echo "unexpected kubectl args: $*" >&2
exit 42
MOCK

chmod +x "$MOCK_BIN/kubectl"

PATH="$MOCK_BIN:$PATH" \
S_SENTINEL_RUNTIME_EXECUTION_ENABLED=1 \
S_SENTINEL_ALLOW_RUNTIME_ABORT=1 \
S_SENTINEL_RUNTIME_ACTION_APPROVED=1 \
S_SENTINEL_RUNTIME_ABORT_EXECUTE=1 \
bash scripts/build-runtime-action-execution-result.sh "$DST_PREFLIGHT"

python3 - "$OUT" <<'PY'
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

action = doc["action"]
write_gate = doc["writeGate"]
after_snapshot = doc["afterSnapshot"]
verification = doc["postActionVerification"]
result = doc["result"]
receipt = doc["receipt"]
guardrails = doc["guardrails"]

assert action["requestedAction"] == "ABORT_ROLLOUT", doc
assert action["supportedAction"] is True, doc
assert action["implementedAction"] is True, doc
assert action["actionStatus"] == "EXECUTION_SUCCEEDED", doc
assert action["commandMode"] == "kubectl_argo_rollouts_abort", doc
assert action["commandWillExecute"] is True, doc

assert write_gate["overallGateStatus"] == "EXECUTION_SUCCEEDED", doc
assert write_gate["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_ABORT", doc
assert write_gate["finalExecuteEnv"] == "S_SENTINEL_RUNTIME_ABORT_EXECUTE", doc

assert after_snapshot["postActionRolloutGetSucceeded"] is True, doc
assert after_snapshot["abortedAssumedFromCommandSuccess"] is True, doc
assert after_snapshot["phase"] == "Degraded", doc
assert after_snapshot["aborted"] is True, doc

assert verification["verificationStatus"] == "VERIFIED", doc
assert verification["abortVerified"] is True, doc
assert verification["abortPhaseObserved"] is True, doc
assert verification["observedAborted"] is True, doc

assert result["executionStatus"] == "SUCCEEDED", doc
assert result["didAbort"] is True, doc
assert result["abortVerified"] is True, doc
assert result["attemptedKubernetesMutation"] is True, doc
assert result["mutatedKubernetes"] is True, doc

assert receipt["didAbort"] is True, doc
assert receipt["abortVerified"] is True, doc
assert receipt["didModifyKubernetes"] is True, doc

assert guardrails["postActionVerified"] is True, doc
assert guardrails["doesNotAbort"] is False, doc
assert guardrails["doesNotModifyKubernetes"] is False, doc
assert guardrails["doesNotModifyGitOps"] is True, doc

print("PASS runtime action execution result mock abort")
PY
