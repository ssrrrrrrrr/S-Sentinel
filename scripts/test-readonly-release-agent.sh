#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-readonly-release-agent-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run read-only release agent test ====="

RELEASE_EVIDENCE="$TEST_TMP/release-evidence-20260521-280100.json"
EVIDENCE_RECORD="$TEST_TMP/evidence-record-20260521-280100.json"
RELEASE_INTELLIGENCE="$TEST_TMP/release-intelligence-20260521-280100.json"

cat > "$RELEASE_EVIDENCE" <<'JSON'
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "policyDecisionId": "pd-test",
  "requestedAction": "STOP_PROMOTION",
  "allowed": true,
  "deniedReasons": [],
  "approvalRequiredReasons": [
    "agent_action_requires_approval",
    "slo_failure_requires_human_approval"
  ],
  "strategyPolicy": {
    "onSLOFailure": "stop_promotion",
    "rollbackAllowed": false,
    "autoPromotionEnabled": false
  },
  "policySafety": {
    "readOnly": true,
    "willExecute": false,
    "autoExecute": false,
    "advisoryOnly": true
  },
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "service": "demo-app",
  "env": "dev",
  "sloId": "demo-app-canary-slo",
  "strategyId": "demo-app-canary-strategy",
  "summary": {
    "rolloutPhase": "Degraded",
    "rolloutAbort": true,
    "analysisRunPhase": "Failed",
    "riskLevel": "critical",
    "riskScore": 100,
    "failedMetrics": [
      "error-rate",
      "p95-latency"
    ],
    "matchedPolicyRules": [
      "slo_failure_stop_promotion_allowed_by_strategy",
      "auto_execute_disabled",
      "guardrail_advisory_only"
    ]
  },
  "artifacts": {
    "releaseContext": null,
    "aiDecision": "docs/release-reports/ai-decision-test.json",
    "policyDecision": "docs/release-reports/policy-decision-test.json",
    "releaseSummary": "docs/release-reports/release-summary-test.md",
    "actionPlan": null
  },
  "decisionRefs": {
    "aiDecision": {
      "decisionSource": "deterministic_rule",
      "confidence": "high",
      "agentAction": {
        "type": "STOP_PROMOTION",
        "allowed": true,
        "requiresApproval": true,
        "reason": "Release failed SLO gates and requires human investigation"
      },
      "policyHints": [
        "multiple_slo_gates_failed",
        "human_approval_required"
      ],
      "nextSteps": [
        "stop_promotion",
        "inspect_canary_logs"
      ]
    },
    "policyDecision": {
      "policyDecisionId": "pd-test",
      "requestedAction": "STOP_PROMOTION",
      "allowed": true,
      "matchedRules": [
        "slo_failure_stop_promotion_allowed_by_strategy"
      ]
    }
  }
}
JSON

cat > "$EVIDENCE_RECORD" <<'JSON'
{
  "schemaVersion": "evidence.record/v1alpha1",
  "evidenceId": "ev-test",
  "releaseId": "20260521-280100",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-agent-test",
  "commit": "abc1234",
  "imageDigest": "sha256:test",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL"
}
JSON

cat > "$RELEASE_INTELLIGENCE" <<'JSON'
{
  "schemaVersion": "release.intelligence/v1alpha1",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "riskPattern": "repeated_slo_failure_pattern",
  "repeatedRiskPattern": true,
  "similarFailureCount": 1,
  "similarFailureIncludingCurrentCount": 2,
  "recommendedNextAction": "STOP_PROMOTION",
  "conclusion": "本次发布失败指标与历史失败记录完全匹配，属于重复风险模式。建议停止继续放量并人工排查。"
}
JSON

AGENT_RUN_OUTPUT_DIR="$TEST_TMP" \
  ./scripts/build-agent-run.sh "$RELEASE_EVIDENCE" "$EVIDENCE_RECORD" "$RELEASE_INTELLIGENCE" \
  >"$TEST_TMP/agent-run.log" 2>&1

cat "$TEST_TMP/agent-run.log"

AGENT_RUN="$TEST_TMP/agent-run-20260521-280100.json"
LATEST_AGENT_RUN="$TEST_TMP/agent-run-latest.json"

[ -f "$AGENT_RUN" ] || { echo "FAILED: agent run not generated: $AGENT_RUN" >&2; exit 1; }
[ -f "$LATEST_AGENT_RUN" ] || { echo "FAILED: latest agent run not generated: $LATEST_AGENT_RUN" >&2; exit 1; }

python3 scripts/validate-release-contracts.py "$AGENT_RUN"

python3 - "$AGENT_RUN" "$RELEASE_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

agent_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])

agent = json.loads(agent_path.read_text(encoding="utf-8"))
evidence_after = json.loads(evidence_path.read_text(encoding="utf-8"))

assert agent["schemaVersion"] == "agent.run/v1alpha1", agent
assert agent["mode"] == "read_only", agent
assert agent["release"]["releaseId"] == "20260521-280100", agent["release"]
assert agent["release"]["service"] == "demo-app", agent["release"]
assert agent["release"]["env"] == "dev", agent["release"]
assert agent["release"]["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", agent["release"]

assert agent["observation"]["failedMetrics"] == ["error-rate", "p95-latency"], agent["observation"]
assert agent["observation"]["riskLevel"] == "critical", agent["observation"]

assert agent["policy"]["policyDecision"] == "REQUIRE_HUMAN_APPROVAL", agent["policy"]
assert agent["policy"]["requestedAction"] == "STOP_PROMOTION", agent["policy"]
assert agent["policy"]["finalAction"] == "STOP_PROMOTION", agent["policy"]
assert agent["policy"]["requiresHumanApproval"] is True, agent["policy"]

assert agent["reasoning"]["riskPattern"] == "repeated_slo_failure_pattern", agent["reasoning"]
assert agent["reasoning"]["repeatedRiskPattern"] is True, agent["reasoning"]

assert agent["recommendation"]["recommendedAction"] == "STOP_PROMOTION", agent["recommendation"]
assert agent["recommendation"]["priority"] == "critical", agent["recommendation"]
assert agent["recommendation"]["willExecute"] is False, agent["recommendation"]
assert "review_policy_decision" in agent["recommendation"]["humanNextSteps"], agent["recommendation"]

assert agent["guardrails"]["readOnly"] is True, agent["guardrails"]
assert agent["guardrails"]["willExecute"] is False, agent["guardrails"]
assert agent["guardrails"]["doesNotModifyKubernetes"] is True, agent["guardrails"]
assert agent["guardrails"]["doesNotModifyGitOps"] is True, agent["guardrails"]
assert agent["guardrails"]["doesNotRollback"] is True, agent["guardrails"]
assert agent["guardrails"]["doesNotPromote"] is True, agent["guardrails"]
assert agent["guardrails"]["doesNotCommitOrPush"] is True, agent["guardrails"]

assert evidence_after["agentRunId"] == agent["agentRunId"], evidence_after
assert evidence_after["artifacts"]["agentRun"] == str(agent_path), evidence_after["artifacts"]
assert evidence_after["decisionRefs"]["agentRun"]["recommendedAction"] == "STOP_PROMOTION", evidence_after["decisionRefs"]["agentRun"]
assert evidence_after["decisionRefs"]["agentRun"]["willExecute"] is False, evidence_after["decisionRefs"]["agentRun"]

print("PASS: read-only release agent run content")
PY

echo "===== build evidence record with agent run link ====="
EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP" \
  ./scripts/build-evidence-record.sh "$RELEASE_EVIDENCE" \
  >"$TEST_TMP/evidence-record.log" 2>&1

cat "$TEST_TMP/evidence-record.log"

python3 scripts/validate-release-contracts.py "$EVIDENCE_RECORD"

python3 - "$EVIDENCE_RECORD" "$AGENT_RUN" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
agent_run_path = Path(sys.argv[2])

assert record["agent"]["agentRunId"] == "ar-20260521-280100", record["agent"]
assert record["agent"]["mode"] == "read_only", record["agent"]
assert record["agent"]["recommendedAction"] == "STOP_PROMOTION", record["agent"]
assert record["agent"]["priority"] == "critical", record["agent"]
assert record["agent"]["willExecute"] is False, record["agent"]
assert record["agent"]["sourceAgentRun"] == str(agent_run_path), record["agent"]
assert record["links"]["agentRun"] == str(agent_run_path), record["links"]

print("PASS: evidence record includes read-only agent run link")
PY

echo "PASS: read-only release agent test passed"
