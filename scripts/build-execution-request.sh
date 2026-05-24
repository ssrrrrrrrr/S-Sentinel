#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-}"
PLAN_RUN_FILE="${1:-latest}"

if [ -z "$REPORT_DIR" ]; then
  if [ -d "/data/nfs/slo-rollout-watcher/reports" ]; then
    REPORT_DIR="/data/nfs/slo-rollout-watcher/reports"
  else
    REPORT_DIR="docs/release-reports"
  fi
fi

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-execution-request.sh [latest|PLAN_RUN_JSON]

Environment:
  RELEASE_REPORT_DIR              Optional report directory.
  EXECUTION_REQUEST_OUTPUT_DIR    Optional output directory. Defaults to plan run directory.
  REQUESTED_BY                    Optional requester. Defaults to read-only-agent-planner.

Behavior:
  - Reads a read-only plan-run JSON.
  - Generates execution-request-*.json and execution-request-latest.json.
  - Creates a policy-bound execution request record.
  - Does not approve or execute the request.
  - Does not modify Kubernetes, GitOps, Rollouts, Deployments, images, commits, or pushes.
USAGE
}

if [ "${PLAN_RUN_FILE:-}" = "-h" ] || [ "${PLAN_RUN_FILE:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ "$PLAN_RUN_FILE" = "latest" ] || [ -z "$PLAN_RUN_FILE" ]; then
  PLAN_RUN_FILE="$(ls -t "$REPORT_DIR"/plan-run-*.json 2>/dev/null | grep -v 'plan-run-latest.json' | head -1 || true)"
fi

if [ -z "$PLAN_RUN_FILE" ] || [ ! -f "$PLAN_RUN_FILE" ]; then
  echo "ERROR: plan run file does not exist: ${PLAN_RUN_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$PLAN_RUN_FILE")"
SUFFIX="${BASENAME#plan-run-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_DIR="${EXECUTION_REQUEST_OUTPUT_DIR:-$(dirname "$PLAN_RUN_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="$OUTPUT_DIR/execution-request-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/execution-request-latest.json"
REQUESTED_BY="${REQUESTED_BY:-read-only-agent-planner}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

validate_generated_release_contract() {
  local contract_file="${1:-}"
  local helper="${RELEASE_CONTRACT_VALIDATOR_HELPER:-$SCRIPT_DIR/validate-generated-release-contract.sh}"

  if [ "${RELEASE_CONTRACT_VALIDATION_MODE:-warn}" = "off" ]; then
    return 0
  fi

  if [ -f "$helper" ]; then
    bash "$helper" "$contract_file"
  else
    echo "WARN: release contract validator helper not found: $helper" >&2
  fi
}

python3 - "$PLAN_RUN_FILE" "$OUTPUT_JSON" "$LATEST_JSON" "$REQUESTED_BY" <<'PY_EXEC_REQ'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

plan_run_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
latest_json = Path(sys.argv[3])
requested_by = sys.argv[4] or "read-only-agent-planner"

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return data if isinstance(data, dict) else {}

def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}

def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]

def nullable_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None

def first_candidate_action(candidate_actions: list[Any]) -> dict[str, Any]:
    for item in candidate_actions:
        if not isinstance(item, dict):
            continue
        action = item.get("action")
        if action:
            return item
    return {}

def derive_request_status(
    release_result: str,
    requested_action: str,
    policy_decision: str | None,
    requires_human_approval: bool,
    candidate: dict[str, Any],
) -> str:
    if not requested_action or requested_action in {"NONE", "NOOP"}:
        return "NO_ACTION_REQUESTED"

    if str(policy_decision or "").upper() == "DENY":
        return "BLOCKED_BY_POLICY"

    if candidate.get("requiresStage32ExecutionRequest") is not True:
        return "NEEDS_MORE_EVIDENCE"

    if requires_human_approval or str(release_result).startswith("FAIL"):
        return "PENDING_APPROVAL"

    return "PENDING_APPROVAL"

def derive_lifecycle_stage(
    request_status: str,
    requires_human_approval: bool,
    allowed_to_request: bool,
) -> str:
    if request_status == "NO_ACTION_REQUESTED":
        return "NO_ACTION_REQUESTED"
    if request_status == "BLOCKED_BY_POLICY":
        return "BLOCKED_BY_POLICY"
    if request_status == "NEEDS_MORE_EVIDENCE":
        return "NEEDS_MORE_EVIDENCE"
    if requires_human_approval:
        return "WAITING_APPROVAL"
    if allowed_to_request:
        return "READY_TO_EXECUTE"
    return "POLICY_CHECKED"

plan_run = load_json(plan_run_path)

release = as_dict(plan_run.get("release"))
plan = as_dict(plan_run.get("plan"))
inputs = as_dict(plan_run.get("inputs"))
retrieval = as_dict(plan_run.get("retrieval"))
retrieval_summary = as_dict(retrieval.get("summary"))
guardrails = as_dict(plan_run.get("guardrails"))

candidate_actions = [item for item in as_list(plan.get("candidateFollowUpActions")) if isinstance(item, dict)]
candidate = first_candidate_action(candidate_actions)

release_id = str(release.get("releaseId") or plan_run_path.stem)
release_result = str(release.get("releaseResult") or "UNKNOWN")
policy_decision = nullable_string(release.get("policyDecision"))
recommended_action = nullable_string(release.get("recommendedAction"))

requested_action = str(candidate.get("action") or recommended_action or "NOOP")
candidate_requires_stage32 = bool(candidate.get("requiresStage32ExecutionRequest", False))
candidate_requires_approval = bool(candidate.get("requiresHumanApproval", False))

blocking_reasons: list[str] = []

if guardrails.get("willExecute") is not False:
    blocking_reasons.append("source_plan_guardrail_does_not_confirm_non_execution")

if plan.get("willExecute") is not False:
    blocking_reasons.append("source_plan_may_execute")

if not candidate_actions and requested_action not in {"NOOP", "NONE"}:
    blocking_reasons.append("no_candidate_follow_up_action_found")

if policy_decision == "DENY":
    blocking_reasons.append("source_policy_decision_denied")

requires_human_approval = bool(
    candidate_requires_approval
    or str(policy_decision or "").upper() == "REQUIRE_HUMAN_APPROVAL"
    or str(release_result).startswith("FAIL")
)

request_status = derive_request_status(
    release_result,
    requested_action,
    policy_decision,
    requires_human_approval,
    candidate,
)

allowed_to_request = not blocking_reasons and request_status != "BLOCKED_BY_POLICY"
lifecycle_stage = derive_lifecycle_stage(
    request_status,
    requires_human_approval,
    allowed_to_request,
)
approval_status = "NOT_APPROVED" if requires_human_approval else "NOT_REQUIRED"
ready_to_execute = lifecycle_stage == "READY_TO_EXECUTE"

execution_request_id = "er-" + release_id

execution_request = {
    "schemaVersion": "execution.request/v1alpha1",
    "executionRequestId": execution_request_id,
    "generatedBy": "build-execution-request.sh",
    "generatedAt": now(),
    "mode": "request_only",
    "sourcePlanRunId": str(plan_run.get("planRunId") or ""),
    "release": {
        "releaseId": release_id,
        "service": release.get("service"),
        "env": release.get("env"),
        "namespace": release.get("namespace"),
        "version": release.get("version"),
        "commit": release.get("commit"),
        "imageDigest": release.get("imageDigest"),
        "releaseResult": release_result,
        "policyDecision": policy_decision,
        "failedMetrics": [str(item) for item in as_list(release.get("failedMetrics"))],
    },
    "request": {
        "requestedBy": requested_by,
        "requestedAction": requested_action,
        "requestReason": candidate.get("reason") or plan.get("summary") or "Generated from read-only plan run.",
        "requestStatus": request_status,
        "lifecycleStage": lifecycle_stage,
        "candidateActionCount": len(candidate_actions),
        "candidateActions": candidate_actions,
        "willExecute": False,
    },
    "policyBinding": {
        "policyDecision": policy_decision,
        "recommendedAction": recommended_action,
        "requiresHumanApproval": requires_human_approval,
        "stage32Required": candidate_requires_stage32,
        "policyBound": True,
        "allowedToRequest": allowed_to_request,
        "willExecute": False,
        "blockingReasons": blocking_reasons,
    },
    "approval": {
        "required": requires_human_approval,
        "status": approval_status,
        "approved": False,
        "approvalDecision": None,
        "approver": None,
        "reason": None,
        "updatedAt": None,
        "readyToExecute": ready_to_execute,
        "willExecuteAfterApproval": False,
    },
    "evidence": {
        "planRun": str(plan_run_path),
        "agentRun": inputs.get("agentRun"),
        "releaseEvidence": inputs.get("releaseEvidence"),
        "releaseIntelligence": inputs.get("releaseIntelligence"),
        "releaseMemory": inputs.get("releaseMemory"),
        "approvalRecord": None,
        "approvalRecordReport": None,
        "retrievedEvidenceCount": retrieval_summary.get("retrievedEvidenceCount"),
        "artifacts": as_dict(inputs.get("artifacts")),
    },
    "guardrails": {
        "requestOnly": True,
        "readOnly": True,
        "willExecute": False,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotRollback": True,
        "doesNotPromote": True,
        "doesNotPatchResources": True,
        "doesNotDeleteResources": True,
        "doesNotBuildImages": True,
        "doesNotCommitOrPush": True,
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(execution_request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Execution request generated: {output_json}")
print(f"Latest execution request: {latest_json}")
print(json.dumps({
    "executionRequestId": execution_request["executionRequestId"],
    "sourcePlanRunId": execution_request["sourcePlanRunId"],
    "releaseId": release_id,
    "releaseResult": release_result,
    "requestedAction": requested_action,
    "requestStatus": request_status,
    "lifecycleStage": lifecycle_stage,
    "requiresHumanApproval": requires_human_approval,
    "approvalStatus": approval_status,
    "readyToExecute": ready_to_execute,
    "mode": execution_request["mode"],
    "willExecute": execution_request["guardrails"]["willExecute"],
}, ensure_ascii=False, indent=2))
PY_EXEC_REQ

validate_generated_release_contract "$OUTPUT_JSON"

python3 - "$OUTPUT_JSON" <<'PY_EXEC_REQ_LINK'
import json
import sys
from pathlib import Path

execution_request_path = Path(sys.argv[1])
execution_request = json.loads(execution_request_path.read_text(encoding="utf-8-sig"))

evidence_ref = (execution_request.get("evidence") or {}).get("releaseEvidence")
if not evidence_ref:
    print("WARN: execution request has no release evidence ref, skip linking", file=sys.stderr)
    raise SystemExit(0)

evidence_path = Path(str(evidence_ref))
candidates = []

if evidence_path.is_absolute():
    candidates.append(evidence_path)

candidates.append(execution_request_path.parent / evidence_path.name)
candidates.append(evidence_path)

resolved = None
for candidate in candidates:
    if candidate.exists() and candidate.is_file():
        resolved = candidate
        break

if not resolved:
    print(f"WARN: release evidence file not found, skip linking execution request: {evidence_ref}", file=sys.stderr)
    raise SystemExit(0)

evidence = json.loads(resolved.read_text(encoding="utf-8-sig"))

request = execution_request.get("request") or {}
policy_binding = execution_request.get("policyBinding") or {}
approval = execution_request.get("approval") or {}

artifacts = evidence.setdefault("artifacts", {})
artifacts["executionRequest"] = str(execution_request_path)

evidence["executionRequestId"] = execution_request.get("executionRequestId")

decision_refs = evidence.setdefault("decisionRefs", {})
decision_refs["executionRequest"] = {
    "executionRequestId": execution_request.get("executionRequestId"),
    "sourcePlanRunId": execution_request.get("sourcePlanRunId"),
    "mode": execution_request.get("mode"),
    "requestedAction": request.get("requestedAction"),
    "requestStatus": request.get("requestStatus"),
    "lifecycleStage": request.get("lifecycleStage"),
    "policyDecision": policy_binding.get("policyDecision"),
    "requiresHumanApproval": policy_binding.get("requiresHumanApproval"),
    "approvalStatus": approval.get("status"),
    "approved": approval.get("approved"),
    "approvalDecision": approval.get("approvalDecision"),
    "readyToExecute": approval.get("readyToExecute"),
    "willExecute": execution_request.get("guardrails", {}).get("willExecute"),
    "guardrails": execution_request.get("guardrails") or {},
}

resolved.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Execution request linked into release evidence: {resolved}")
PY_EXEC_REQ_LINK

if [ -n "${RELEASE_CONTRACT_VALIDATION_MODE:-warn}" ] && [ "${RELEASE_CONTRACT_VALIDATION_MODE:-warn}" != "off" ]; then
  true
fi

cat "$OUTPUT_JSON"
