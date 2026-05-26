#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-handoff-progress.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                               Optional report directory.
  GITOPS_ADAPTER_HANDOFF_PROGRESS_OUTPUT_DIR      Optional output directory.
  GITOPS_ADAPTER_HANDOFF_PROGRESS_OUTPUT_FILE     Optional exact output file.
  GITOPS_ADAPTER_HANDOFF_ACTION                   Optional local action: START_HANDOFF, COMPLETE_HANDOFF, RETURN_FOR_REWORK.

Behavior:
  - Reads release evidence, handoff prep, pickup transition, and handoff state artifacts.
  - Generates gitops-adapter-handoff-progress-*.json and gitops-adapter-handoff-progress-latest.json.
  - Derives a local-only handoff progression result; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_HANDOFF_PROGRESS_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_HANDOFF_PROGRESS_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-handoff-progress-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-handoff-progress-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_HANDOFF_PROGRESS'
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
            if candidate.exists():
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


def normalized_action(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip().upper()
    return text if text else None


def progress_from(prep_status: str | None, selected_action: str | None) -> tuple[str, str, str, str, str, list[str]]:
    warnings: list[str] = []

    if prep_status == "PREPARED_FOR_HANDOFF":
        if selected_action is None:
            return (
                "WAITING_TO_START",
                "handoff_preparation_ready",
                "start_handoff_execution",
                "platform_owner",
                "platform_owner",
                warnings,
            )
        if selected_action == "START_HANDOFF":
            return (
                "HANDOFF_IN_PROGRESS",
                "handoff_execution_started",
                "capture_handoff_progress",
                "platform_owner",
                "platform_owner",
                warnings,
            )
        if selected_action == "COMPLETE_HANDOFF":
            return (
                "HANDOFF_COMPLETED",
                "handoff_execution_completed",
                "archive_handoff_state",
                "platform_owner",
                "platform_owner",
                warnings,
            )
        if selected_action == "RETURN_FOR_REWORK":
            return (
                "RETURNED_FOR_REWORK",
                "handoff_returned_for_rework",
                "revise_handoff_workspace",
                "platform_owner",
                "platform_owner",
                warnings,
            )
        warnings.append(f"selected handoff action {selected_action} is not supported for prep status {prep_status}")
        return (
            "INVALID_ACTION",
            "invalid_handoff_action",
            "repair_handoff_progress_state",
            "platform_owner",
            "platform_owner",
            warnings,
        )

    static_mapping = {
        "WAITING_FOR_PREP": (
            "WAITING_TO_START",
            "await_handoff_prep",
            "wait_for_handoff_prep",
            "platform_owner",
            "platform_owner",
        ),
        "HANDOFF_IN_PROGRESS": (
            "HANDOFF_IN_PROGRESS",
            "handoff_execution_started",
            "capture_handoff_progress",
            "platform_owner",
            "platform_owner",
        ),
        "HANDOFF_COMPLETED": (
            "HANDOFF_COMPLETED",
            "handoff_execution_completed",
            "archive_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
        "RETURNED_FOR_REWORK": (
            "RETURNED_FOR_REWORK",
            "handoff_returned_for_rework",
            "revise_handoff_workspace",
            "platform_owner",
            "platform_owner",
        ),
        "WAITING_APPROVAL": (
            "WAITING_APPROVAL",
            "approval_gate_pending",
            "await_manual_approval",
            "approver",
            "approver",
        ),
        "BLOCKED": (
            "BLOCKED",
            "handoff_progress_blocked",
            "resolve_handoff_blockers",
            "platform_owner",
            "platform_owner",
        ),
        "NO_ACTION_REQUIRED": (
            "NO_ACTION_REQUIRED",
            "handoff_not_required",
            "archive_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
        "INVALID_TRANSITION": (
            "INVALID_ACTION",
            "invalid_handoff_transition",
            "repair_handoff_progress_state",
            "platform_owner",
            "platform_owner",
        ),
        "FAILED": (
            "FAILED",
            "handoff_progress_failed",
            "repair_handoff_progress_state",
            "platform_owner",
            "platform_owner",
        ),
    }

    if prep_status in static_mapping:
        progress_status, current_checkpoint, next_checkpoint, current_actor, next_actor = static_mapping[prep_status]
        return (
            progress_status,
            current_checkpoint,
            next_checkpoint,
            current_actor,
            next_actor,
            warnings,
        )

    warnings.append("gitops adapter handoff progress could not map the current prep state")
    return (
        "FAILED",
        "unknown_handoff_progress_state",
        "repair_handoff_progress_state",
        "platform_owner",
        "platform_owner",
        warnings,
    )


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

handoff_prep_path = resolve_ref(artifacts.get("gitopsAdapterHandoffPrep"), input_path)
handoff_prep = load_json(handoff_prep_path)
handoff_prep_body = as_dict(handoff_prep.get("handoffPrep"))

pickup_transition_path = resolve_ref(artifacts.get("gitopsAdapterPickupTransition"), input_path)
pickup_transition = load_json(pickup_transition_path)
pickup_transition_body = as_dict(pickup_transition.get("pickupTransition"))

handoff_state_path = resolve_ref(artifacts.get("gitopsAdapterHandoffState"), input_path)
handoff_state = load_json(handoff_state_path)
handoff_state_body = as_dict(handoff_state.get("handoffState"))

release = as_dict(handoff_prep.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

selected_action = normalized_action(os.environ.get("GITOPS_ADAPTER_HANDOFF_ACTION"))
prep_status = nullable_string(handoff_prep_body.get("prepStatus"))
progress_status, current_checkpoint, next_checkpoint, current_actor, next_actor, progress_warnings = progress_from(
    prep_status,
    selected_action,
)

action_source = "env:GITOPS_ADAPTER_HANDOFF_ACTION" if selected_action else "pending_local_action"
workspace_dir = resolve_ref(first_not_none(
    handoff_prep_body.get("workspaceDir"),
    pickup_transition_body.get("workspaceDir"),
    handoff_state_body.get("workspaceDir"),
), input_path)

workspace_files = []
if workspace_dir and workspace_dir.exists():
    try:
        workspace_files = sorted([str(item) for item in workspace_dir.rglob("*") if item.is_file()])
    except OSError:
        workspace_files = []

progress_control_path = workspace_dir / "handoff-progress-control.json" if workspace_dir else output_json.parent / f"handoff-progress-control-{release_id}.json"
progress_control_summary_path = workspace_dir / "handoff-progress-summary.md" if workspace_dir else output_json.parent / f"handoff-progress-summary-{release_id}.md"
progress_control_path.parent.mkdir(parents=True, exist_ok=True)

progress_control = {
    "schemaVersion": "gitops.adapter.handoff.progress.control/v1alpha1",
    "gitopsAdapterHandoffProgressId": f"ghpr-{release_id}",
    "generatedAt": now(),
    "progressStatus": progress_status,
    "selectedAction": selected_action,
    "actionSource": action_source,
    "currentCheckpoint": current_checkpoint,
    "nextCheckpoint": next_checkpoint,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "workspaceArtifactCount": len(workspace_files),
    "localOnly": True,
}
progress_control_path.write_text(json.dumps(progress_control, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
progress_control_summary_path.write_text(
    "# GitOps Handoff Progress\n\n"
    + f"- progressStatus: {progress_status}\n"
    + f"- selectedAction: {selected_action or 'none'}\n"
    + f"- actionSource: {action_source}\n"
    + f"- currentCheckpoint: {current_checkpoint}\n"
    + f"- nextCheckpoint: {next_checkpoint}\n"
    + f"- workspaceArtifactCount: {len(workspace_files)}\n",
    encoding="utf-8",
)

warnings = [str(item) for item in as_list(handoff_prep_body.get("warnings"))]
warnings.extend(progress_warnings)
if not handoff_prep_path:
    warnings.append("gitops adapter handoff progress could not resolve handoff prep input")

handoff_progress = {
    "schemaVersion": "gitops.adapter.handoff.progress/v1alpha1",
    "gitopsAdapterHandoffProgressId": f"ghpr-{release_id}",
    "generatedBy": "build-gitops-adapter-handoff-progress.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_handoff_progress",
    "release": {
        "releaseId": release_id,
        "service": first_not_none(evidence.get("service"), release.get("service")),
        "env": first_not_none(evidence.get("env"), release.get("env"), environment.get("env")),
        "namespace": first_not_none(evidence.get("namespace"), release.get("namespace"), environment.get("namespace")),
        "policyDecision": first_not_none(evidence.get("policyDecision"), release.get("policyDecision")),
        "finalAction": first_not_none(evidence.get("finalAction"), release.get("finalAction")),
        "requestedAction": first_not_none(release.get("requestedAction"), evidence.get("requestedAction")),
    },
    "inputs": {
        "releaseEvidence": str(input_path),
        "gitopsAdapterHandoffPrep": str(handoff_prep_path) if handoff_prep_path else None,
        "gitopsAdapterPickupTransition": str(pickup_transition_path) if pickup_transition_path else None,
        "gitopsAdapterHandoffState": str(handoff_state_path) if handoff_state_path else None,
    },
    "handoffProgress": {
        "progressStatus": progress_status,
        "prepStatus": prep_status,
        "transitionStatus": nullable_string(handoff_prep_body.get("transitionStatus")),
        "eventStatus": nullable_string(handoff_prep_body.get("eventStatus")),
        "handoffStateStatus": nullable_string(first_not_none(
            handoff_prep_body.get("handoffStateStatus"),
            handoff_state_body.get("stateStatus"),
        )),
        "resultingStateStatus": nullable_string(handoff_prep_body.get("resultingStateStatus")),
        "pickupStatus": nullable_string(first_not_none(
            handoff_prep_body.get("pickupStatus"),
            pickup_transition_body.get("pickupStatus"),
        )),
        "ackStatus": nullable_string(first_not_none(
            handoff_prep_body.get("ackStatus"),
            pickup_transition_body.get("ackStatus"),
        )),
        "branchName": nullable_string(first_not_none(
            handoff_prep_body.get("branchName"),
            pickup_transition_body.get("branchName"),
            handoff_state_body.get("branchName"),
        )),
        "requestedOperation": nullable_string(first_not_none(
            handoff_prep_body.get("requestedOperation"),
            pickup_transition_body.get("requestedOperation"),
            handoff_state_body.get("requestedOperation"),
        )),
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "selectedEvent": nullable_string(handoff_prep_body.get("selectedEvent")),
        "selectedAction": selected_action,
        "actionSource": action_source,
        "currentCheckpoint": current_checkpoint,
        "nextCheckpoint": next_checkpoint,
        "currentActor": current_actor,
        "nextActor": next_actor,
        "workspaceArtifactCount": len(workspace_files),
        "summary": f"Handoff progress is {progress_status}; selectedAction is {selected_action or 'none'} and next checkpoint is {next_checkpoint}.",
        "progressControl": {
            "path": str(progress_control_path),
            "summaryPath": str(progress_control_summary_path),
            "generatedAt": now(),
            "localOnly": True,
        },
        "warnings": warnings,
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotModifyGitOps": True,
        "doesNotCommit": True,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotCallExternalGitProvider": True,
        "doesNotModifyKubernetes": True,
        "derivedFromGitopsAdapterHandoffPrep": as_dict(handoff_prep.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(handoff_progress, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterHandoffProgress"] = str(output_json)
evidence["gitopsAdapterHandoffProgressId"] = handoff_progress["gitopsAdapterHandoffProgressId"]
evidence["gitopsAdapterHandoffProgressRef"] = {
    "json": str(output_json),
    "progressStatus": handoff_progress["handoffProgress"]["progressStatus"],
    "nextCheckpoint": handoff_progress["handoffProgress"]["nextCheckpoint"],
    "workspaceArtifactCount": handoff_progress["handoffProgress"]["workspaceArtifactCount"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterHandoffProgress"] = {
    "gitopsAdapterHandoffProgressId": handoff_progress["gitopsAdapterHandoffProgressId"],
    "progressStatus": handoff_progress["handoffProgress"]["progressStatus"],
    "prepStatus": handoff_progress["handoffProgress"]["prepStatus"],
    "transitionStatus": handoff_progress["handoffProgress"]["transitionStatus"],
    "eventStatus": handoff_progress["handoffProgress"]["eventStatus"],
    "handoffStateStatus": handoff_progress["handoffProgress"]["handoffStateStatus"],
    "resultingStateStatus": handoff_progress["handoffProgress"]["resultingStateStatus"],
    "pickupStatus": handoff_progress["handoffProgress"]["pickupStatus"],
    "ackStatus": handoff_progress["handoffProgress"]["ackStatus"],
    "branchName": handoff_progress["handoffProgress"]["branchName"],
    "requestedOperation": handoff_progress["handoffProgress"]["requestedOperation"],
    "workspaceDir": handoff_progress["handoffProgress"]["workspaceDir"],
    "selectedEvent": handoff_progress["handoffProgress"]["selectedEvent"],
    "selectedAction": handoff_progress["handoffProgress"]["selectedAction"],
    "actionSource": handoff_progress["handoffProgress"]["actionSource"],
    "currentCheckpoint": handoff_progress["handoffProgress"]["currentCheckpoint"],
    "nextCheckpoint": handoff_progress["handoffProgress"]["nextCheckpoint"],
    "currentActor": handoff_progress["handoffProgress"]["currentActor"],
    "nextActor": handoff_progress["handoffProgress"]["nextActor"],
    "workspaceArtifactCount": handoff_progress["handoffProgress"]["workspaceArtifactCount"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter handoff progress generated: {output_json}")
print(f"Latest GitOps adapter handoff progress: {latest_json}")
print(f"GitOps adapter handoff progress linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterHandoffProgressId": handoff_progress["gitopsAdapterHandoffProgressId"],
    "releaseId": release_id,
    "progressStatus": handoff_progress["handoffProgress"]["progressStatus"],
    "selectedAction": handoff_progress["handoffProgress"]["selectedAction"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_HANDOFF_PROGRESS

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
