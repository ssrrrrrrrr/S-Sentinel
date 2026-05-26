#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-handoff-prep.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                           Optional report directory.
  GITOPS_ADAPTER_HANDOFF_PREP_OUTPUT_DIR      Optional output directory.
  GITOPS_ADAPTER_HANDOFF_PREP_OUTPUT_FILE     Optional exact output file.

Behavior:
  - Reads release evidence, pickup transition, pickup event, and handoff state artifacts.
  - Generates gitops-adapter-handoff-prep-*.json and gitops-adapter-handoff-prep-latest.json.
  - Derives a local-only handoff prep result; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_HANDOFF_PREP_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_HANDOFF_PREP_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-handoff-prep-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-handoff-prep-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_HANDOFF_PREP'
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


def checklist_for_status(prep_status: str) -> list[str]:
    if prep_status == "PREPARED_FOR_HANDOFF":
        return [
            "verify_handoff_workspace",
            "verify_branch_metadata",
            "verify_handoff_manifest",
        ]
    if prep_status == "RETURNED_FOR_REWORK":
        return [
            "revise_handoff_workspace",
            "refresh_pickup_transition",
        ]
    if prep_status == "HANDOFF_IN_PROGRESS":
        return [
            "continue_handoff_execution",
            "capture_progress_receipt",
        ]
    if prep_status == "HANDOFF_COMPLETED":
        return [
            "archive_handoff_workspace",
            "capture_completion_receipt",
        ]
    if prep_status == "WAITING_APPROVAL":
        return [
            "await_manual_approval",
            "preserve_handoff_workspace",
        ]
    if prep_status == "BLOCKED":
        return [
            "resolve_handoff_blockers",
            "rebuild_handoff_prep",
        ]
    if prep_status == "NO_ACTION_REQUIRED":
        return [
            "archive_handoff_state",
        ]
    if prep_status == "WAITING_FOR_PREP":
        return [
            "await_pickup_resolution",
        ]
    return [
        "repair_handoff_prep_state",
    ]


def prep_from_transition(transition_status: str | None) -> tuple[str, str, str, str, str]:
    mapping = {
        "WAITING_FOR_RESOLUTION": (
            "WAITING_FOR_PREP",
            "await_pickup_resolution",
            "wait_for_pickup_resolution",
            "service_owner_or_release_operator",
            "service_owner_or_release_operator",
        ),
        "PICKUP_ACCEPTED": (
            "PREPARED_FOR_HANDOFF",
            "handoff_preparation_started",
            "begin_handoff_execution",
            "platform_owner",
            "platform_owner",
        ),
        "PICKUP_RETURNED": (
            "RETURNED_FOR_REWORK",
            "pickup_return_recorded",
            "revise_handoff_workspace",
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
        "WAITING_APPROVAL": (
            "WAITING_APPROVAL",
            "approval_gate_pending",
            "await_manual_approval",
            "approver",
            "approver",
        ),
        "BLOCKED": (
            "BLOCKED",
            "handoff_prep_blocked",
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
        "INVALID_RESPONSE": (
            "INVALID_TRANSITION",
            "invalid_pickup_transition",
            "repair_handoff_prep_state",
            "platform_owner",
            "platform_owner",
        ),
        "FAILED": (
            "FAILED",
            "handoff_prep_failed",
            "repair_handoff_prep_state",
            "platform_owner",
            "platform_owner",
        ),
    }
    return mapping.get(
        transition_status,
        (
            "FAILED",
            "unknown_handoff_prep_state",
            "repair_handoff_prep_state",
            "platform_owner",
            "platform_owner",
        ),
    )


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

pickup_transition_path = resolve_ref(artifacts.get("gitopsAdapterPickupTransition"), input_path)
pickup_transition = load_json(pickup_transition_path)
pickup_transition_body = as_dict(pickup_transition.get("pickupTransition"))

pickup_event_path = resolve_ref(artifacts.get("gitopsAdapterPickupEvent"), input_path)
pickup_event = load_json(pickup_event_path)
pickup_event_body = as_dict(pickup_event.get("pickupEvent"))

handoff_state_path = resolve_ref(artifacts.get("gitopsAdapterHandoffState"), input_path)
handoff_state = load_json(handoff_state_path)
handoff_state_body = as_dict(handoff_state.get("handoffState"))

release = as_dict(pickup_transition.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

transition_status = nullable_string(pickup_transition_body.get("transitionStatus"))
prep_status, current_checkpoint, next_checkpoint, current_actor, next_actor = prep_from_transition(transition_status)
workspace_dir = resolve_ref(first_not_none(
    pickup_transition_body.get("workspaceDir"),
    pickup_event_body.get("workspaceDir"),
    handoff_state_body.get("workspaceDir"),
), input_path)

materialized_files = []
if workspace_dir and workspace_dir.exists():
    try:
        materialized_files = sorted(
            [str(item) for item in workspace_dir.rglob("*") if item.is_file()]
        )
    except OSError:
        materialized_files = []

prep_control_path = workspace_dir / "handoff-prep-control.json" if workspace_dir else output_json.parent / f"handoff-prep-control-{release_id}.json"
prep_control_summary_path = workspace_dir / "handoff-prep-summary.md" if workspace_dir else output_json.parent / f"handoff-prep-summary-{release_id}.md"
prep_control_path.parent.mkdir(parents=True, exist_ok=True)

prep_checklist = checklist_for_status(prep_status)

prep_control = {
    "schemaVersion": "gitops.adapter.handoff.prep.control/v1alpha1",
    "gitopsAdapterHandoffPrepId": f"ghp-{release_id}",
    "generatedAt": now(),
    "prepStatus": prep_status,
    "transitionStatus": transition_status,
    "currentCheckpoint": current_checkpoint,
    "nextCheckpoint": next_checkpoint,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "preparedArtifactCount": len(materialized_files),
    "localOnly": True,
}
prep_control_path.write_text(json.dumps(prep_control, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
prep_control_summary_path.write_text(
    "# GitOps Handoff Prep\n\n"
    + f"- prepStatus: {prep_status}\n"
    + f"- transitionStatus: {transition_status or 'none'}\n"
    + f"- currentCheckpoint: {current_checkpoint}\n"
    + f"- nextCheckpoint: {next_checkpoint}\n"
    + f"- preparedArtifactCount: {len(materialized_files)}\n",
    encoding="utf-8",
)

warnings = [str(item) for item in as_list(pickup_transition_body.get("warnings"))]
if not pickup_transition_path:
    warnings.append("gitops adapter handoff prep could not resolve pickup transition input")
if prep_status == "FAILED":
    warnings.append("gitops adapter handoff prep fell back to failed state mapping")

handoff_prep = {
    "schemaVersion": "gitops.adapter.handoff.prep/v1alpha1",
    "gitopsAdapterHandoffPrepId": f"ghp-{release_id}",
    "generatedBy": "build-gitops-adapter-handoff-prep.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_handoff_prep",
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
        "gitopsAdapterPickupTransition": str(pickup_transition_path) if pickup_transition_path else None,
        "gitopsAdapterPickupEvent": str(pickup_event_path) if pickup_event_path else None,
        "gitopsAdapterHandoffState": str(handoff_state_path) if handoff_state_path else None,
    },
    "handoffPrep": {
        "prepStatus": prep_status,
        "transitionStatus": transition_status,
        "eventStatus": nullable_string(first_not_none(
            pickup_transition_body.get("eventStatus"),
            pickup_event_body.get("eventStatus"),
        )),
        "handoffStateStatus": nullable_string(first_not_none(
            pickup_transition_body.get("handoffStateStatus"),
            handoff_state_body.get("stateStatus"),
        )),
        "resultingStateStatus": nullable_string(pickup_transition_body.get("resultingStateStatus")),
        "pickupStatus": nullable_string(first_not_none(
            pickup_transition_body.get("pickupStatus"),
            pickup_event_body.get("pickupStatus"),
        )),
        "ackStatus": nullable_string(first_not_none(
            pickup_transition_body.get("ackStatus"),
            pickup_event_body.get("ackStatus"),
        )),
        "branchName": nullable_string(first_not_none(
            pickup_transition_body.get("branchName"),
            pickup_event_body.get("branchName"),
            handoff_state_body.get("branchName"),
        )),
        "requestedOperation": nullable_string(first_not_none(
            pickup_transition_body.get("requestedOperation"),
            pickup_event_body.get("requestedOperation"),
            handoff_state_body.get("requestedOperation"),
        )),
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "selectedEvent": nullable_string(pickup_transition_body.get("selectedEvent")),
        "responseSource": nullable_string(pickup_transition_body.get("responseSource")),
        "currentCheckpoint": current_checkpoint,
        "nextCheckpoint": next_checkpoint,
        "currentActor": current_actor,
        "nextActor": next_actor,
        "preparedArtifactCount": len(materialized_files),
        "prepChecklist": prep_checklist,
        "summary": f"Handoff prep is {prep_status}; transition status is {transition_status or 'none'} and next checkpoint is {next_checkpoint}.",
        "prepControl": {
            "path": str(prep_control_path),
            "summaryPath": str(prep_control_summary_path),
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
        "derivedFromGitopsAdapterPickupTransition": as_dict(pickup_transition.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(handoff_prep, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterHandoffPrep"] = str(output_json)
evidence["gitopsAdapterHandoffPrepId"] = handoff_prep["gitopsAdapterHandoffPrepId"]
evidence["gitopsAdapterHandoffPrepRef"] = {
    "json": str(output_json),
    "prepStatus": handoff_prep["handoffPrep"]["prepStatus"],
    "nextCheckpoint": handoff_prep["handoffPrep"]["nextCheckpoint"],
    "preparedArtifactCount": handoff_prep["handoffPrep"]["preparedArtifactCount"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterHandoffPrep"] = {
    "gitopsAdapterHandoffPrepId": handoff_prep["gitopsAdapterHandoffPrepId"],
    "prepStatus": handoff_prep["handoffPrep"]["prepStatus"],
    "transitionStatus": handoff_prep["handoffPrep"]["transitionStatus"],
    "eventStatus": handoff_prep["handoffPrep"]["eventStatus"],
    "handoffStateStatus": handoff_prep["handoffPrep"]["handoffStateStatus"],
    "resultingStateStatus": handoff_prep["handoffPrep"]["resultingStateStatus"],
    "pickupStatus": handoff_prep["handoffPrep"]["pickupStatus"],
    "ackStatus": handoff_prep["handoffPrep"]["ackStatus"],
    "branchName": handoff_prep["handoffPrep"]["branchName"],
    "requestedOperation": handoff_prep["handoffPrep"]["requestedOperation"],
    "workspaceDir": handoff_prep["handoffPrep"]["workspaceDir"],
    "selectedEvent": handoff_prep["handoffPrep"]["selectedEvent"],
    "responseSource": handoff_prep["handoffPrep"]["responseSource"],
    "currentCheckpoint": handoff_prep["handoffPrep"]["currentCheckpoint"],
    "nextCheckpoint": handoff_prep["handoffPrep"]["nextCheckpoint"],
    "currentActor": handoff_prep["handoffPrep"]["currentActor"],
    "nextActor": handoff_prep["handoffPrep"]["nextActor"],
    "preparedArtifactCount": handoff_prep["handoffPrep"]["preparedArtifactCount"],
    "prepChecklist": handoff_prep["handoffPrep"]["prepChecklist"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter handoff prep generated: {output_json}")
print(f"Latest GitOps adapter handoff prep: {latest_json}")
print(f"GitOps adapter handoff prep linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterHandoffPrepId": handoff_prep["gitopsAdapterHandoffPrepId"],
    "releaseId": release_id,
    "prepStatus": handoff_prep["handoffPrep"]["prepStatus"],
    "transitionStatus": handoff_prep["handoffPrep"]["transitionStatus"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_HANDOFF_PREP

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
