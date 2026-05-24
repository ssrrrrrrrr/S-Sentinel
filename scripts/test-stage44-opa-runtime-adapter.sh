#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-stage44-opa-runtime-adapter-test}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/bin"

AI_DECISION="$TMP_DIR/ai-decision-20260101-000000.json"
POLICY_INPUT="$TMP_DIR/policy-input-opa-20260101-000000.json"
MISSING_RESULT="$TMP_DIR/policy-runtime-result-opa-missing.json"
MISSING_DECISION="$TMP_DIR/policy-decision-opa-missing.json"
EVAL_RESULT="$TMP_DIR/policy-runtime-result-opa-evaluated.json"
EVAL_DECISION="$TMP_DIR/policy-decision-opa-evaluated.json"
FAKE_OPA="$TMP_DIR/bin/opa"

cat > "$AI_DECISION" <<'JSON'
{
  "schemaVersion": "ai.release.advisor/v1alpha1",
  "generatedBy": "test-stage44-opa-runtime-adapter.sh",
  "releaseResult": "PASS",
  "recommendedAction": "NOOP",
  "executionMode": "advisory_only",
  "requiresHumanApproval": false,
  "service": "demo-app",
  "env": "dev",
  "sloId": "demo-app-canary-slo",
  "strategyId": "demo-app-canary-strategy",
  "agentAction": {
    "type": "NOOP",
    "allowed": true,
    "requiresApproval": false
  },
  "guardrails": {
    "autoExecute": false,
    "executionMode": "advisory_only"
  }
}
JSON

echo "===== build opa policy input ====="
./scripts/policy-runtime-adapter.py build-input \
  --ai-decision "$AI_DECISION" \
  --policy-file policy/release-policy.yaml \
  --runtime opa \
  --output "$POLICY_INPUT"

echo "===== evaluate opa with external command enabled but binary missing ====="
S_SENTINEL_POLICY_RUNTIME_EXTERNAL_COMMANDS=1 \
S_SENTINEL_OPA_BIN="$TMP_DIR/bin/missing-opa" \
./scripts/policy-runtime-adapter.py evaluate \
  --runtime opa \
  --policy-input "$POLICY_INPUT" \
  --output "$MISSING_RESULT" \
  --repo-dir "$ROOT_DIR" \
  --decision-output "$MISSING_DECISION"

python3 - "$MISSING_RESULT" "$MISSING_DECISION" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
decision = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert result["schemaVersion"] == "policy.runtime.result/v1alpha1", result
assert result["runtime"]["name"] == "opa", result
assert result["runtime"]["status"] == "runtime_unavailable", result
assert result["runtime"]["mode"] == "external_command", result
assert result["runtime"]["externalCommandEnabled"] is True, result
assert result["runtime"]["binaryAvailable"] is False, result
assert result["policyDecision"]["policyDecision"] == "REQUIRE_HUMAN_APPROVAL", result
assert result["policyDecision"]["allowed"] is False, result
assert "policy_runtime_unavailable" in result["policyDecision"]["matchedRules"], result
assert result["summary"]["runtimeStatus"] == "runtime_unavailable", result
assert result["safety"]["readOnly"] is True, result
assert result["safety"]["willExecute"] is False, result
assert result["safety"]["doesNotRunExternalCommands"] is True, result
assert decision["schemaVersion"] == "release.policy.evaluator/v1alpha1", decision
assert "policy_runtime_unavailable" in decision["matchedRules"], decision
PY

echo "===== create fake opa binary ====="
cat > "$FAKE_OPA" <<'PY_FAKE_OPA'
#!/usr/bin/env python3
import json
import sys
from pathlib import Path

input_path = None
for idx, item in enumerate(sys.argv):
    if item == "--input" and idx + 1 < len(sys.argv):
        input_path = sys.argv[idx + 1]
        break

policy_input = json.loads(Path(input_path).read_text(encoding="utf-8"))
summary = policy_input.get("inputSummary") or {}

decision = {
    "schemaVersion": "release.policy.evaluator/v1alpha1",
    "policyDecisionId": "pd-opa-" + str(policy_input.get("releaseId") or "unknown"),
    "sourceDecisionFile": policy_input.get("sourceDecisionFile"),
    "releaseId": policy_input.get("releaseId"),
    "evidenceId": None,
    "service": summary.get("service"),
    "env": summary.get("env"),
    "sloId": summary.get("sloId"),
    "strategyId": summary.get("strategyId"),
    "policyDecision": "ALLOW",
    "requestedAction": summary.get("requestedAction"),
    "allowed": True,
    "finalAction": "NOOP",
    "executionMode": "advisory_only",
    "requiresHumanApproval": False,
    "reason": "fake opa allowed PASS/NOOP release",
    "deniedReasons": [],
    "approvalRequiredReasons": [],
    "matchedRules": ["opa_pass_noop_allowed"],
    "signedReleaseGate": policy_input.get("signedReleaseGateRef") or {},
    "inputSummary": summary,
    "safety": {
        "readOnly": True,
        "willExecute": False,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotBuildOrPushImages": True
    },
    "policyRef": policy_input.get("policyRef") or {}
}

print(json.dumps({
    "result": [
        {
            "expressions": [
                {
                    "value": decision
                }
            ]
        }
    ]
}))
PY_FAKE_OPA
chmod +x "$FAKE_OPA"

echo "===== evaluate opa with fake opa binary ====="
S_SENTINEL_POLICY_RUNTIME_EXTERNAL_COMMANDS=1 \
S_SENTINEL_OPA_BIN="$FAKE_OPA" \
./scripts/policy-runtime-adapter.py evaluate \
  --runtime opa \
  --policy-input "$POLICY_INPUT" \
  --output "$EVAL_RESULT" \
  --repo-dir "$ROOT_DIR" \
  --decision-output "$EVAL_DECISION"

python3 - "$POLICY_INPUT" "$EVAL_RESULT" "$EVAL_DECISION" "$FAKE_OPA" <<'PY'
import json
import sys
from pathlib import Path

policy_input = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
decision = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
fake_opa = str(Path(sys.argv[4]))

assert policy_input["runtime"]["requestedRuntime"] == "opa", policy_input
assert result["schemaVersion"] == "policy.runtime.result/v1alpha1", result
assert result["runtime"]["name"] == "opa", result
assert result["runtime"]["status"] == "evaluated", result
assert result["runtime"]["mode"] == "external_command", result
assert result["runtime"]["externalCommandEnabled"] is True, result
assert result["runtime"]["binaryAvailable"] is True, result
assert result["runtime"]["binaryPath"] == fake_opa, result
assert result["runtime"]["exitCode"] == 0, result
assert result["runtime"]["command"][0] == fake_opa, result
assert "eval" in result["runtime"]["command"], result

assert result["policyDecision"]["schemaVersion"] == "release.policy.evaluator/v1alpha1", result
assert result["policyDecision"]["policyDecision"] == "ALLOW", result
assert result["policyDecision"]["allowed"] is True, result
assert result["policyDecision"]["finalAction"] == "NOOP", result
assert result["policyDecision"]["requiresHumanApproval"] is False, result
assert "opa_pass_noop_allowed" in result["policyDecision"]["matchedRules"], result

assert result["summary"]["runtimeStatus"] == "evaluated", result
assert result["summary"]["runtimePreviewOnly"] is False, result
assert result["summary"]["allowed"] is True, result
assert result["summary"]["requiresHumanApproval"] is False, result
assert result["safety"]["readOnly"] is True, result
assert result["safety"]["willExecute"] is False, result
assert result["safety"]["externalCommandEnabled"] is True, result
assert result["safety"]["externalCommandBinaryAvailable"] is True, result
assert result["safety"]["doesNotRunExternalCommands"] is False, result
assert result["safety"]["doesNotModifyKubernetes"] is True, result
assert result["safety"]["doesNotModifyGitOps"] is True, result

assert decision["schemaVersion"] == "release.policy.evaluator/v1alpha1", decision
assert decision["policyDecision"] == "ALLOW", decision
assert "opa_pass_noop_allowed" in decision["matchedRules"], decision
PY

echo "PASS: Stage44 OPA runtime adapter guarded execution test passed"
