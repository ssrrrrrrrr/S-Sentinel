#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-approval-record-report-integration-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run approval record report integration test ====="

cat > "$TEST_TMP/ai-advice-current.md" <<'MD'
# AI Release Advice

Existing AI advice content.
MD

cat > "$TEST_TMP/release-evidence-current.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "ALLOW_ADVISORY_ONLY",
  "finalAction": "STOP_PROMOTION",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "summary": {
    "rolloutPhase": "Degraded",
    "rolloutAbort": true,
    "analysisRunPhase": "Failed",
    "riskLevel": "critical",
    "riskScore": 100,
    "failedMetrics": ["error-rate", "p95-latency"],
    "matchedPolicyRules": ["multiple_slo_failure_requires_human_approval"]
  },
  "artifacts": {
    "aiAdvice": "$TEST_TMP/ai-advice-current.md"
  },
  "decisionRefs": {
    "aiDecision": {
      "agentAction": {
        "type": "STOP_PROMOTION",
        "allowed": true,
        "requiresApproval": true,
        "reason": "Release failed SLO gates and requires human investigation"
      }
    },
    "policyDecision": {
      "reason": "Multiple SLO gates failed; action is advisory only and requires human approval"
    }
  }
}
JSON

cat > "$TEST_TMP/action-plan-current.json" <<JSON
{
  "schemaVersion": "release.action-plan/v1alpha1",
  "sourceReleaseEvidence": "$TEST_TMP/release-evidence-current.json",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "ALLOW_ADVISORY_ONLY",
  "finalAction": "STOP_PROMOTION",
  "executionMode": "dry_run",
  "sourceExecutionMode": "advisory_only",
  "willExecute": false,
  "requiresHumanApproval": true,
  "target": {
    "namespace": "slo-rollout",
    "rollout": "demo-app",
    "analysisRun": "demo-app-multiple-analysis"
  },
  "actionPlan": {
    "action": "STOP_PROMOTION",
    "blocked": false,
    "blockReason": "",
    "candidateCommands": [
      {
        "name": "candidate_abort_rollout",
        "command": "kubectl argo rollouts abort demo-app -n slo-rollout",
        "type": "write_candidate_requires_human_approval",
        "willExecute": false
      }
    ],
    "humanSteps": ["停止继续扩大流量。"]
  }
}
JSON

APPROVER="stage20-human" \
APPROVAL_OUTPUT_DIR="$TEST_TMP" \
  ./scripts/create-approval-record.sh "$TEST_TMP/action-plan-current.json" APPROVED "确认停止继续放量，但不自动执行" \
  >"$TEST_TMP/approval-report.log" 2>&1

cat "$TEST_TMP/approval-report.log"

grep -q "Approval record linked into release evidence" "$TEST_TMP/approval-report.log"
grep -q "Release summary rebuilt with approval record" "$TEST_TMP/approval-report.log"
grep -q "Human approval record appended to AI advice" "$TEST_TMP/approval-report.log"

SUMMARY_MD="$TEST_TMP/release-summary-current.md"
AI_ADVICE="$TEST_TMP/ai-advice-current.md"

python3 - "$TEST_TMP/release-evidence-current.json" "$SUMMARY_MD" "$AI_ADVICE" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
summary = Path(sys.argv[2]).read_text(encoding="utf-8")
advice = Path(sys.argv[3]).read_text(encoding="utf-8")

artifacts = evidence.get("artifacts", {})
approval_ref = evidence.get("approvalRef", {})

assert artifacts.get("approvalRecord"), artifacts
assert artifacts.get("approvalRecordReport"), artifacts
assert approval_ref.get("generated") is True, approval_ref
assert approval_ref.get("decision") == "APPROVED", approval_ref
assert approval_ref.get("approvedAction") == "STOP_PROMOTION", approval_ref
assert approval_ref.get("willExecute") is False, approval_ref

assert "Human Approval Record 人工审批记录" in summary
assert "Approval Decision：`APPROVED`" in summary
assert "Approved Action：`STOP_PROMOTION`" in summary
assert "Will Execute：`false`" in summary
assert "确认停止继续放量" in summary
assert "Approval Record JSON" in summary

assert "Human Approval Record" in advice
assert "Approval Decision: `APPROVED`" in advice
assert "Approved Action: `STOP_PROMOTION`" in advice
assert "Will Execute: `false`" in advice
assert "approval_record_only" in advice
assert "does not execute Rollback" in advice

print("Approval record report integration test passed")
PY
