#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-approval-record-evidence-link-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run approval record evidence link test ====="

cat > "$TEST_TMP/release-evidence-current.json" <<'JSON'
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
    "failedMetrics": ["error-rate", "p95-latency"]
  },
  "artifacts": {}
}
JSON

cat > "$TEST_TMP/action-plan-current.json" <<JSON
{
  "schemaVersion": "release.action-plan/v1alpha1",
  "generatedBy": "build-action-plan.sh",
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
  },
  "guardrails": {
    "advisoryOnly": true,
    "dryRunOnly": true,
    "doesNotModifyKubernetes": true,
    "doesNotRollback": true
  }
}
JSON

APPROVER="approval-link-human" \
APPROVAL_OUTPUT_DIR="$TEST_TMP" \
  ./scripts/create-approval-record.sh "$TEST_TMP/action-plan-current.json" APPROVED "确认多 SLO 失败，认可 STOP_PROMOTION 建议" \
  >"$TEST_TMP/approval-link.log" 2>&1

cat "$TEST_TMP/approval-link.log"

grep -q "Approval record linked into release evidence" "$TEST_TMP/approval-link.log"

python3 - "$TEST_TMP/release-evidence-current.json" "$TEST_TMP/approval-record-current.json" "$TEST_TMP/approval-record-current.md" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
approval_json = Path(sys.argv[2])
approval_md = Path(sys.argv[3])

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
approval = json.loads(approval_json.read_text(encoding="utf-8"))

artifacts = evidence.get("artifacts", {})
approval_ref = evidence.get("approvalRef", {})

assert artifacts.get("approvalRecord") == str(approval_json), artifacts
assert artifacts.get("approvalRecordReport") == str(approval_md), artifacts

assert approval_ref["generated"] is True, approval_ref
assert approval_ref["decision"] == "APPROVED", approval_ref
assert approval_ref["approvedAction"] == "STOP_PROMOTION", approval_ref
assert approval_ref["executionMode"] == "approval_record_only", approval_ref
assert approval_ref["willExecute"] is False, approval_ref
assert approval_ref["approver"] == "approval-link-human", approval_ref

assert approval["approvalDecision"] == "APPROVED", approval
assert approval["approvedAction"] == "STOP_PROMOTION", approval
assert approval["willExecute"] is False, approval
assert approval["guardrails"]["doesNotModifyKubernetes"] is True, approval["guardrails"]
assert approval["guardrails"]["doesNotRollback"] is True, approval["guardrails"]

assert approval_md.exists(), approval_md

print("Approval record evidence link test passed")
PY
