#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-execution-eligibility.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                   Optional report directory.
  EXECUTION_ELIGIBILITY_OUTPUT_DIR     Optional output directory.
  EXECUTION_ELIGIBILITY_OUTPUT_FILE    Optional exact output file.

Behavior:
  - Reads release evidence and related execution / approval / supply-chain artifacts.
  - Generates execution-eligibility-*.json and execution-eligibility-latest.json.
  - Produces a read-only execution eligibility decision.
  - Does not execute, rollback, promote, patch, delete, build, commit, or push.
USAGE
}

if [ "${INPUT_FILE:-}" = "-h" ] || [ "${INPUT_FILE:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ "$INPUT_FILE" = "latest" ] || [ -z "$INPUT_FILE" ]; then
  INPUT_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | grep -v 'release-evidence-latest.json' | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: input file does not exist: ${INPUT_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_DIR="${EXECUTION_ELIGIBILITY_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${EXECUTION_ELIGIBILITY_OUTPUT_FILE:-$OUTPUT_DIR/execution-eligibility-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/execution-eligibility-latest.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_EXEC_ELIGIBILITY'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

input_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
latest_json = Path(sys.argv[3])


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path | None) -> dict[str, Any]:
    if not path or not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


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


def first_not_none(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None


def unique_strings(values: list[Any]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for item in values:
        text = nullable_string(item)
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result


def resolve_ref(ref: Any, source_path: Path) -> Path | None:
    if not ref:
        return None
    raw = Path(str(ref))
    candidates: list[Path] = []
    if raw.is_absolute():
        candidates.append(raw)
    candidates.extend([
        source_path.parent / raw,
        source_path.parent / raw.name,
        Path.cwd() / raw,
        raw,
    ])
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate)
        if key in seen:
            continue
        seen.add(key)
        try:
            if candidate.exists() and candidate.is_file():
                return candidate
        except OSError:
            continue
    return None


def release_id_from_path(path: Path) -> str:
    name = path.name
    prefix = "release-evidence-"
    if name.startswith(prefix) and name.endswith(".json"):
        return name[len(prefix):-len(".json")]
    return path.stem


def summarize_status(
    final_status: str,
    requested_action: str | None,
    blocking_reasons: list[str],
    approval_reasons: list[str],
    missing_inputs: list[str],
) -> str:
    action = requested_action or "UNKNOWN"
    if final_status == "READY_TO_EXECUTE":
        return f"Execution request for {action} is ready for a controlled executor."
    if final_status == "WAITING_APPROVAL":
        return f"Execution request for {action} is waiting for human approval."
    if final_status == "BLOCKED":
        reason = blocking_reasons[0] if blocking_reasons else "blocking guardrail present"
        return f"Execution request for {action} is blocked: {reason}."
    if final_status == "NO_ACTION_REQUIRED":
        return "No action has been requested for this release."
    reason = (missing_inputs or approval_reasons or blocking_reasons or ["more evidence is required"])[0]
    return f"Execution eligibility is incomplete: {reason}."


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
decision_refs = as_dict(evidence.get("decisionRefs"))

execution_request_path = resolve_ref(artifacts.get("executionRequest"), input_path)
approval_record_path = resolve_ref(first_not_none(
    artifacts.get("approvalRecord"),
    as_dict(decision_refs.get("executionRequest")).get("approvalRecord"),
), input_path)
supply_chain_path = resolve_ref(artifacts.get("supplyChainDecision"), input_path)
signed_gate_path = resolve_ref(artifacts.get("signedReleaseGate"), input_path)
policy_decision_path = resolve_ref(artifacts.get("policyDecision"), input_path)

execution_request = load_json(execution_request_path)
approval_record = load_json(approval_record_path)
supply_chain = load_json(supply_chain_path)
signed_gate = load_json(signed_gate_path)
policy_decision_doc = load_json(policy_decision_path)

release = as_dict(execution_request.get("release")) or as_dict(evidence.get("release"))
request = as_dict(execution_request.get("request"))
policy_binding = as_dict(execution_request.get("policyBinding"))
approval = as_dict(execution_request.get("approval"))
supply_chain_decision = as_dict(supply_chain.get("decision"))
signed_gate_decision = as_dict(signed_gate.get("decision"))
signed_gate_verification = as_dict(signed_gate.get("verification"))

release_id = nullable_string(first_not_none(
    execution_request.get("release", {}).get("releaseId") if isinstance(execution_request.get("release"), dict) else None,
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

requested_action = nullable_string(first_not_none(
    request.get("requestedAction"),
    evidence.get("finalAction"),
))
request_status = nullable_string(request.get("requestStatus"))
lifecycle_stage = nullable_string(request.get("lifecycleStage"))
policy_decision = nullable_string(first_not_none(
    policy_binding.get("policyDecision"),
    evidence.get("policyDecision"),
    policy_decision_doc.get("policyDecision"),
))

approval_required = bool(first_not_none(
    approval.get("required"),
    policy_binding.get("requiresHumanApproval"),
    evidence.get("requiresHumanApproval"),
    False,
))
approval_status = nullable_string(approval.get("status"))
approval_decision = nullable_string(first_not_none(
    approval.get("approvalDecision"),
    approval_record.get("approvalDecision"),
))
approved = bool(first_not_none(
    approval.get("approved"),
    approval_record.get("approvalDecision") == "APPROVED" if approval_record else False,
    False,
))
approval_ready = bool(first_not_none(approval.get("readyToExecute"), False))
approver = nullable_string(first_not_none(approval.get("approver"), approval_record.get("approver")))
approval_reason = nullable_string(first_not_none(approval.get("reason"), approval_record.get("reason")))
approval_satisfied = approved or approval_ready or approval_status == "APPROVED" or approval_decision == "APPROVED"

blocking_reasons: list[str] = []
approval_reasons: list[str] = []
missing_inputs: list[str] = []

if not execution_request:
    missing_inputs.append("execution_request_missing")

if requested_action in (None, "", "NONE", "NOOP"):
    final_status = "NO_ACTION_REQUIRED"
else:
    if request_status == "BLOCKED_BY_POLICY" or str(policy_decision or "").upper() == "DENY":
        blocking_reasons.append("policy_denied_execution_request")

    if request_status == "NEEDS_MORE_EVIDENCE" or lifecycle_stage == "NEEDS_MORE_EVIDENCE":
        missing_inputs.append("execution_request_needs_more_evidence")

    if not supply_chain:
        missing_inputs.append("supply_chain_decision_missing")
    elif supply_chain_decision.get("decision") == "BLOCK" or supply_chain_decision.get("allowed") is False:
        blocking_reasons.extend(unique_strings(
            as_list(supply_chain_decision.get("blockingReasons")) or ["supply_chain_decision_blocked"]
        ))
    elif supply_chain_decision.get("requiresHumanApproval") is True and not approval_satisfied:
        approval_reasons.extend(unique_strings(
            as_list(supply_chain_decision.get("warningReasons")) or ["supply_chain_requires_human_approval"]
        ))

    if signed_gate:
        if signed_gate_decision.get("decision") == "BLOCK" or signed_gate_decision.get("allowed") is False:
            blocking_reasons.extend(unique_strings(
                as_list(signed_gate_decision.get("blockingReasons")) or ["signed_release_gate_blocked"]
            ))
        elif signed_gate_decision.get("requiresHumanApproval") is True and not approval_satisfied:
            approval_reasons.extend(unique_strings(
                as_list(signed_gate_decision.get("warningReasons")) or ["signed_release_gate_requires_human_approval"]
            ))

    if approval_required:
        if approval_satisfied:
            pass
        elif approval_status in {"REJECTED"} or approval_decision == "REJECTED":
            blocking_reasons.append("human_approval_rejected")
        elif approval_status == "DEFERRED" or approval_decision == "DEFERRED":
            approval_reasons.append("human_approval_deferred")
        elif approval_status == "NEEDS_MORE_EVIDENCE" or approval_decision == "NEEDS_MORE_EVIDENCE":
            missing_inputs.append("human_approval_requested_more_evidence")
        else:
            approval_reasons.append("human_approval_required")

    if blocking_reasons:
        final_status = "BLOCKED"
    elif missing_inputs:
        final_status = "NEEDS_MORE_EVIDENCE"
    elif approval_reasons:
        final_status = "WAITING_APPROVAL"
    else:
        final_status = "READY_TO_EXECUTE"

decision = {
    "schemaVersion": "execution.eligibility/v1alpha1",
    "eligibilityDecisionId": f"el-{release_id}",
    "generatedBy": "build-execution-eligibility.sh",
    "generatedAt": now(),
    "mode": "read_only_eligibility_assessment",
    "release": {
      "releaseId": release_id,
      "service": first_not_none(evidence.get("service"), release.get("service")),
      "env": first_not_none(evidence.get("env"), release.get("env")),
      "namespace": first_not_none(evidence.get("namespace"), release.get("namespace")),
      "version": release.get("version"),
      "commit": release.get("commit"),
      "releaseResult": first_not_none(evidence.get("releaseResult"), release.get("releaseResult")),
      "policyDecision": policy_decision,
      "finalAction": first_not_none(evidence.get("finalAction"), requested_action),
    },
    "inputs": {
      "releaseEvidence": str(input_path),
      "executionRequest": str(execution_request_path) if execution_request_path else None,
      "approvalRecord": str(approval_record_path) if approval_record_path else None,
      "approvalRecordReport": first_not_none(
          artifacts.get("approvalRecordReport"),
          as_dict(decision_refs.get("executionRequest")).get("approvalRecordReport"),
      ),
      "supplyChainDecision": str(supply_chain_path) if supply_chain_path else None,
      "signedReleaseGate": str(signed_gate_path) if signed_gate_path else None,
      "policyDecision": str(policy_decision_path) if policy_decision_path else None,
    },
    "executionRequest": {
      "executionRequestId": execution_request.get("executionRequestId"),
      "requestedAction": requested_action,
      "requestStatus": request_status,
      "lifecycleStage": lifecycle_stage,
      "requiresHumanApproval": policy_binding.get("requiresHumanApproval"),
    },
    "approval": {
      "required": approval_required,
      "status": approval_status,
      "approvalDecision": approval_decision,
      "approved": approved,
      "readyToExecute": approved or approval_ready,
      "approver": approver,
      "reason": approval_reason,
    },
    "supplyChain": {
      "supplyChainDecisionId": supply_chain.get("supplyChainDecisionId"),
      "decision": supply_chain_decision.get("decision"),
      "allowed": supply_chain_decision.get("allowed"),
      "requiresHumanApproval": supply_chain_decision.get("requiresHumanApproval"),
      "riskLevel": as_dict(supply_chain.get("risk")).get("riskLevel"),
      "riskScore": as_dict(supply_chain.get("risk")).get("riskScore"),
      "blockingReasons": unique_strings(as_list(supply_chain_decision.get("blockingReasons"))),
      "warningReasons": unique_strings(as_list(supply_chain_decision.get("warningReasons"))),
    },
    "signedReleaseGate": {
      "signedReleaseGateId": signed_gate.get("signedReleaseGateId"),
      "decision": signed_gate_decision.get("decision"),
      "allowed": signed_gate_decision.get("allowed"),
      "requiresHumanApproval": signed_gate_decision.get("requiresHumanApproval"),
      "verificationStatus": first_not_none(
          signed_gate_verification.get("verificationStatus"),
          as_dict(signed_gate_verification.get("results")).get("verificationStatus"),
      ),
      "blockingReasons": unique_strings(as_list(signed_gate_decision.get("blockingReasons"))),
      "warningReasons": unique_strings(as_list(signed_gate_decision.get("warningReasons"))),
    },
    "decision": {
      "finalStatus": final_status,
      "readyToExecute": final_status == "READY_TO_EXECUTE",
      "blockingReasons": unique_strings(blocking_reasons),
      "approvalReasons": unique_strings(approval_reasons),
      "missingInputs": unique_strings(missing_inputs),
      "summary": summarize_status(
          final_status,
          requested_action,
          unique_strings(blocking_reasons),
          unique_strings(approval_reasons),
          unique_strings(missing_inputs),
      ),
    },
    "guardrails": {
      "readOnly": True,
      "willExecute": False,
      "requestOnly": True,
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
output_json.write_text(json.dumps(decision, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

release_evidence = evidence
artifacts = release_evidence.setdefault("artifacts", {})
artifacts["executionEligibility"] = str(output_json)

release_evidence["executionEligibilityId"] = decision["eligibilityDecisionId"]
release_evidence["executionEligibilityRef"] = {
    "json": str(output_json),
    "finalStatus": decision["decision"]["finalStatus"],
    "readyToExecute": decision["decision"]["readyToExecute"],
}

decision_refs = release_evidence.setdefault("decisionRefs", {})
decision_refs["executionEligibility"] = {
    "eligibilityDecisionId": decision["eligibilityDecisionId"],
    "finalStatus": decision["decision"]["finalStatus"],
    "readyToExecute": decision["decision"]["readyToExecute"],
    "requestedAction": requested_action,
    "requestStatus": request_status,
    "lifecycleStage": lifecycle_stage,
    "approvalStatus": approval_status,
    "approvalDecision": approval_decision,
    "approver": approver,
    "supplyChainDecision": supply_chain_decision.get("decision"),
    "signedReleaseGateDecision": signed_gate_decision.get("decision"),
    "blockingReasons": decision["decision"]["blockingReasons"],
    "approvalReasons": decision["decision"]["approvalReasons"],
    "missingInputs": decision["decision"]["missingInputs"],
    "source": str(output_json),
}

input_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Execution eligibility generated: {output_json}")
print(f"Latest execution eligibility: {latest_json}")
print(f"Execution eligibility linked into release evidence: {input_path}")
print(json.dumps({
    "eligibilityDecisionId": decision["eligibilityDecisionId"],
    "releaseId": release_id,
    "finalStatus": decision["decision"]["finalStatus"],
    "readyToExecute": decision["decision"]["readyToExecute"],
    "requestedAction": requested_action,
    "blockingReasonCount": len(decision["decision"]["blockingReasons"]),
    "approvalReasonCount": len(decision["decision"]["approvalReasons"]),
    "missingInputCount": len(decision["decision"]["missingInputs"]),
}, ensure_ascii=False, indent=2))
PY_EXEC_ELIGIBILITY

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
