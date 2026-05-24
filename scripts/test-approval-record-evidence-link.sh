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
  "artifacts": {
    "executionRequest": "__EXECUTION_REQUEST__"
  }
}
JSON

cat > "$TEST_TMP/execution-request-current.json" <<JSON
{
  "schemaVersion": "execution.request/v1alpha1",
  "executionRequestId": "er-approval-link-test",
  "generatedBy": "test-approval-record-evidence-link.sh",
  "generatedAt": "2026-05-24T00:00:00Z",
  "mode": "request_only",
  "sourcePlanRunId": "pr-approval-link-test",
  "release": {
    "releaseId": "approval-link-test",
    "releaseResult": "FAIL_BY_MULTIPLE_SLO",
    "policyDecision": "ALLOW_ADVISORY_ONLY",
    "failedMetrics": ["error-rate", "p95-latency"]
  },
  "request": {
    "requestedBy": "test-agent-planner",
    "requestedAction": "STOP_PROMOTION",
    "requestReason": "stage32 test fixture",
    "requestStatus": "PENDING_APPROVAL",
    "lifecycleStage": "WAITING_APPROVAL",
    "candidateActionCount": 1,
    "candidateActions": [
      {
        "action": "STOP_PROMOTION",
        "requiresHumanApproval": true,
        "requiresStage32ExecutionRequest": true
      }
    ],
    "willExecute": false
  },
  "policyBinding": {
    "policyDecision": "ALLOW_ADVISORY_ONLY",
    "recommendedAction": "STOP_PROMOTION",
    "requiresHumanApproval": true,
    "stage32Required": true,
    "policyBound": true,
    "allowedToRequest": true,
    "willExecute": false,
    "blockingReasons": []
  },
  "approval": {
    "required": true,
    "status": "NOT_APPROVED",
    "approved": false,
    "approvalDecision": null,
    "approver": null,
    "reason": null,
    "updatedAt": null,
    "readyToExecute": false,
    "willExecuteAfterApproval": false
  },
  "evidence": {
    "releaseEvidence": "$TEST_TMP/release-evidence-current.json",
    "approvalRecord": null,
    "approvalRecordReport": null,
    "artifacts": {}
  },
  "guardrails": {
    "requestOnly": true,
    "readOnly": true,
    "willExecute": false,
    "doesNotModifyKubernetes": true,
    "doesNotModifyGitOps": true,
    "doesNotRollback": true,
    "doesNotPromote": true,
    "doesNotPatchResources": true,
    "doesNotDeleteResources": true,
    "doesNotBuildImages": true,
    "doesNotCommitOrPush": true
  }
}
JSON

python3 - "$TEST_TMP/release-evidence-current.json" "$TEST_TMP/execution-request-current.json" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
execution_request_path = Path(sys.argv[2])

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
evidence["artifacts"]["executionRequest"] = str(execution_request_path)
evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

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
grep -q "Execution request updated with approval outcome" "$TEST_TMP/approval-link.log"

python3 - "$TEST_TMP/release-evidence-current.json" "$TEST_TMP/approval-record-current.json" "$TEST_TMP/approval-record-current.md" "$TEST_TMP/execution-request-current.json" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
approval_json = Path(sys.argv[2])
approval_md = Path(sys.argv[3])
execution_request_path = Path(sys.argv[4])

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
approval = json.loads(approval_json.read_text(encoding="utf-8"))
execution_request = json.loads(execution_request_path.read_text(encoding="utf-8"))

artifacts = evidence.get("artifacts", {})
approval_ref = evidence.get("approvalRef", {})
decision_ref = (evidence.get("decisionRefs") or {}).get("executionRequest", {})

assert artifacts.get("approvalRecord") == str(approval_json), artifacts
assert artifacts.get("approvalRecordReport") == str(approval_md), artifacts

assert approval_ref["generated"] is True, approval_ref
assert approval_ref["decision"] == "APPROVED", approval_ref
assert approval_ref["approvedAction"] == "STOP_PROMOTION", approval_ref
assert approval_ref["executionMode"] == "approval_record_only", approval_ref
assert approval_ref["willExecute"] is False, approval_ref
assert approval_ref["approver"] == "approval-link-human", approval_ref
assert approval_ref["executionRequestId"] == "er-approval-link-test", approval_ref
assert approval_ref["sourceExecutionRequest"] == str(execution_request_path), approval_ref
assert approval_ref["readyToExecute"] is True, approval_ref

assert decision_ref["executionRequestId"] == "er-approval-link-test", decision_ref
assert decision_ref["lifecycleStage"] == "READY_TO_EXECUTE", decision_ref
assert decision_ref["approvalStatus"] == "APPROVED", decision_ref
assert decision_ref["approvalDecision"] == "APPROVED", decision_ref
assert decision_ref["approver"] == "approval-link-human", decision_ref
assert decision_ref["readyToExecute"] is True, decision_ref
assert decision_ref["approvalRecord"] == str(approval_json), decision_ref
assert decision_ref["approvalRecordReport"] == str(approval_md), decision_ref

assert approval["approvalDecision"] == "APPROVED", approval
assert approval["approvedAction"] == "STOP_PROMOTION", approval
assert approval["willExecute"] is False, approval
assert approval["executionRequestId"] == "er-approval-link-test", approval
assert approval["sourceExecutionRequest"] == str(execution_request_path), approval
assert approval["guardrails"]["doesNotModifyKubernetes"] is True, approval["guardrails"]
assert approval["guardrails"]["doesNotRollback"] is True, approval["guardrails"]

assert execution_request["request"]["lifecycleStage"] == "READY_TO_EXECUTE", execution_request["request"]
assert execution_request["approval"]["status"] == "APPROVED", execution_request["approval"]
assert execution_request["approval"]["approved"] is True, execution_request["approval"]
assert execution_request["approval"]["approvalDecision"] == "APPROVED", execution_request["approval"]
assert execution_request["approval"]["approver"] == "approval-link-human", execution_request["approval"]
assert execution_request["approval"]["readyToExecute"] is True, execution_request["approval"]
assert execution_request["evidence"]["approvalRecord"] == str(approval_json), execution_request["evidence"]
assert execution_request["evidence"]["approvalRecordReport"] == str(approval_md), execution_request["evidence"]

assert approval_md.exists(), approval_md

print("Approval record evidence link test passed")
PY

if ! EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP/evidence-record-out" \
  ./scripts/build-evidence-record.sh "$TEST_TMP/release-evidence-current.json" \
  >"$TEST_TMP/evidence-record.log" 2>&1; then
  cat "$TEST_TMP/evidence-record.log" || true
  echo "FAILED: build-evidence-record.sh failed" >&2
  exit 1
fi

cat "$TEST_TMP/evidence-record.log"

python3 - "$TEST_TMP/evidence-record-out/evidence-record-latest.json" "$TEST_TMP/approval-record-current.json" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
approval_json = Path(sys.argv[2])
execution_request = record.get("executionRequest", {})

assert execution_request["lifecycleStage"] == "READY_TO_EXECUTE", execution_request
assert execution_request["approvalStatus"] == "APPROVED", execution_request
assert execution_request["approvalDecision"] == "APPROVED", execution_request
assert execution_request["approver"] == "approval-link-human", execution_request
assert execution_request["readyToExecute"] is True, execution_request
assert execution_request["approvalRecord"] == str(approval_json), execution_request

print("Approval-linked evidence record test passed")
PY
