#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-agent-planning-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run agent planning + lightweight RAG test ====="

RELEASE_EVIDENCE="$TEST_TMP/release-evidence-20260521-310100.json"
EVIDENCE_RECORD="$TEST_TMP/evidence-record-20260521-310100.json"
RELEASE_INTELLIGENCE="$TEST_TMP/release-intelligence-20260521-310100.json"
RELEASE_MEMORY="$TEST_TMP/release-memory.jsonl"

cat > "$RELEASE_EVIDENCE" <<'JSON'
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "policyDecisionId": "pd-plan-test",
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
    "aiDecision": "docs/release-reports/ai-decision-plan-test.json",
    "policyDecision": "docs/release-reports/policy-decision-plan-test.json",
    "releaseSummary": "docs/release-reports/release-summary-plan-test.md",
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
      "policyDecisionId": "pd-plan-test",
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
  "evidenceId": "ev-plan-test",
  "releaseId": "20260521-310100",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-plan-test",
  "commit": "abc1234",
  "imageDigest": "sha256:plan-test",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL"
}
JSON

cat > "$RELEASE_INTELLIGENCE" <<'JSON'
{
  "schemaVersion": "release.intelligence/v1alpha1",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "intelligence": {
    "riskPattern": "repeated_slo_failure_pattern",
    "repeatedRiskPattern": true,
    "recommendedNextAction": "STOP_PROMOTION",
    "conclusion": "本次发布失败指标与历史失败记录完全匹配，属于重复风险模式。"
  }
}
JSON

cat > "$RELEASE_MEMORY" <<'JSONL'
{"releaseId":"previous-exact-failure","generatedAt":"2026-05-20T10:00:00Z","service":"demo-app","env":"dev","appVersion":"v-bad-old","releaseResult":"FAIL_BY_MULTIPLE_SLO","policyDecision":"REQUIRE_HUMAN_APPROVAL","finalAction":"STOP_PROMOTION","requiresHumanApproval":true,"failedMetrics":["error-rate","p95-latency"],"riskLevel":"critical","riskScore":100,"sourceReleaseEvidence":"/tmp/previous/release-evidence-previous-exact-failure.json","artifacts":{"failureEvidence":"/tmp/previous/failure-evidence.json","actionPlan":"/tmp/previous/action-plan.json","releaseIntelligence":"/tmp/previous/release-intelligence.json","agentRun":"/tmp/previous/agent-run.json","runbook":"/tmp/previous/runbook.md","rca":"/tmp/previous/rca.md"}}
{"releaseId":"previous-p95-failure","generatedAt":"2026-05-20T09:00:00Z","service":"demo-app","env":"dev","appVersion":"v-latency-old","releaseResult":"FAIL_BY_P95_LATENCY","policyDecision":"REQUIRE_HUMAN_APPROVAL","finalAction":"STOP_PROMOTION","requiresHumanApproval":true,"failedMetrics":["p95-latency"],"riskLevel":"high","riskScore":70,"sourceReleaseEvidence":"/tmp/previous/release-evidence-previous-p95-failure.json","artifacts":{"failureEvidence":"/tmp/previous/p95-failure-evidence.json","actionPlan":"/tmp/previous/p95-action-plan.json"}}
{"releaseId":"previous-pass","generatedAt":"2026-05-20T08:00:00Z","service":"demo-app","env":"dev","appVersion":"v-good-old","releaseResult":"PASS","policyDecision":"ALLOW_ADVISORY_ONLY","finalAction":"NOOP","requiresHumanApproval":false,"failedMetrics":[],"riskLevel":"low","riskScore":0,"sourceReleaseEvidence":"/tmp/previous/release-evidence-previous-pass.json","artifacts":{}}
JSONL

AGENT_RUN_OUTPUT_DIR="$TEST_TMP" \
RELEASE_MEMORY_FILE="$RELEASE_MEMORY" \
  ./scripts/build-agent-run.sh "$RELEASE_EVIDENCE" "$EVIDENCE_RECORD" "$RELEASE_INTELLIGENCE" \
  >"$TEST_TMP/agent-run.log" 2>&1

cat "$TEST_TMP/agent-run.log"

AGENT_RUN="$TEST_TMP/agent-run-20260521-310100.json"
[ -f "$AGENT_RUN" ] || { echo "FAILED: agent run not generated: $AGENT_RUN" >&2; exit 1; }

PLAN_RUN_OUTPUT_DIR="$TEST_TMP" \
RELEASE_MEMORY_FILE="$RELEASE_MEMORY" \
  ./scripts/build-plan-run.sh "$AGENT_RUN" "$RELEASE_EVIDENCE" "$RELEASE_INTELLIGENCE" \
  >"$TEST_TMP/plan-run.log" 2>&1

cat "$TEST_TMP/plan-run.log"

PLAN_RUN="$TEST_TMP/plan-run-20260521-310100.json"
LATEST_PLAN_RUN="$TEST_TMP/plan-run-latest.json"

[ -f "$PLAN_RUN" ] || { echo "FAILED: plan run not generated: $PLAN_RUN" >&2; exit 1; }
[ -f "$LATEST_PLAN_RUN" ] || { echo "FAILED: latest plan run not generated: $LATEST_PLAN_RUN" >&2; exit 1; }

python3 scripts/validate-release-contracts.py "$PLAN_RUN"

python3 - "$PLAN_RUN" "$AGENT_RUN" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
agent = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert plan["schemaVersion"] == "agent.plan.run/v1alpha1", plan
assert plan["mode"] == "read_only_planning", plan
assert plan["sourceAgentRunId"] == agent["agentRunId"], plan
assert plan["release"]["releaseId"] == "20260521-310100", plan["release"]
assert plan["release"]["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", plan["release"]
assert plan["release"]["failedMetrics"] == ["error-rate", "p95-latency"], plan["release"]

assert plan["retrieval"]["strategy"] == "lightweight_rule_based_rag_v1", plan["retrieval"]
assert plan["retrieval"]["summary"]["retrievedEvidenceCount"] == 2, plan["retrieval"]
assert plan["retrieval"]["retrievedEvidence"][0]["releaseId"] == "previous-exact-failure", plan["retrieval"]
retrieved_results = [item["releaseResult"] for item in plan["retrieval"]["retrievedEvidence"]]
assert "PASS" not in retrieved_results, retrieved_results

step_ids = [step["stepId"] for step in plan["plan"]["investigationSteps"]]
assert "review_policy_decision" in step_ids, step_ids
assert "compare_change_context" in step_ids, step_ids
assert "inspect_canary_logs" in step_ids, step_ids
assert "inspect_5xx_error_paths" in step_ids, step_ids
assert "inspect_tail_latency_paths" in step_ids, step_ids
assert "review_similar_failure_evidence" in step_ids, step_ids

assert plan["plan"]["planType"] == "rag_assisted_failure_investigation", plan["plan"]
assert plan["plan"]["priority"] == "critical", plan["plan"]
assert plan["plan"]["willExecute"] is False, plan["plan"]
assert plan["plan"]["candidateFollowUpActions"], plan["plan"]
assert plan["plan"]["candidateFollowUpActions"][0]["requiresStage32ExecutionRequest"] is True, plan["plan"]

assert plan["guardrails"]["readOnly"] is True, plan["guardrails"]
assert plan["guardrails"]["willExecute"] is False, plan["guardrails"]
assert plan["guardrails"]["doesNotModifyKubernetes"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotModifyGitOps"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotRollback"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotPromote"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotPatchResources"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotDeleteResources"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotCommitOrPush"] is True, plan["guardrails"]

print("PASS: agent planning + lightweight RAG content")
PY

python3 - "$PLAN_RUN" "$RELEASE_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
evidence = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert evidence["planRunId"] == plan["planRunId"], evidence
assert evidence["artifacts"]["planRun"] == str(Path(sys.argv[1])), evidence["artifacts"]
assert evidence["decisionRefs"]["planRun"]["planRunId"] == plan["planRunId"], evidence["decisionRefs"]["planRun"]
assert evidence["decisionRefs"]["planRun"]["sourceAgentRunId"] == plan["sourceAgentRunId"], evidence["decisionRefs"]["planRun"]
assert evidence["decisionRefs"]["planRun"]["planType"] == "rag_assisted_failure_investigation", evidence["decisionRefs"]["planRun"]
assert evidence["decisionRefs"]["planRun"]["retrievedEvidenceCount"] == 2, evidence["decisionRefs"]["planRun"]
assert evidence["decisionRefs"]["planRun"]["willExecute"] is False, evidence["decisionRefs"]["planRun"]

print("PASS: release evidence includes read-only plan run link")
PY

echo "===== build evidence record with plan run link ====="
EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP" \
  ./scripts/build-evidence-record.sh "$RELEASE_EVIDENCE" \
  >"$TEST_TMP/evidence-record.log" 2>&1

cat "$TEST_TMP/evidence-record.log"

python3 scripts/validate-release-contracts.py "$EVIDENCE_RECORD"

python3 - "$EVIDENCE_RECORD" "$PLAN_RUN" "$AGENT_RUN" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plan_run_path = Path(sys.argv[2])
agent_run_path = Path(sys.argv[3])

assert record["plan"]["planRunId"] == "pr-20260521-310100", record["plan"]
assert record["plan"]["mode"] == "read_only_planning", record["plan"]
assert record["plan"]["sourceAgentRunId"] == "ar-20260521-310100", record["plan"]
assert record["plan"]["planType"] == "rag_assisted_failure_investigation", record["plan"]
assert record["plan"]["priority"] == "critical", record["plan"]
assert record["plan"]["willExecute"] is False, record["plan"]
assert record["plan"]["sourcePlanRun"] == str(plan_run_path), record["plan"]
assert record["plan"]["retrievedEvidenceCount"] == 2, record["plan"]

assert record["agent"]["sourceAgentRun"] == str(agent_run_path), record["agent"]
assert record["links"]["planRun"] == str(plan_run_path), record["links"]

print("PASS: evidence record includes read-only plan run link")
PY

echo "PASS: agent planning test passed"
