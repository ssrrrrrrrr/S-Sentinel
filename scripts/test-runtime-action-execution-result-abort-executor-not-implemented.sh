#!/usr/bin/env bash
set -euo pipefail

SRC_DIR=".tmp/test-runtime-action-preflight-abort-contract"
TMP_DIR=".tmp/test-runtime-action-execution-result-abort-executor-not-implemented"
SRC_RELEASE_ID="runtime-action-abort-preflight-contract-smoke"
RELEASE_ID="runtime-action-abort-executor-not-implemented-smoke"

rm -rf "$TMP_DIR"

bash scripts/test-runtime-action-preflight-abort-contract.sh >/tmp/s-sentinel-abort-preflight-contract.log

SRC_PREFLIGHT="$SRC_DIR/runtime-action-preflight-${SRC_RELEASE_ID}.json"
DST_PREFLIGHT="$TMP_DIR/runtime-action-preflight-${RELEASE_ID}.json"
OUT="$TMP_DIR/runtime-action-execution-result-${RELEASE_ID}.json"

mkdir -p "$TMP_DIR"
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

        if k in {
            "releaseId",
        } and isinstance(v, str):
            v = release_id

        if k in {
            "runtimeActionPreflightId",
        }:
            v = f"rap-{release_id}"

        if k in {
            "sourceRuntimeActionRequestId",
        }:
            v = f"rarq-{release_id}"

        if k in {
            "sourceRolloutRuntimeInspectId",
        }:
            v = f"rti-{release_id}"

        if k in {"requestedAction", "recommendedAction", "operation", "finalAction"}:
            v = "ABORT_ROLLOUT"

        if k == "preflightStatus":
            v = "PREFLIGHT_PASSED"

        if k == "preflightPassed":
            v = True

        if k == "eligibilityStatus":
            v = "ELIGIBLE_FOR_CONTROLLED_EXECUTOR"

        if k == "readyToExecute":
            v = True

        if k == "eligibleForExecution":
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

doc.setdefault("target", {})
doc["target"]["namespace"] = "slo-rollout"
doc["target"]["rolloutName"] = "demo-app"
doc["target"]["service"] = "demo-app"
doc["target"]["env"] = "dev"

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
snapshot["paused"] = False
snapshot["degraded"] = False

guardrails = doc.setdefault("guardrails", {})
guardrails["willExecute"] = False
guardrails["doesNotAbort"] = True
guardrails["doesNotRollback"] = True
guardrails["doesNotModifyGitOps"] = True

path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

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
result = doc["result"]
receipt = doc["receipt"]
guardrails = doc["guardrails"]
write_gate = doc["writeGate"]

assert action["requestedAction"] == "ABORT_ROLLOUT", doc
assert action["supportedAction"] is True, doc
assert action["implementedAction"] is False, doc
assert action["actionStatus"] == "BLOCKED_EXECUTOR_NOT_IMPLEMENTED", doc
assert action["commandMode"] == "kubectl_argo_rollouts_abort", doc
assert action["commandPreviewArgs"] == [
    "kubectl", "argo", "rollouts", "abort", "demo-app", "-n", "slo-rollout"
], doc
assert action["commandWillExecute"] is False, doc

assert write_gate["preflightStatus"] == "PREFLIGHT_PASSED", doc
assert write_gate["eligibilityStatus"] == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR", doc
assert write_gate["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_ABORT", doc
assert write_gate["operationGateEnabled"] is True, doc
assert write_gate["finalExecuteEnv"] == "S_SENTINEL_RUNTIME_ABORT_EXECUTE", doc
assert write_gate["finalExecuteEnabled"] is True, doc

assert result["executionStatus"] == "NOT_EXECUTED", doc
assert result["didAbort"] is False, doc
assert result["attemptedKubernetesMutation"] is False, doc
assert result["mutatedKubernetes"] is False, doc

assert receipt["didAbort"] is False, doc
assert receipt["didModifyKubernetes"] is False, doc

assert guardrails["doesNotAbort"] is True, doc
assert guardrails["doesNotModifyKubernetes"] is True, doc

print("PASS runtime action execution result abort executor not implemented")
PY
