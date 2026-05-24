#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-execution-eligibility-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run execution eligibility test ====="

create_release_evidence() {
  local case_name="$1"
  cat > "$TEST_TMP/release-evidence-$case_name.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-execution-eligibility.sh",
  "generatedAt": "2026-05-24T00:00:00Z",
  "releaseId": "$case_name",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "summary": {
    "riskLevel": "critical",
    "riskScore": 100,
    "failedMetrics": ["error-rate", "p95-latency"]
  },
  "artifacts": {
    "executionRequest": "$TEST_TMP/execution-request-$case_name.json",
    "supplyChainDecision": "$TEST_TMP/supply-chain-decision-$case_name.json"
  }
}
JSON
}

create_execution_request() {
  local case_name="$1"
  local approval_status="$2"
  local approval_decision="$3"
  local approved="$4"
  local ready="$5"
  local lifecycle="$6"
  local reason="$7"
  cat > "$TEST_TMP/execution-request-$case_name.json" <<JSON
{
  "schemaVersion": "execution.request/v1alpha1",
  "executionRequestId": "er-$case_name",
  "generatedBy": "test-execution-eligibility.sh",
  "generatedAt": "2026-05-24T00:00:00Z",
  "mode": "request_only",
  "sourcePlanRunId": "pr-$case_name",
  "release": {
    "releaseId": "$case_name",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "releaseResult": "FAIL_BY_MULTIPLE_SLO",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL"
  },
  "request": {
    "requestedBy": "test-agent-planner",
    "requestedAction": "STOP_PROMOTION",
    "requestReason": "fixture",
    "requestStatus": "PENDING_APPROVAL",
    "lifecycleStage": "$lifecycle",
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
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
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
    "status": "$approval_status",
    "approved": $approved,
    "approvalDecision": $approval_decision,
    "approver": null,
    "reason": $reason,
    "updatedAt": null,
    "readyToExecute": $ready,
    "willExecuteAfterApproval": false
  },
  "evidence": {
    "releaseEvidence": "$TEST_TMP/release-evidence-$case_name.json",
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
}

create_supply_chain_decision() {
  local case_name="$1"
  local decision="$2"
  local allowed="$3"
  local requires_approval="$4"
  local blocking_reasons="$5"
  local warning_reasons="$6"
  cat > "$TEST_TMP/supply-chain-decision-$case_name.json" <<JSON
{
  "schemaVersion": "supply.chain.decision/v1alpha1",
  "supplyChainDecisionId": "sc-$case_name",
  "generatedBy": "test-execution-eligibility.sh",
  "generatedAt": "2026-05-24T00:00:00Z",
  "mode": "read_only_supply_chain_check",
  "release": {
    "releaseId": "$case_name",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout"
  },
  "image": {
    "image": "registry.local/demo-app:v-test",
    "imageTag": "v-test",
    "imageDigest": null
  },
  "gitops": {
    "manifest": "deploy/base/rollout.yaml",
    "manifestFound": true
  },
  "checks": [],
  "decision": {
    "decision": "$decision",
    "requiresHumanApproval": $requires_approval,
    "allowed": $allowed,
    "blockingReasons": $blocking_reasons,
    "warningReasons": $warning_reasons
  },
  "risk": {
    "riskLevel": "medium",
    "riskScore": 25
  },
  "guardrails": {
    "readOnly": true,
    "willExecute": false,
    "doesNotModifyKubernetes": true,
    "doesNotModifyGitOps": true,
    "doesNotBuildImages": true,
    "doesNotPushImages": true,
    "doesNotCommitOrPush": true
  }
}
JSON
}

create_release_evidence "waiting-approval"
create_execution_request "waiting-approval" "NOT_APPROVED" "null" "false" "false" "WAITING_APPROVAL" "null"
create_supply_chain_decision "waiting-approval" "ALLOW" "true" "false" "[]" "[]"

create_release_evidence "ready-to-execute"
create_execution_request "ready-to-execute" "APPROVED" "\"APPROVED\"" "true" "true" "READY_TO_EXECUTE" "\"approved by human gate\""
create_supply_chain_decision "ready-to-execute" "ALLOW" "true" "false" "[]" "[]"

create_release_evidence "blocked"
create_execution_request "blocked" "NOT_APPROVED" "null" "false" "false" "WAITING_APPROVAL" "null"
create_supply_chain_decision "blocked" "BLOCK" "false" "true" "[\"image digest mismatch\"]" "[]"

for case_name in waiting-approval ready-to-execute blocked; do
  echo
  echo "===== build eligibility: $case_name ====="
  EXECUTION_ELIGIBILITY_OUTPUT_DIR="$TEST_TMP/out-$case_name" \
    ./scripts/build-execution-eligibility.sh "$TEST_TMP/release-evidence-$case_name.json" \
    >"$TEST_TMP/$case_name.log" 2>&1
  cat "$TEST_TMP/$case_name.log"
done

python3 - "$TEST_TMP" <<'PY'
import json
import os
import sys
from shutil import which
from pathlib import Path

root = Path(sys.argv[1])

expectations = {
    "waiting-approval": {
        "finalStatus": "WAITING_APPROVAL",
        "readyToExecute": False,
        "approvalReason": "human_approval_required",
    },
    "ready-to-execute": {
        "finalStatus": "READY_TO_EXECUTE",
        "readyToExecute": True,
        "approvalReason": None,
    },
    "blocked": {
        "finalStatus": "BLOCKED",
        "readyToExecute": False,
        "blockingReason": "image digest mismatch",
    },
}

for case_name, expected in expectations.items():
    eligibility_path = root / f"out-{case_name}" / f"execution-eligibility-{case_name}.json"
    evidence_path = root / f"release-evidence-{case_name}.json"

    eligibility = json.loads(eligibility_path.read_text(encoding="utf-8"))
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))

    assert eligibility["decision"]["finalStatus"] == expected["finalStatus"], eligibility
    assert eligibility["decision"]["readyToExecute"] is expected["readyToExecute"], eligibility
    assert evidence["executionEligibilityId"] == eligibility["eligibilityDecisionId"], evidence
    assert evidence["artifacts"]["executionEligibility"] == str(eligibility_path), evidence["artifacts"]
    assert evidence["decisionRefs"]["executionEligibility"]["finalStatus"] == expected["finalStatus"], evidence["decisionRefs"]["executionEligibility"]

    if expected.get("approvalReason"):
        assert expected["approvalReason"] in eligibility["decision"]["approvalReasons"], eligibility["decision"]
    if expected.get("blockingReason"):
        assert expected["blockingReason"] in eligibility["decision"]["blockingReasons"], eligibility["decision"]

ready_evidence = root / "release-evidence-ready-to-execute.json"
record_dir = Path.cwd() / "record-ready"
record_dir.mkdir(exist_ok=True)
record_dir_env = "record-ready"

import subprocess
bash_bin = os.environ.get("S_SENTINEL_BASH_BIN") or which("bash") or which("sh") or r"D:\Git\bin\bash.exe"
subprocess.run(
    [bash_bin, "./scripts/build-evidence-record.sh", str(ready_evidence)],
    cwd=Path.cwd(),
    check=True,
    env={**os.environ, "EVIDENCE_RECORD_OUTPUT_DIR": record_dir_env},
)

record = json.loads((record_dir / "evidence-record-ready-to-execute.json").read_text(encoding="utf-8"))
eligibility = record["executionEligibility"]
assert eligibility["finalStatus"] == "READY_TO_EXECUTE", eligibility
assert eligibility["readyToExecute"] is True, eligibility
assert eligibility["sourceExecutionEligibility"].endswith("execution-eligibility-ready-to-execute.json"), eligibility

print("PASS: execution eligibility test passed")
PY
