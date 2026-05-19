#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-agent-tool-router-approval-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run agent tool router approval record test ====="

cat > "$TEST_TMP/action-plan-current.json" <<'JSON'
{
  "schemaVersion": "release.action-plan/v1alpha1",
  "generatedBy": "build-action-plan.sh",
  "sourceReleaseEvidence": "/tmp/slo-agent-tool-router-approval-test/release-evidence-current.json",
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
        "name": "inspect_rollout",
        "command": "kubectl argo rollouts get rollout demo-app -n slo-rollout",
        "type": "read_only",
        "willExecute": false
      },
      {
        "name": "candidate_abort_rollout",
        "command": "kubectl argo rollouts abort demo-app -n slo-rollout",
        "type": "write_candidate_requires_human_approval",
        "willExecute": false
      }
    ],
    "humanSteps": [
      "停止继续扩大流量。",
      "人工检查 canary 版本日志、事件、AnalysisRun 指标和本次变更内容。"
    ]
  },
  "guardrails": {
    "advisoryOnly": true,
    "dryRunOnly": true,
    "doesNotModifyKubernetes": true,
    "doesNotRollback": true
  }
}
JSON

RELEASE_REPORT_DIR="$TEST_TMP" \
APPROVAL_OUTPUT_DIR="$TEST_TMP" \
APPROVER="router-human" \
  ./scripts/agent-tool-router.sh create-approval-record "$TEST_TMP/action-plan-current.json" APPROVED "通过 router 记录人工认可 STOP_PROMOTION" \
  >"$TEST_TMP/router-create.log" 2>&1

cat "$TEST_TMP/router-create.log"

grep -q "toolName: create-approval-record" "$TEST_TMP/router-create.log"
grep -q "executionMode: approval_record_only" "$TEST_TMP/router-create.log"
grep -q "willExecute: false" "$TEST_TMP/router-create.log"
grep -q "Approval record JSON generated" "$TEST_TMP/router-create.log"

RELEASE_REPORT_DIR="$TEST_TMP" \
  ./scripts/agent-tool-router.sh get-latest-approval-record json \
  >"$TEST_TMP/router-get-json.log" 2>&1

cat "$TEST_TMP/router-get-json.log"

grep -q "toolName: get-latest-approval-record" "$TEST_TMP/router-get-json.log"
grep -q "toolOutputFile:" "$TEST_TMP/router-get-json.log"
grep -q '"approvalDecision": "APPROVED"' "$TEST_TMP/router-get-json.log"

RELEASE_REPORT_DIR="$TEST_TMP" \
  ./scripts/agent-tool-router.sh get-latest-approval-record markdown \
  >"$TEST_TMP/router-get-md.log" 2>&1

grep -q "Human Approval Record" "$TEST_TMP/router-get-md.log"
grep -q "APPROVED" "$TEST_TMP/router-get-md.log"
grep -q "Will Execute" "$TEST_TMP/router-get-md.log"

python3 - "$TEST_TMP/approval-record-current.json" "$TEST_TMP/approval-record-current.md" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
md = Path(sys.argv[2]).read_text(encoding="utf-8")

assert record["schemaVersion"] == "release.approval/v1alpha1", record
assert record["approvalDecision"] == "APPROVED", record
assert record["approvedAction"] == "STOP_PROMOTION", record
assert record["executionMode"] == "approval_record_only", record
assert record["willExecute"] is False, record
assert record["approver"] == "router-human", record
assert record["release"]["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", record["release"]
assert record["release"]["finalAction"] == "STOP_PROMOTION", record["release"]
assert record["actionPlan"]["candidateCommandCount"] == 2, record["actionPlan"]
assert record["guardrails"]["doesNotModifyKubernetes"] is True, record["guardrails"]
assert record["guardrails"]["doesNotRollback"] is True, record["guardrails"]
assert record["guardrails"]["willExecute"] is False, record["guardrails"]

assert "Human Approval Record" in md
assert "APPROVED" in md
assert "STOP_PROMOTION" in md
assert "不会自动执行" in md

print("Agent tool router approval record test passed")
PY
