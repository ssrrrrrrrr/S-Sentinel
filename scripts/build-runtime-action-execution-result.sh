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
  S_SENTINEL_RUNTIME_ACTION_APPROVED            Approval gate.
  S_SENTINEL_RUNTIME_PAUSE_EXECUTE              Final explicit execution switch.

Behavior:
  - Reads runtime-action-preflight-*.json.
  - Generates runtime-action-execution-result-*.json and runtime-action-execution-result-latest.json.
  - Records a controlled runtime action execution result / receipt.
  - Default mode records evidence only.
  - Real PAUSE_ROLLOUT execution requires all explicit gates.
  - Only PAUSE_ROLLOUT is supported; resume, promote, abort, rollback, GitOps writes, commits, and pushes are not supported.
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
approval_gate_enabled = env_enabled("S_SENTINEL_RUNTIME_ACTION_APPROVED")
final_execute_enabled = env_enabled("S_SENTINEL_RUNTIME_PAUSE_EXECUTE")
supported_action = requested_action == "PAUSE_ROLLOUT"

if requested_action in {"NOOP", "REQUIRE_REVIEW"}:
    overall_gate_status = "NO_RUNTIME_EXECUTION_REQUIRED"
elif not supported_action:
    overall_gate_status = "BLOCKED_UNSUPPORTED_ACTION"
elif not preflight_passed:
    overall_gate_status = "BLOCKED_BY_PREFLIGHT"
elif not global_gate_enabled:
    overall_gate_status = "BLOCKED_BY_GLOBAL_GATE"
elif not pause_gate_enabled:
    overall_gate_status = "BLOCKED_BY_OPERATION_GATE"
elif not approval_gate_enabled:
    overall_gate_status = "BLOCKED_BY_APPROVAL_GATE"
elif not final_execute_enabled:
    overall_gate_status = "READY_BUT_NOT_EXECUTED_FINAL_SWITCH_OFF"
else:
    overall_gate_status = "EXECUTION_ALLOWED"

rollout_name = target.get("rolloutName")
namespace = target.get("namespace")

command_args = [
    "kubectl",
    "-n",
    str(namespace or ""),
    "patch",
    "rollout",
    str(rollout_name or ""),
    "--type=merge",
    "-p",
    '{"spec":{"paused":true}}',
]
command_mode = "kubectl_patch_rollout_spec_paused"

command_started_at = None
command_finished_at = None
command_exit_code = None
command_stdout = None
command_stderr = None
attempted_kubernetes_mutation = False
mutated_kubernetes = False
did_pause = False
executed = False

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
    did_pause = completed.returncode == 0
    overall_gate_status = "EXECUTION_SUCCEEDED" if completed.returncode == 0 else "EXECUTION_FAILED"

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
    "executor": {
        "executorName": "runtime-pause-executor",
        "executorType": "controlled_runtime_executor",
        "adapter": "runtime-pause",
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
        "operationGateEnv": "S_SENTINEL_ALLOW_RUNTIME_PAUSE",
        "operationGateEnabled": pause_gate_enabled,
        "approvalGateEnv": "S_SENTINEL_RUNTIME_ACTION_APPROVED",
        "approvalGateEnabled": approval_gate_enabled,
        "finalExecuteEnv": "S_SENTINEL_RUNTIME_PAUSE_EXECUTE",
        "finalExecuteEnabled": final_execute_enabled,
        "operation": "PAUSE_ROLLOUT",
        "overallGateStatus": overall_gate_status,
        "writeAllowed": overall_gate_status in {"EXECUTION_ALLOWED", "EXECUTION_SUCCEEDED", "EXECUTION_FAILED"},
        "willExecute": executed,
    },
    "beforeSnapshot": runtime_snapshot,
    "afterSnapshot": {
        "observationMode": "command_result_only" if executed else "not_executed",
        "commandExitCode": command_exit_code,
        "pausedAssumedFromCommandSuccess": did_pause,
    },
    "result": {
        "executionStatus": "SUCCEEDED" if executed and command_exit_code == 0 else ("FAILED" if executed else "NOT_EXECUTED"),
        "actionStatus": overall_gate_status,
        "requestedAction": requested_action,
        "didPause": did_pause,
        "didResume": False,
        "didPromote": False,
        "didAbort": False,
        "didRollback": False,
        "attemptedKubernetesMutation": attempted_kubernetes_mutation,
        "mutatedKubernetes": mutated_kubernetes,
        "mutatedGitOps": False,
        "readyForExecutor": overall_gate_status in {"EXECUTION_ALLOWED", "EXECUTION_SUCCEEDED"},
        "willExecute": executed,
        "summary": (
            f"Runtime action execution result recorded {overall_gate_status} for {requested_action}; "
            f"attemptedKubernetesMutation={attempted_kubernetes_mutation}, "
            f"mutatedKubernetes={mutated_kubernetes}, didPause={did_pause}."
        ),
    },
    "receipt": {
        "receiptType": "runtime_action_execution_result",
        "receiptStatus": "RECORDED",
        "wroteEvidence": True,
        "sourceRuntimeActionPreflight": str(input_path),
        "resultArtifact": str(output_json),
        "didPause": did_pause,
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
        "doesNotPause": not did_pause,
        "doesNotResume": True,
        "doesNotPromote": True,
        "doesNotAbort": True,
        "doesNotRollback": True,
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
    "willExecute": executed,
}, indent=2))
PY
