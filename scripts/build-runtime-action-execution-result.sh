#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"
OUTPUT_DIR="${RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-runtime-action-execution-result.sh [latest|RUNTIME_ACTION_PREFLIGHT_JSON]

Environment:
  RELEASE_REPORT_DIR                            Optional report directory.
  RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR    Optional output directory.
  S_SENTINEL_RUNTIME_EXECUTION_ENABLED          Global execution gate.
  S_SENTINEL_ALLOW_RUNTIME_PAUSE                PAUSE_ROLLOUT operation gate.
  S_SENTINEL_ALLOW_RUNTIME_RESUME               RESUME_ROLLOUT operation gate.
  S_SENTINEL_ALLOW_RUNTIME_PROMOTE              PROMOTE_ROLLOUT operation gate.
  S_SENTINEL_ALLOW_RUNTIME_ABORT                ABORT_ROLLOUT operation gate.
  S_SENTINEL_ALLOW_RUNTIME_ROLLBACK             ROLLBACK_ROLLOUT operation gate.
  S_SENTINEL_RUNTIME_ACTION_APPROVED            Approval gate.
  S_SENTINEL_RUNTIME_PAUSE_EXECUTE              Final explicit pause execution switch.
  S_SENTINEL_RUNTIME_RESUME_EXECUTE             Final explicit resume execution switch.
  S_SENTINEL_RUNTIME_PROMOTE_EXECUTE            Final explicit promote execution switch.
  S_SENTINEL_RUNTIME_ABORT_EXECUTE              Final explicit abort execution switch.

Behavior:
  - Reads runtime-action-preflight-*.json.
  - Generates runtime-action-execution-result-*.json and runtime-action-execution-result-latest.json.
  - Records a controlled runtime action execution result / receipt.
  - Default mode records evidence only.
  - Real PAUSE_ROLLOUT execution requires all explicit gates and patches spec.paused=true after gates pass.
  - Real RESUME_ROLLOUT execution requires all explicit gates and patches spec.paused=false after gates pass.
  - Real PROMOTE_ROLLOUT execution requires all explicit gates and runs kubectl argo rollouts promote after gates pass.
  - Real ABORT_ROLLOUT execution requires all explicit gates and runs kubectl argo rollouts abort after gates pass.
  - Real ROLLBACK_ROLLOUT execution requires all explicit gates and runs kubectl argo rollouts undo after gates pass.
  - GitOps writes, commits, and pushes are not supported by this executor yet.
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
  INPUT_FILE="$(ls -t "$REPORT_DIR"/runtime-action-preflight-*.json 2>/dev/null | grep -v 'runtime-action-preflight-latest.json' | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: runtime action preflight file does not exist: ${INPUT_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
SUFFIX="${BASENAME#runtime-action-preflight-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$(dirname "$INPUT_FILE")"
fi
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="$OUTPUT_DIR/runtime-action-execution-result-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/runtime-action-execution-result-latest.json"

python3 - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY'
from __future__ import annotations

import json
import os
import shutil
import subprocess
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

def first_not_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None

def env_enabled(name: str) -> bool:
    return str(os.environ.get(name, "")).strip().lower() in {"1", "true", "yes", "y", "on"}

preflight_doc = load_json(input_path)

release = as_dict(preflight_doc.get("release"))
target = as_dict(preflight_doc.get("target"))
request = as_dict(preflight_doc.get("request"))
preflight = as_dict(preflight_doc.get("preflight"))
runtime_snapshot = as_dict(preflight_doc.get("runtimeSnapshot"))
rollback_target = as_dict(preflight_doc.get("rollbackTarget"))
evidence_refs = as_dict(preflight_doc.get("evidenceRefs"))
source_guardrails = as_dict(preflight_doc.get("guardrails"))

release_id = str(first_not_empty(
    release.get("releaseId"),
    input_path.stem.replace("runtime-action-preflight-", ""),
))

requested_action = str(request.get("requestedAction") or "NOOP")
preflight_status = str(preflight.get("preflightStatus") or "UNKNOWN")
eligibility_status = str(preflight.get("eligibilityStatus") or "UNKNOWN")

preflight_passed = (
    preflight_status == "PREFLIGHT_PASSED"
    and eligibility_status == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR"
    and preflight.get("eligibleForExecution") is True
    and preflight.get("readyToExecute") is True
    and preflight.get("willExecute") is False
)

global_gate_enabled = env_enabled("S_SENTINEL_RUNTIME_EXECUTION_ENABLED")
pause_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_PAUSE")
resume_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_RESUME")
promote_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_PROMOTE")
abort_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_ABORT")
rollback_gate_enabled = env_enabled("S_SENTINEL_ALLOW_RUNTIME_ROLLBACK")
approval_gate_enabled = env_enabled("S_SENTINEL_RUNTIME_ACTION_APPROVED")

operation_gate_env = None
operation_gate_enabled = False
final_execute_env = None

if requested_action == "PAUSE_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_PAUSE"
    operation_gate_enabled = pause_gate_enabled
    final_execute_env = "S_SENTINEL_RUNTIME_PAUSE_EXECUTE"
elif requested_action == "RESUME_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_RESUME"
    operation_gate_enabled = resume_gate_enabled
    final_execute_env = "S_SENTINEL_RUNTIME_RESUME_EXECUTE"
elif requested_action == "PROMOTE_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_PROMOTE"
    operation_gate_enabled = promote_gate_enabled
    final_execute_env = "S_SENTINEL_RUNTIME_PROMOTE_EXECUTE"
elif requested_action == "ABORT_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_ABORT"
    operation_gate_enabled = abort_gate_enabled
    final_execute_env = "S_SENTINEL_RUNTIME_ABORT_EXECUTE"
elif requested_action == "ROLLBACK_ROLLOUT":
    operation_gate_env = "S_SENTINEL_ALLOW_RUNTIME_ROLLBACK"
    operation_gate_enabled = rollback_gate_enabled
    final_execute_env = "S_SENTINEL_RUNTIME_ROLLBACK_EXECUTE"

final_execute_enabled = env_enabled(final_execute_env) if final_execute_env else False
supported_action = requested_action in {"PAUSE_ROLLOUT", "RESUME_ROLLOUT", "PROMOTE_ROLLOUT", "ABORT_ROLLOUT", "ROLLBACK_ROLLOUT"}
implemented_action = requested_action in {"PAUSE_ROLLOUT", "RESUME_ROLLOUT", "PROMOTE_ROLLOUT", "ABORT_ROLLOUT", "ROLLBACK_ROLLOUT"}

if requested_action in {"NOOP", "REQUIRE_REVIEW"}:
    overall_gate_status = "NO_RUNTIME_EXECUTION_REQUIRED"
elif not supported_action:
    overall_gate_status = "BLOCKED_UNSUPPORTED_ACTION"
elif not preflight_passed:
    overall_gate_status = "BLOCKED_BY_PREFLIGHT"
elif not global_gate_enabled:
    overall_gate_status = "BLOCKED_BY_GLOBAL_GATE"
elif not operation_gate_enabled:
    overall_gate_status = "BLOCKED_BY_OPERATION_GATE"
elif not approval_gate_enabled:
    overall_gate_status = "BLOCKED_BY_APPROVAL_GATE"
elif not final_execute_enabled:
    overall_gate_status = "READY_BUT_NOT_EXECUTED_FINAL_SWITCH_OFF"
elif not implemented_action:
    overall_gate_status = "BLOCKED_EXECUTOR_NOT_IMPLEMENTED"
else:
    overall_gate_status = "EXECUTION_ALLOWED"

rollout_name = target.get("rolloutName")
namespace = target.get("namespace")

if requested_action in {"PAUSE_ROLLOUT", "RESUME_ROLLOUT"}:
    paused_patch_value = "false" if requested_action == "RESUME_ROLLOUT" else "true"
    command_args = [
        "kubectl",
        "-n",
        str(namespace or ""),
        "patch",
        "rollout",
        str(rollout_name or ""),
        "--type=merge",
        "-p",
        f'{{"spec":{{"paused":{paused_patch_value}}}}}',
    ]
    command_mode = (
        "kubectl_patch_rollout_spec_paused_false"
        if requested_action == "RESUME_ROLLOUT"
        else "kubectl_patch_rollout_spec_paused"
    )
elif requested_action == "PROMOTE_ROLLOUT":
    command_args = [
        "kubectl",
        "argo",
        "rollouts",
        "promote",
        str(rollout_name or ""),
        "-n",
        str(namespace or ""),
    ]
    command_mode = "kubectl_argo_rollouts_promote"
elif requested_action == "ABORT_ROLLOUT":
    command_args = [
        "kubectl",
        "argo",
        "rollouts",
        "abort",
        str(rollout_name or ""),
        "-n",
        str(namespace or ""),
    ]
    command_mode = "kubectl_argo_rollouts_abort"
elif requested_action == "ROLLBACK_ROLLOUT":
    command_args = [
        "kubectl",
        "argo",
        "rollouts",
        "undo",
        str(rollout_name or ""),
        "-n",
        str(namespace or ""),
    ]
    target_revision = rollback_target.get("targetRevision")
    if target_revision not in (None, ""):
        command_args.append(f"--to-revision={int(target_revision)}")
        command_mode = "kubectl_argo_rollouts_undo_to_revision"
    else:
        command_mode = "kubectl_argo_rollouts_undo"
else:
    command_args = []
    command_mode = "unsupported_runtime_action_command"

command_started_at = None
command_finished_at = None
command_exit_code = None
command_stdout = None
command_stderr = None
attempted_kubernetes_mutation = False
mutated_kubernetes = False
did_pause = False
did_resume = False
did_promote = False
did_abort = False
did_rollback = False
executed = False
post_action_rollout_get_attempted = False
post_action_rollout_get_succeeded = False
post_action_rollout_get_exit_code = None
post_action_rollout_get_stdout = None
post_action_rollout_get_stderr = None
post_action_rollout_snapshot = {}

def build_rollout_snapshot_from_live_json(raw: str) -> dict[str, Any]:
    try:
        rollout_obj = json.loads(raw)
    except Exception as exc:
        return {
            "observationMode": "live_readonly_rollout_get_parse_failed",
            "parseError": str(exc),
        }

    meta = as_dict(rollout_obj.get("metadata"))
    spec = as_dict(rollout_obj.get("spec"))
    status = as_dict(rollout_obj.get("status"))
    conditions = status.get("conditions") if isinstance(status.get("conditions"), list) else []

    paused_condition = {}
    healthy_condition = {}
    for item in conditions:
        if not isinstance(item, dict):
            continue
        if item.get("type") == "Paused":
            paused_condition = item
        if item.get("type") == "Healthy":
            healthy_condition = item

    spec_paused = spec.get("paused") is True
    pause_conditions = status.get("pauseConditions")
    if not isinstance(pause_conditions, list):
        pause_conditions = []
    status_paused = paused_condition.get("status") == "True" or bool(pause_conditions)

    return {
        "observationMode": "live_readonly_rollout_get_after_action",
        "name": meta.get("name") or rollout_name,
        "namespace": meta.get("namespace") or namespace,
        "phase": status.get("phase") or "Unknown",
        "message": status.get("message"),
        "currentStepIndex": status.get("currentStepIndex"),
        "replicas": first_not_empty(status.get("replicas"), spec.get("replicas")),
        "updatedReplicas": status.get("updatedReplicas"),
        "readyReplicas": status.get("readyReplicas"),
        "availableReplicas": status.get("availableReplicas"),
        "paused": spec_paused or status_paused,
        "specPaused": spec_paused,
        "statusPaused": status_paused,
        "pauseConditions": pause_conditions,
        "degraded": status.get("phase") == "Degraded",
        "aborted": "abort" in str(status.get("message") or status.get("phase") or "").lower(),
        "observedGeneration": status.get("observedGeneration"),
        "currentPodHash": status.get("currentPodHash"),
        "stableRS": status.get("stableRS"),
        "pausedCondition": {
            "status": paused_condition.get("status"),
            "reason": paused_condition.get("reason"),
            "message": paused_condition.get("message"),
        },
        "healthyCondition": {
            "status": healthy_condition.get("status"),
            "reason": healthy_condition.get("reason"),
            "message": healthy_condition.get("message"),
        },
    }

if overall_gate_status == "EXECUTION_ALLOWED":
    command_started_at = now()
    completed = subprocess.run(
        command_args,
        text=True,
        capture_output=True,
        check=False,
    )
    command_finished_at = now()
    command_exit_code = completed.returncode
    command_stdout = completed.stdout
    command_stderr = completed.stderr
    executed = True
    attempted_kubernetes_mutation = True
    mutated_kubernetes = completed.returncode == 0
    did_pause = completed.returncode == 0 and requested_action == "PAUSE_ROLLOUT"
    did_resume = completed.returncode == 0 and requested_action == "RESUME_ROLLOUT"
    did_promote = completed.returncode == 0 and requested_action == "PROMOTE_ROLLOUT"
    did_abort = completed.returncode == 0 and requested_action == "ABORT_ROLLOUT"
    did_rollback = completed.returncode == 0 and requested_action == "ROLLBACK_ROLLOUT"
    overall_gate_status = "EXECUTION_SUCCEEDED" if completed.returncode == 0 else "EXECUTION_FAILED"

    if completed.returncode == 0 and namespace and rollout_name:
        post_action_rollout_get_attempted = True
        rollout_get = subprocess.run(
            ["kubectl", "-n", str(namespace), "get", "rollout", str(rollout_name), "-o", "json"],
            text=True,
            capture_output=True,
            check=False,
        )
        post_action_rollout_get_exit_code = rollout_get.returncode
        post_action_rollout_get_stdout = rollout_get.stdout
        post_action_rollout_get_stderr = rollout_get.stderr
        post_action_rollout_get_succeeded = rollout_get.returncode == 0
        if rollout_get.returncode == 0:
            post_action_rollout_snapshot = build_rollout_snapshot_from_live_json(rollout_get.stdout)

after_snapshot = {
    "observationMode": "command_result_only" if executed else "not_executed",
    "commandExitCode": command_exit_code,
    "pausedAssumedFromCommandSuccess": did_pause,
    "resumedAssumedFromCommandSuccess": did_resume,
    "promotedAssumedFromCommandSuccess": did_promote,
    "abortedAssumedFromCommandSuccess": did_abort,
    "rolledBackAssumedFromCommandSuccess": did_rollback,
    "postActionRolloutGetAttempted": post_action_rollout_get_attempted,
    "postActionRolloutGetSucceeded": post_action_rollout_get_succeeded,
    "postActionRolloutGetExitCode": post_action_rollout_get_exit_code,
}
if post_action_rollout_get_stderr not in (None, ""):
    after_snapshot["postActionRolloutGetStderr"] = post_action_rollout_get_stderr
if post_action_rollout_snapshot:
    after_snapshot.update(post_action_rollout_snapshot)

command_succeeded = executed and command_exit_code == 0
post_action_observed = post_action_rollout_get_succeeded is True
observed_paused = after_snapshot.get("paused") is True
observed_spec_paused = after_snapshot.get("specPaused") is True
observed_status_paused = after_snapshot.get("statusPaused") is True
pause_desired_state_observed = observed_paused or observed_spec_paused
resume_desired_state_observed = (
    after_snapshot.get("paused") is False
    or after_snapshot.get("specPaused") is False
)
before_step_index = runtime_snapshot.get("currentStepIndex")
after_step_index = after_snapshot.get("currentStepIndex")
promote_step_advanced = (
    isinstance(before_step_index, int)
    and isinstance(after_step_index, int)
    and after_step_index > before_step_index
)
promote_phase_observed = after_snapshot.get("phase") in {"Healthy", "Progressing"}
promote_desired_state_observed = (
    post_action_observed
    and after_snapshot.get("degraded") is not True
    and (promote_step_advanced or promote_phase_observed)
)
abort_phase_observed = (
    after_snapshot.get("phase") == "Degraded"
    or after_snapshot.get("aborted") is True
)
abort_desired_state_observed = (
    post_action_observed
    and abort_phase_observed
)

rollback_target_stable_rs = rollback_target.get("targetStableRS")
rollback_target_pod_hash = rollback_target.get("targetPodHash")
rollback_phase_observed = (
    after_snapshot.get("phase") in {"Healthy", "Progressing"}
    and after_snapshot.get("degraded") is not True
)
rollback_target_observed = (
    (rollback_target_stable_rs not in (None, "") and after_snapshot.get("stableRS") == rollback_target_stable_rs)
    or (rollback_target_pod_hash not in (None, "") and after_snapshot.get("currentPodHash") == rollback_target_pod_hash)
    or rollback_target.get("targetRevision") not in (None, "")
    or rollback_target.get("strategy") == "previous_revision"
)
rollback_desired_state_observed = (
    post_action_observed
    and rollback_phase_observed
    and rollback_target_observed
)

if requested_action == "PAUSE_ROLLOUT":
    desired_state_observed = pause_desired_state_observed
elif requested_action == "RESUME_ROLLOUT":
    desired_state_observed = resume_desired_state_observed
elif requested_action == "PROMOTE_ROLLOUT":
    desired_state_observed = promote_desired_state_observed
elif requested_action == "ABORT_ROLLOUT":
    desired_state_observed = abort_desired_state_observed
elif requested_action == "ROLLBACK_ROLLOUT":
    desired_state_observed = rollback_desired_state_observed
else:
    desired_state_observed = False

pause_verified = (
    requested_action == "PAUSE_ROLLOUT"
    and command_succeeded
    and post_action_observed
    and desired_state_observed
)
resume_verified = (
    requested_action == "RESUME_ROLLOUT"
    and command_succeeded
    and post_action_observed
    and desired_state_observed
)
promote_verified = (
    requested_action == "PROMOTE_ROLLOUT"
    and command_succeeded
    and post_action_observed
    and desired_state_observed
)
abort_verified = (
    requested_action == "ABORT_ROLLOUT"
    and command_succeeded
    and post_action_observed
    and desired_state_observed
)
rollback_verified = (
    requested_action == "ROLLBACK_ROLLOUT"
    and command_succeeded
    and post_action_observed
    and desired_state_observed
)

verification_blocking_reasons = []
verification_warning_reasons = []

if not executed:
    verification_status = "NOT_RUN"
    verification_blocking_reasons.append("runtime_action_not_executed")
elif not command_succeeded:
    verification_status = "COMMAND_FAILED"
    verification_blocking_reasons.append("runtime_action_command_failed")
elif not post_action_observed:
    verification_status = "OBSERVATION_FAILED"
    verification_blocking_reasons.append("post_action_rollout_get_failed")
elif requested_action == "PAUSE_ROLLOUT" and not desired_state_observed:
    verification_status = "VERIFY_FAILED"
    verification_blocking_reasons.append("pause_state_not_observed_after_action")
elif requested_action == "RESUME_ROLLOUT" and not desired_state_observed:
    verification_status = "VERIFY_FAILED"
    verification_blocking_reasons.append("resume_state_not_observed_after_action")
elif requested_action == "PROMOTE_ROLLOUT" and not desired_state_observed:
    verification_status = "VERIFY_FAILED"
    verification_blocking_reasons.append("promote_state_not_observed_after_action")
elif requested_action == "ABORT_ROLLOUT" and not desired_state_observed:
    verification_status = "VERIFY_FAILED"
    verification_blocking_reasons.append("abort_state_not_observed_after_action")
elif requested_action == "ROLLBACK_ROLLOUT" and not desired_state_observed:
    verification_status = "VERIFY_FAILED"
    verification_blocking_reasons.append("rollback_state_not_observed_after_action")
else:
    verification_status = "VERIFIED"

post_action_verification = {
    "verificationType": "runtime_action_post_action_verification",
    "verificationStatus": verification_status,
    "requestedAction": requested_action,
    "commandSucceeded": command_succeeded,
    "postActionObserved": post_action_observed,
    "desiredStateObserved": desired_state_observed,
    "pauseVerified": pause_verified,
    "resumeVerified": resume_verified,
    "promoteVerified": promote_verified,
    "abortVerified": abort_verified,
    "rollbackVerified": rollback_verified,
    "promoteStepAdvanced": promote_step_advanced,
    "promotePhaseObserved": promote_phase_observed,
    "abortPhaseObserved": abort_phase_observed,
    "rollbackPhaseObserved": rollback_phase_observed,
    "rollbackTargetObserved": rollback_target_observed,
    "observedAborted": after_snapshot.get("aborted") is True,
    "observedStableRS": after_snapshot.get("stableRS"),
    "observedCurrentPodHash": after_snapshot.get("currentPodHash"),
    "expectedPaused": False if requested_action == "RESUME_ROLLOUT" else requested_action == "PAUSE_ROLLOUT",
    "observedPaused": observed_paused,
    "observedSpecPaused": observed_spec_paused,
    "observedStatusPaused": observed_status_paused,
    "blockingReasons": verification_blocking_reasons,
    "warningReasons": verification_warning_reasons,
}

doc = {
    "schemaVersion": "runtime.action.execution.result/v1alpha1",
    "runtimeActionExecutionResultId": "raer-" + release_id,
    "generatedBy": "build-runtime-action-execution-result.sh",
    "generatedAt": now(),
    "mode": "controlled_runtime_action_result",
    "sourceRuntimeActionPreflightId": preflight_doc.get("runtimeActionPreflightId"),
    "sourceRuntimeActionRequestId": preflight_doc.get("sourceRuntimeActionRequestId"),
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
        "namespace": namespace,
        "rolloutName": rollout_name,
        "service": first_not_empty(target.get("service"), release.get("service")),
        "env": first_not_empty(target.get("env"), release.get("env")),
    },
    "rollbackTarget": rollback_target,
    "executor": {
        "executorName": "runtime-rollout-executor",
        "executorType": "controlled_runtime_executor",
        "adapter": "runtime-rollout-control",
        "adapterType": "local-script",
        "contractMode": False,
        "dryRunOnly": not executed,
        "readOnly": not executed,
        "willExecute": executed,
        "mutatesKubernetes": mutated_kubernetes,
        "mutatesGitOps": False,
        "emitsExecutionEvidence": True,
    },
    "action": {
        "requestedAction": requested_action,
        "supportedAction": supported_action,
        "implementedAction": implemented_action,
        "actionStatus": overall_gate_status,
        "commandPreviewArgs": command_args,
        "commandMode": command_mode,
        "commandStartedAt": command_started_at,
        "commandFinishedAt": command_finished_at,
        "commandExitCode": command_exit_code,
        "commandStdout": command_stdout,
        "commandStderr": command_stderr,
        "commandWillExecute": executed,
    },
    "writeGate": {
        "preflightRequired": True,
        "preflightStatus": preflight_status,
        "eligibilityStatus": eligibility_status,
        "preflightPassed": preflight_passed,
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
        "finalExecuteEnv": final_execute_env,
        "finalExecuteEnabled": final_execute_enabled,
        "operation": requested_action,
        "overallGateStatus": overall_gate_status,
        "writeAllowed": overall_gate_status in {"EXECUTION_ALLOWED", "EXECUTION_SUCCEEDED", "EXECUTION_FAILED"},
        "willExecute": executed,
    },
    "beforeSnapshot": runtime_snapshot,
    "afterSnapshot": after_snapshot,
    "postActionVerification": post_action_verification,
    "result": {
        "executionStatus": "SUCCEEDED" if executed and command_exit_code == 0 else ("FAILED" if executed else "NOT_EXECUTED"),
        "actionStatus": overall_gate_status,
        "requestedAction": requested_action,
        "verificationStatus": verification_status,
        "pauseVerified": pause_verified,
        "resumeVerified": resume_verified,
        "promoteVerified": promote_verified,
        "abortVerified": abort_verified,
        "rollbackVerified": rollback_verified,
        "postActionObserved": post_action_observed,
        "desiredStateObserved": desired_state_observed,
        "didPause": did_pause,
        "didResume": did_resume,
        "didPromote": did_promote,
        "didAbort": did_abort,
        "didRollback": did_rollback,
        "attemptedKubernetesMutation": attempted_kubernetes_mutation,
        "mutatedKubernetes": mutated_kubernetes,
        "mutatedGitOps": False,
        "readyForExecutor": overall_gate_status in {"EXECUTION_ALLOWED", "EXECUTION_SUCCEEDED"},
        "willExecute": executed,
        "summary": (
            f"Runtime action execution result recorded {overall_gate_status} for {requested_action}; "
            f"attemptedKubernetesMutation={attempted_kubernetes_mutation}, "
            f"mutatedKubernetes={mutated_kubernetes}, didPause={did_pause}, "
            f"didResume={did_resume}, didPromote={did_promote}, didAbort={did_abort}, "
            f"didRollback={did_rollback}."
        ),
    },
    "receipt": {
        "receiptType": "runtime_action_execution_result",
        "receiptStatus": "RECORDED",
        "wroteEvidence": True,
        "sourceRuntimeActionPreflight": str(input_path),
        "resultArtifact": str(output_json),
        "didPause": did_pause,
        "didResume": did_resume,
        "didPromote": did_promote,
        "didAbort": did_abort,
        "didRollback": did_rollback,
        "verificationStatus": verification_status,
        "pauseVerified": pause_verified,
        "resumeVerified": resume_verified,
        "promoteVerified": promote_verified,
        "abortVerified": abort_verified,
        "rollbackVerified": rollback_verified,
        "attemptedModifyKubernetes": attempted_kubernetes_mutation,
        "didModifyKubernetes": mutated_kubernetes,
        "didModifyGitOps": False,
    },
    "evidenceRefs": {
        "runtimeActionPreflight": str(input_path),
        "sourceRuntimeActionPreflightId": preflight_doc.get("runtimeActionPreflightId"),
        "runtimeActionRequest": evidence_refs.get("runtimeActionRequest"),
        "sourceRuntimeActionRequestId": preflight_doc.get("sourceRuntimeActionRequestId"),
        "runtimeActionRecommendation": evidence_refs.get("runtimeActionRecommendation"),
        "sourceRuntimeActionRecommendationId": evidence_refs.get("sourceRuntimeActionRecommendationId"),
        "rolloutRuntimeInspect": evidence_refs.get("rolloutRuntimeInspect"),
        "sourceRolloutRuntimeInspectId": evidence_refs.get("sourceRolloutRuntimeInspectId"),
    },
    "guardrails": {
        "contractOnly": False,
        "readOnly": not executed,
        "dryRunOnly": not executed,
        "willExecute": executed,
        "postActionVerified": pause_verified or resume_verified or promote_verified or abort_verified or rollback_verified,
        "doesNotPause": not did_pause,
        "doesNotResume": not did_resume,
        "doesNotPromote": not did_promote,
        "doesNotAbort": not did_abort,
        "doesNotRollback": not did_rollback,
        "doesNotModifyKubernetes": not mutated_kubernetes,
        "doesNotModifyGitOps": True,
        "doesNotCommitOrPush": True,
        "sourcePreflightWillExecute": source_guardrails.get("willExecute"),
    },
}

output_json.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Runtime action execution result generated: {output_json}")
print(f"Latest runtime action execution result: {latest_json}")
print(json.dumps({
    "runtimeActionExecutionResultId": doc["runtimeActionExecutionResultId"],
    "releaseId": release_id,
    "requestedAction": requested_action,
    "overallGateStatus": overall_gate_status,
    "executionStatus": doc["result"]["executionStatus"],
    "didPause": did_pause,
    "didResume": did_resume,
    "didRollback": did_rollback,
    "willExecute": executed,
}, indent=2))
PY
