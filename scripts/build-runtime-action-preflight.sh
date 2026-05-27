#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"
OUTPUT_DIR="${RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-runtime-action-preflight.sh [latest|RUNTIME_ACTION_REQUEST_JSON]

Environment:
  RELEASE_REPORT_DIR                    Optional report directory.
  RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR    Optional output directory.

Behavior:
  - Reads runtime-action-request-*.json.
  - Generates runtime-action-preflight-*.json and runtime-action-preflight-latest.json.
  - Produces a read-only runtime action preflight / eligibility assessment.
  - Does not execute pause, resume, promote, abort, rollback, kubectl mutation, GitOps write, commit, or push.
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
  INPUT_FILE="$(ls -t "$REPORT_DIR"/runtime-action-request-*.json 2>/dev/null | grep -v 'runtime-action-request-latest.json' | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: runtime action request file does not exist: ${INPUT_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
SUFFIX="${BASENAME#runtime-action-request-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$(dirname "$INPUT_FILE")"
fi
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="$OUTPUT_DIR/runtime-action-preflight-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/runtime-action-preflight-latest.json"

python3 - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY'
from __future__ import annotations

import json
import os
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

def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return data if isinstance(data, dict) else {}

def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}

def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]

def first_not_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None

def unique_strings(values: list[Any]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for item in values:
        if item is None:
            continue
        text = str(item).strip()
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result

def bool_value(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    return default

def env_enabled(name: str) -> bool:
    return str(os.environ.get(name, "")).strip().lower() in {"1", "true", "yes", "y", "on"}

request_doc = load_json(input_path)
release = as_dict(request_doc.get("release"))
target = as_dict(request_doc.get("target"))
request_body = as_dict(request_doc.get("request"))
binding = as_dict(request_doc.get("recommendationBinding"))
approval = as_dict(request_doc.get("approval"))
snapshot = as_dict(request_doc.get("runtimeSnapshot"))
evidence_refs = as_dict(request_doc.get("evidenceRefs"))
guardrails = as_dict(request_doc.get("guardrails"))
rollback_target = as_dict(request_doc.get("rollbackTarget"))

release_id = str(first_not_empty(
    release.get("releaseId"),
    input_path.stem.replace("runtime-action-request-", ""),
))

requested_action = str(request_body.get("requestedAction") or "NOOP")
request_status = str(request_body.get("requestStatus") or "UNKNOWN")
lifecycle_stage = str(request_body.get("lifecycleStage") or "UNKNOWN")
approval_required = bool_value(request_body.get("approvalRequired"), bool_value(approval.get("required"), False))
approved = bool_value(approval.get("approved"), False)
allowed_to_request = bool_value(binding.get("allowedToRequest"), False)

global_gate_enabled = env_enabled("S_SENTINEL_RUNTIME_EXECUTION_ENABLED")
pause_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_PAUSE")
resume_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_RESUME")
promote_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_PROMOTE")
abort_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_ABORT")
rollback_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_ROLLBACK")
approval_gate_enabled = env_enabled("S_SENTINEL_RUNTIME_ACTION_APPROVED")

operation_gate_env = None
operation_gate_enabled = False
if requested_action == "PAUSE_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_PAUSE"
    operation_gate_enabled = pause_gate_enabled
elif requested_action == "RESUME_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_RESUME"
    operation_gate_enabled = resume_gate_enabled
elif requested_action == "PROMOTE_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_PROMOTE"
    operation_gate_enabled = promote_gate_enabled
elif requested_action == "ABORT_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_ABORT"
    operation_gate_enabled = abort_gate_enabled
elif requested_action == "ROLLBACK_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_ROLLBACK"
    operation_gate_enabled = rollback_gate_enabled

manual_pause_gate_enabled = (
    requested_action == "PAUSE_ROLLOUT"
    and global_gate_enabled
    and pause_gate_enabled
    and approval_gate_enabled
)
manual_resume_gate_enabled = (
    requested_action == "RESUME_ROLLOUT"
    and global_gate_enabled
    and resume_gate_enabled
    and approval_gate_enabled
)
manual_promote_gate_enabled = (
    requested_action == "PROMOTE_ROLLOUT"
    and global_gate_enabled
    and promote_gate_enabled
    and approval_gate_enabled
)
manual_abort_gate_enabled = (
    requested_action == "ABORT_ROLLOUT"
    and global_gate_enabled
    and abort_gate_enabled
    and approval_gate_enabled
)
manual_rollback_gate_enabled = (
    requested_action == "ROLLBACK_ROLLOUT"
    and global_gate_enabled
    and rollback_gate_enabled
    and approval_gate_enabled
)
manual_operation_gate_enabled = (
    manual_pause_gate_enabled
    or manual_resume_gate_enabled
    or manual_promote_gate_enabled
    or manual_abort_gate_enabled
    or manual_rollback_gate_enabled
)

blocking_reasons = unique_strings(as_list(binding.get("blockingReasons")))
approval_reasons: list[str] = []
warning_reasons: list[str] = []

supported_actions = {"NOOP", "REQUIRE_REVIEW", "PAUSE_ROLLOUT", "RESUME_ROLLOUT", "PROMOTE_ROLLOUT", "ABORT_ROLLOUT", "ROLLBACK_ROLLOUT"}

if requested_action not in supported_actions:
    blocking_reasons.append("unsupported_runtime_action")

if requested_action == "RESUME_ROLLOUT" and not bool_value(snapshot.get("paused"), False):
    blocking_reasons.append("rollout_not_paused")

snapshot_phase = str(snapshot.get("rolloutPhase") or snapshot.get("phase") or "")
if requested_action == "PROMOTE_ROLLOUT" and (
    bool_value(snapshot.get("degraded"), False)
    or snapshot_phase == "Degraded"
):
    blocking_reasons.append("rollout_degraded_not_promotable")

if requested_action == "ROLLBACK_ROLLOUT":
    target_revision = rollback_target.get("targetRevision")
    if target_revision not in (None, ""):
        try:
            if int(target_revision) <= 0:
                blocking_reasons.append("invalid_rollback_target_revision")
        except Exception:
            blocking_reasons.append("invalid_rollback_target_revision")

if not allowed_to_request and requested_action not in {"NOOP"}:
    blocking_reasons.append("request_not_allowed_by_recommendation")

if bool_value(request_body.get("willExecute"), False):
    blocking_reasons.append("source_request_would_execute")

if bool_value(guardrails.get("willExecute"), False):
    blocking_reasons.append("source_guardrail_would_execute")

if guardrails.get("readOnly") is not True:
    blocking_reasons.append("source_request_not_read_only")

if guardrails.get("doesNotModifyKubernetes") is not True:
    blocking_reasons.append("source_request_may_modify_kubernetes")

if guardrails.get("doesNotPause") is not True:
    blocking_reasons.append("source_request_may_pause_rollout")

blocking_reasons = unique_strings(blocking_reasons)

if requested_action == "NOOP" or request_status == "NO_ACTION_REQUESTED":
    preflight_status = "NO_ACTION_REQUIRED"
    eligibility_status = "NO_ACTION_REQUIRED"
elif blocking_reasons:
    preflight_status = "BLOCKED"
    eligibility_status = "NOT_ELIGIBLE"
elif requested_action == "REQUIRE_REVIEW" or request_status == "REVIEW_REQUIRED":
    preflight_status = "WAITING_REVIEW"
    eligibility_status = "NEEDS_REVIEW"
    approval_reasons.append("human_review_required")
elif approval_required and not approved:
    preflight_status = "WAITING_APPROVAL"
    eligibility_status = "NOT_ELIGIBLE"
    approval_reasons.append("human_approval_required")
else:
    preflight_status = "PREFLIGHT_PASSED"
    eligibility_status = "ELIGIBLE_FOR_CONTROLLED_EXECUTOR"

eligible_for_execution = (
    preflight_status == "PREFLIGHT_PASSED"
    and eligibility_status == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR"
    and requested_action in {"PAUSE_ROLLOUT", "RESUME_ROLLOUT", "PROMOTE_ROLLOUT", "ABORT_ROLLOUT", "ROLLBACK_ROLLOUT"}
    and approved
    and manual_operation_gate_enabled
)

ready_to_execute = eligible_for_execution

checks = [
    {
        "name": "request_integrity",
        "status": "PASS" if request_doc.get("runtimeActionRequestId") else "FAIL",
        "reasons": [] if request_doc.get("runtimeActionRequestId") else ["missing_runtime_action_request_id"],
    },
    {
        "name": "action_support",
        "status": "PASS" if requested_action in supported_actions else "FAIL",
        "reasons": [] if requested_action in supported_actions else ["unsupported_runtime_action"],
    },
    {
        "name": "approval_gate",
        "status": "PASS" if not approval_reasons else "WAITING",
        "reasons": approval_reasons,
    },
    {
        "name": "safety_guardrails",
        "status": "PASS" if not [r for r in blocking_reasons if r.startswith("source_")] else "FAIL",
        "reasons": [r for r in blocking_reasons if r.startswith("source_")],
    },
    {
        "name": "evidence_refs",
        "status": "PASS" if evidence_refs else "WARN",
        "reasons": [] if evidence_refs else ["missing_evidence_refs"],
    },
]

doc = {
    "schemaVersion": "runtime.action.preflight/v1alpha1",
    "runtimeActionPreflightId": "rap-" + release_id,
    "generatedBy": "build-runtime-action-preflight.sh",
    "generatedAt": now(),
    "mode": "read_only_runtime_action_preflight",
    "sourceRuntimeActionRequestId": request_doc.get("runtimeActionRequestId"),
    "release": {
        "releaseId": release_id,
        "service": first_not_empty(release.get("service"), target.get("service")),
        "env": first_not_empty(release.get("env"), target.get("env")),
        "namespace": first_not_empty(release.get("namespace"), target.get("namespace")),
        "policyDecision": release.get("policyDecision"),
        "finalAction": release.get("finalAction"),
    },
    "target": {
        "cluster": target.get("cluster"),
        "namespace": target.get("namespace"),
        "rolloutName": target.get("rolloutName"),
        "service": first_not_empty(target.get("service"), release.get("service")),
        "env": first_not_empty(target.get("env"), release.get("env")),
    },
    "rollbackTarget": rollback_target,
    "request": {
        "runtimeActionRequestId": request_doc.get("runtimeActionRequestId"),
        "requestedAction": requested_action,
        "requestStatus": request_status,
        "lifecycleStage": lifecycle_stage,
        "riskLevel": request_body.get("riskLevel"),
        "confidence": request_body.get("confidence"),
        "approvalRequired": approval_required,
        "approved": approved,
        "allowedToRequest": allowed_to_request,
        "readyToExecute": ready_to_execute,
        "willExecute": False,
    },
    "executionGate": {
        "globalGateEnv": "S_SENTINEL_RUNTIME_EXECUTION_ENABLED",
        "globalGateEnabled": global_gate_enabled,
        "operationGateEnv": operation_gate_env,
        "operationGateEnabled": operation_gate_enabled,
        "pauseGateEnabled": pause_gate_enabled,
        "resumeGateEnabled": resume_gate_enabled,
        "promoteGateEnabled": promote_gate_enabled,
        "abortGateEnabled": abort_gate_enabled,
        "rollbackGateEnabled": rollback_gate_enabled,
        "approvalGateEnv": "S_SENTINEL_RUNTIME_ACTION_APPROVED",
        "approvalGateEnabled": approval_gate_enabled,
        "manualPauseGateEnabled": manual_pause_gate_enabled,
        "manualResumeGateEnabled": manual_resume_gate_enabled,
        "manualPromoteGateEnabled": manual_promote_gate_enabled,
        "manualAbortGateEnabled": manual_abort_gate_enabled,
        "manualRollbackGateEnabled": manual_rollback_gate_enabled,
        "manualOperationGateEnabled": manual_operation_gate_enabled,
        "readyForControlledExecutor": ready_to_execute,
        "willExecute": False,
    },
    "preflight": {
        "preflightStatus": preflight_status,
        "eligibilityStatus": eligibility_status,
        "checks": checks,
        "blockingReasons": blocking_reasons,
        "approvalReasons": approval_reasons,
        "warningReasons": warning_reasons,
        "eligibleForExecution": eligible_for_execution,
        "readyToExecute": ready_to_execute,
        "willExecute": False,
        "summary": f"Runtime action preflight status is {preflight_status} for {requested_action}.",
    },
    "runtimeSnapshot": {
        "rolloutPhase": snapshot.get("rolloutPhase"),
        "strategy": snapshot.get("strategy"),
        "currentStepIndex": snapshot.get("currentStepIndex"),
        "replicas": snapshot.get("replicas"),
        "updatedReplicas": snapshot.get("updatedReplicas"),
        "readyReplicas": snapshot.get("readyReplicas"),
        "availableReplicas": snapshot.get("availableReplicas"),
        "paused": snapshot.get("paused"),
        "degraded": snapshot.get("degraded"),
        "analysisRunName": snapshot.get("analysisRunName"),
        "analysisStatus": snapshot.get("analysisStatus"),
    },
    "evidenceRefs": {
        "runtimeActionRequest": str(input_path),
        "sourceRuntimeActionRequestId": request_doc.get("runtimeActionRequestId"),
        "runtimeActionRecommendation": evidence_refs.get("runtimeActionRecommendation"),
        "sourceRuntimeActionRecommendationId": evidence_refs.get("sourceRuntimeActionRecommendationId"),
        "rolloutRuntimeInspect": evidence_refs.get("rolloutRuntimeInspect"),
        "sourceRolloutRuntimeInspectId": evidence_refs.get("sourceRolloutRuntimeInspectId"),
    },
    "guardrails": {
        "preflightOnly": True,
        "readOnly": True,
        "willExecute": False,
        "doesNotPause": True,
        "doesNotResume": True,
        "doesNotPromote": True,
        "doesNotAbort": True,
        "doesNotRollback": True,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotCommitOrPush": True,
        "sourceRequestWillExecute": guardrails.get("willExecute"),
    },
}

output_json.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Runtime action preflight generated: {output_json}")
print(f"Latest runtime action preflight: {latest_json}")
print(json.dumps({
    "runtimeActionPreflightId": doc["runtimeActionPreflightId"],
    "releaseId": release_id,
    "requestedAction": requested_action,
    "preflightStatus": preflight_status,
    "eligibilityStatus": eligibility_status,
    "readyToExecute": ready_to_execute,
    "willExecute": False,
}, indent=2))
PY
