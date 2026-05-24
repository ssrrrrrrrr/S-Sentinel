#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

if [ -z "${PYTHON_BIN:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: python runtime not found. Set PYTHON_BIN=/path/to/python." >&2
    exit 1
  fi
fi

TEST_TMP="${1:-/tmp/slo-execution-request-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"
mkdir -p "$TEST_TMP/evidence-record-out"

echo
echo "===== run policy-bound execution request test ====="

PLAN_RUN="$TEST_TMP/plan-run-20260521-320100.json"
RELEASE_EVIDENCE="$TEST_TMP/release-evidence-20260521-320100.json"

cat > "$RELEASE_EVIDENCE" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "service": "demo-app",
  "env": "dev",
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
      "slo_failure_stop_promotion_allowed_by_strategy"
    ]
  },
  "artifacts": {
    "planRun": "$PLAN_RUN"
  },
  "decisionRefs": {}
}
JSON

cat > "$PLAN_RUN" <<JSON
{
  "schemaVersion": "agent.plan.run/v1alpha1",
  "planRunId": "pr-20260521-320100",
  "sourceAgentRunId": "ar-20260521-320100",
  "generatedBy": "test",
  "generatedAt": "2026-05-21T12:00:00Z",
  "mode": "read_only_planning",
  "release": {
    "releaseId": "20260521-320100",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "version": "v-exec-request-test",
    "commit": "abc1234",
    "imageDigest": "sha256:exec-request-test",
    "releaseResult": "FAIL_BY_MULTIPLE_SLO",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "recommendedAction": "STOP_PROMOTION",
    "failedMetrics": [
      "error-rate",
      "p95-latency"
    ],
    "riskLevel": "critical",
    "riskScore": 100
  },
  "inputs": {
    "agentRun": "$TEST_TMP/agent-run-20260521-320100.json",
    "releaseEvidence": "$RELEASE_EVIDENCE",
    "releaseIntelligence": "$TEST_TMP/release-intelligence-20260521-320100.json",
    "releaseMemory": "$TEST_TMP/release-memory.jsonl",
    "artifacts": {
      "failureEvidence": "$TEST_TMP/failure-evidence.json",
      "actionPlan": "$TEST_TMP/action-plan.json"
    }
  },
  "retrieval": {
    "strategy": "lightweight_rule_based_rag_v1",
    "query": {
      "releaseId": "20260521-320100",
      "failedMetrics": [
        "error-rate",
        "p95-latency"
      ]
    },
    "retrievedEvidence": [],
    "summary": {
      "retrievedEvidenceCount": 2,
      "topScore": 63
    }
  },
  "plan": {
    "planType": "rag_assisted_failure_investigation",
    "priority": "critical",
    "summary": "Release failed and similar historical evidence was retrieved.",
    "investigationSteps": [],
    "candidateFollowUpActions": [
      {
        "action": "STOP_PROMOTION",
        "reason": "Recommended by read-only agent planning stage.",
        "requiresStage32ExecutionRequest": true,
        "requiresHumanApproval": true,
        "willExecute": false
      },
      {
        "action": "PREPARE_FIX_FORWARD_OR_ROLLBACK_DECISION",
        "reason": "Failure remediation must be converted into a policy-bound execution request before any change.",
        "requiresStage32ExecutionRequest": true,
        "requiresHumanApproval": true,
        "willExecute": false
      }
    ],
    "willExecute": false
  },
  "guardrails": {
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

EXECUTION_REQUEST_OUTPUT_DIR="$TEST_TMP" \
REQUESTED_BY="test-agent-planner" \
  ./scripts/build-execution-request.sh "$PLAN_RUN" \
  >"$TEST_TMP/execution-request.log" 2>&1

cat "$TEST_TMP/execution-request.log"

EXECUTION_REQUEST="$TEST_TMP/execution-request-20260521-320100.json"
LATEST_EXECUTION_REQUEST="$TEST_TMP/execution-request-latest.json"

[ -f "$EXECUTION_REQUEST" ] || { echo "FAILED: execution request not generated: $EXECUTION_REQUEST" >&2; exit 1; }
[ -f "$LATEST_EXECUTION_REQUEST" ] || { echo "FAILED: latest execution request not generated: $LATEST_EXECUTION_REQUEST" >&2; exit 1; }

"$PYTHON_BIN" scripts/validate-release-contracts.py "$EXECUTION_REQUEST"

"$PYTHON_BIN" - "$EXECUTION_REQUEST" "$PLAN_RUN" <<'PY'
import json
import sys
from pathlib import Path

request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plan_run_path = Path(sys.argv[2])

assert request["schemaVersion"] == "execution.request/v1alpha1", request
assert request["executionRequestId"] == "er-20260521-320100", request
assert request["mode"] == "request_only", request
assert request["sourcePlanRunId"] == "pr-20260521-320100", request

assert request["request"]["requestedBy"] == "test-agent-planner", request["request"]
assert request["request"]["requestedAction"] == "STOP_PROMOTION", request["request"]
assert request["request"]["requestStatus"] == "PENDING_APPROVAL", request["request"]
assert request["request"]["lifecycleStage"] == "WAITING_APPROVAL", request["request"]
assert request["request"]["candidateActionCount"] == 2, request["request"]
assert request["request"]["willExecute"] is False, request["request"]

assert request["policyBinding"]["policyDecision"] == "REQUIRE_HUMAN_APPROVAL", request["policyBinding"]
assert request["policyBinding"]["requiresHumanApproval"] is True, request["policyBinding"]
assert request["policyBinding"]["stage32Required"] is True, request["policyBinding"]
assert request["policyBinding"]["policyBound"] is True, request["policyBinding"]
assert request["policyBinding"]["allowedToRequest"] is True, request["policyBinding"]
assert request["policyBinding"]["willExecute"] is False, request["policyBinding"]

assert request["approval"]["required"] is True, request["approval"]
assert request["approval"]["status"] == "NOT_APPROVED", request["approval"]
assert request["approval"]["approved"] is False, request["approval"]
assert request["approval"]["approvalDecision"] is None, request["approval"]
assert request["approval"]["readyToExecute"] is False, request["approval"]
assert request["approval"]["willExecuteAfterApproval"] is False, request["approval"]

assert request["evidence"]["planRun"] == str(plan_run_path), request["evidence"]
assert request["evidence"]["retrievedEvidenceCount"] == 2, request["evidence"]

assert request["guardrails"]["requestOnly"] is True, request["guardrails"]
assert request["guardrails"]["readOnly"] is True, request["guardrails"]
assert request["guardrails"]["willExecute"] is False, request["guardrails"]
assert request["guardrails"]["doesNotModifyKubernetes"] is True, request["guardrails"]
assert request["guardrails"]["doesNotModifyGitOps"] is True, request["guardrails"]
assert request["guardrails"]["doesNotRollback"] is True, request["guardrails"]
assert request["guardrails"]["doesNotPromote"] is True, request["guardrails"]
assert request["guardrails"]["doesNotPatchResources"] is True, request["guardrails"]
assert request["guardrails"]["doesNotDeleteResources"] is True, request["guardrails"]
assert request["guardrails"]["doesNotCommitOrPush"] is True, request["guardrails"]

print("PASS: execution request content")
PY

"$PYTHON_BIN" - "$EXECUTION_REQUEST" "$RELEASE_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
evidence = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert evidence["executionRequestId"] == request["executionRequestId"], evidence
assert evidence["artifacts"]["executionRequest"] == str(Path(sys.argv[1])), evidence["artifacts"]
assert evidence["decisionRefs"]["executionRequest"]["executionRequestId"] == request["executionRequestId"], evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["sourcePlanRunId"] == request["sourcePlanRunId"], evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["requestedAction"] == "STOP_PROMOTION", evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["requestStatus"] == "PENDING_APPROVAL", evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["lifecycleStage"] == "WAITING_APPROVAL", evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["requiresHumanApproval"] is True, evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["approved"] is False, evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["readyToExecute"] is False, evidence["decisionRefs"]["executionRequest"]
assert evidence["decisionRefs"]["executionRequest"]["willExecute"] is False, evidence["decisionRefs"]["executionRequest"]

print("PASS: release evidence includes policy-bound execution request link")
PY

echo "===== build evidence record with execution request link ====="

if ! EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP/evidence-record-out" \
  ./scripts/build-evidence-record.sh "$RELEASE_EVIDENCE" \
  >"$TEST_TMP/evidence-record.log" 2>&1; then
  cat "$TEST_TMP/evidence-record.log" || true
  echo "FAILED: build-evidence-record.sh failed" >&2
  exit 1
fi

cat "$TEST_TMP/evidence-record.log"

EVIDENCE_RECORD="$TEST_TMP/evidence-record-out/evidence-record-20260521-320100.json"

if [ ! -f "$EVIDENCE_RECORD" ]; then
  echo "WARN: expected evidence record not found, fallback to latest"
  EVIDENCE_RECORD="$TEST_TMP/evidence-record-out/evidence-record-latest.json"
fi

[ -f "$EVIDENCE_RECORD" ] || { echo "FAILED: evidence record not generated" >&2; exit 1; }

"$PYTHON_BIN" scripts/validate-release-contracts.py "$EVIDENCE_RECORD"

"$PYTHON_BIN" - "$EVIDENCE_RECORD" "$EXECUTION_REQUEST" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
execution_request_path = Path(sys.argv[2])

assert record["executionRequest"]["executionRequestId"] == "er-20260521-320100", record["executionRequest"]
assert record["executionRequest"]["mode"] == "request_only", record["executionRequest"]
assert record["executionRequest"]["sourcePlanRunId"] == "pr-20260521-320100", record["executionRequest"]
assert record["executionRequest"]["requestedAction"] == "STOP_PROMOTION", record["executionRequest"]
assert record["executionRequest"]["requestStatus"] == "PENDING_APPROVAL", record["executionRequest"]
assert record["executionRequest"]["lifecycleStage"] == "WAITING_APPROVAL", record["executionRequest"]
assert record["executionRequest"]["requestedBy"] == "test-agent-planner", record["executionRequest"]
assert record["executionRequest"]["policyDecision"] == "REQUIRE_HUMAN_APPROVAL", record["executionRequest"]
assert record["executionRequest"]["requiresHumanApproval"] is True, record["executionRequest"]
assert record["executionRequest"]["approvalStatus"] == "NOT_APPROVED", record["executionRequest"]
assert record["executionRequest"]["approved"] is False, record["executionRequest"]
assert record["executionRequest"]["approvalDecision"] is None, record["executionRequest"]
assert record["executionRequest"]["readyToExecute"] is False, record["executionRequest"]
assert record["executionRequest"]["willExecute"] is False, record["executionRequest"]
assert record["executionRequest"]["sourceExecutionRequest"] == str(execution_request_path), record["executionRequest"]
assert record["links"]["executionRequest"] == str(execution_request_path), record["links"]

print("PASS: evidence record includes policy-bound execution request link")
PY

echo "PASS: execution request test passed"
