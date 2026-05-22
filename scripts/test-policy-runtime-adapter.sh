#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-policy-runtime-adapter-test}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

AI_DECISION="$TMP_DIR/ai-decision-20260101-000000.json"
POLICY_INPUT="$TMP_DIR/policy-input.json"
POLICY_RESULT="$TMP_DIR/policy-runtime-result.json"

cat > "$AI_DECISION" <<'JSON'
{
  "schemaVersion": "ai.release.advisor/v1alpha1",
  "generatedBy": "test-policy-runtime-adapter.sh",
  "model": "deterministic-test",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "decisionSource": "deterministic_rule",
  "confidence": "high",
  "executionMode": "advisory_only",
  "summary": "test",
  "conclusion": "test",
  "failedMetrics": ["error-rate", "p95-latency"],
  "riskLevel": "critical",
  "riskScore": 100,
  "riskReasons": [],
  "decision": "test",
  "recommendedAction": "STOP_PROMOTION",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "service": "demo-app",
  "env": "dev",
  "sloId": "demo-app-canary-slo",
  "strategyId": "demo-app-canary-strategy",
  "strategyType": "canary",
  "strategyFailurePolicy": {
    "onSLOFailure": "stop_promotion",
    "onAnalysisError": "require_manual_review",
    "onInsufficientTraffic": "retry_with_more_traffic",
    "rollbackAllowed": false
  },
  "strategyPromotionPolicy": {
    "autoPromotionEnabled": false,
    "requiresHumanApproval": true,
    "finalPromotionMode": "manual"
  },
  "agentAction": {
    "type": "STOP_PROMOTION",
    "allowed": true,
    "requiresApproval": true,
    "reason": "test"
  },
  "guardrails": {
    "autoExecute": false,
    "executionMode": "advisory_only",
    "allowedActions": [
      "NOOP",
      "OBSERVE",
      "RETRY_WITH_MORE_TRAFFIC",
      "STOP_PROMOTION",
      "INVESTIGATE",
      "MANUAL_REVIEW",
      "ROLLBACK",
      "PROMOTE"
    ],
    "blockedActions": [
      "DELETE_RESOURCE",
      "PATCH_RESOURCE",
      "APPLY_MANIFEST"
    ]
  },
  "evidence": {
    "service": "demo-app",
    "env": "dev",
    "sloId": "demo-app-canary-slo",
    "strategyId": "demo-app-canary-strategy",
    "strategyType": "canary"
  },
  "nextSteps": [],
  "rollout": {},
  "analysisRun": {},
  "sources": {}
}
JSON

echo "===== build policy input ====="
./scripts/policy-runtime-adapter.py build-input \
  --ai-decision "$AI_DECISION" \
  --policy-file policy/release-policy.yaml \
  --output "$POLICY_INPUT"

cat "$POLICY_INPUT"

echo
echo "===== evaluate policy input ====="
./scripts/policy-runtime-adapter.py evaluate \
  --runtime local-python \
  --policy-input "$POLICY_INPUT" \
  --output "$POLICY_RESULT" \
  --repo-dir "$ROOT_DIR"

cat "$POLICY_RESULT"

echo
echo "===== assert policy runtime result ====="
python3 - "$POLICY_INPUT" "$POLICY_RESULT" <<'PY'
import json
import sys
from pathlib import Path

policy_input = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert policy_input["schemaVersion"] == "policy.input/v1alpha1", policy_input
assert policy_input["inputSummary"]["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", policy_input
assert policy_input["inputSummary"]["requestedAction"] == "STOP_PROMOTION", policy_input

assert result["schemaVersion"] == "policy.runtime.result/v1alpha1", result
assert result["runtime"]["name"] == "local-python", result
assert result["policyDecision"]["policyDecision"] == "REQUIRE_HUMAN_APPROVAL", result
assert result["policyDecision"]["finalAction"] == "STOP_PROMOTION", result
assert result["policyDecision"]["allowed"] is True, result
assert result["summary"]["requiresHumanApproval"] is True, result
assert result["safety"]["readOnly"] is True, result
assert result["safety"]["willExecute"] is False, result

print("PASS: PolicyRuntimeAdapter local-python contract is valid")
PY

echo
echo "PASS: policy runtime adapter test passed"
