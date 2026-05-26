#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-pickup-transition.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                            Optional report directory.
  GITOPS_ADAPTER_PICKUP_TRANSITION_OUTPUT_DIR  Optional output directory.
  GITOPS_ADAPTER_PICKUP_TRANSITION_OUTPUT_FILE Optional exact output file.
  GITOPS_ADAPTER_PICKUP_RESPONSE               Optional local response: ACCEPT_PICKUP or RETURN_PICKUP.

Behavior:
  - Reads release evidence, pickup event, and handoff state artifacts.
  - Generates gitops-adapter-pickup-transition-*.json and gitops-adapter-pickup-transition-latest.json.
  - Derives a local-only transition result; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_PICKUP_TRANSITION_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_PICKUP_TRANSITION_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-pickup-transition-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-pickup-transition-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_PICKUP_TRANSITION'
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


def normalized_response(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip().upper()
    return text if text else None


def transition_from(
    event_status: str | None,
    selected_event: str | None,
    allowed_events: list[str],
) -> tuple[str, str | None, str, str, str, str, list[str]]:
    allowed = {item.upper() for item in allowed_events}
    warnings: list[str] = []

    if event_status == "WAITING_FOR_EVENT":
        if selected_event is None:
            return (
                "WAITING_FOR_RESOLUTION",
                "READY_FOR_ACKNOWLEDGEMENT",
                "await_pickup_response",
                "wait_for_pickup_resolution",
                "service_owner_or_release_operator",
                "service_owner_or_release_operator",
                warnings,
            )
        if selected_event not in allowed:
            warnings.append(f"selected pickup event {selected_event} is not allowed by the current event envelope")
            return (
                "INVALID_RESPONSE",
                "READY_FOR_ACKNOWLEDGEMENT",
                "invalid_pickup_response",
                "repair_pickup_resolution",
                "platform_owner",
                "platform_owner",
                warnings,
            )
        if selected_event == "ACCEPT_PICKUP":
            return (
                "PICKUP_ACCEPTED",
                "PICKUP_ACCEPTED",
                "pickup_response_recorded",
                "prepare_handoff_execution",
                "service_owner_or_release_operator",
                "platform_owner",
                warnings,
            )
        if selected_event == "RETURN_PICKUP":
            return (
                "PICKUP_RETURNED",
                "PICKUP_RETURNED",
                "pickup_response_recorded",
                "revise_handoff_workspace",
                "service_owner_or_release_operator",
                "platform_owner",
                warnings,
            )

    static_mapping = {
        "PICKUP_ACCEPTED": (
            "PICKUP_ACCEPTED",
            "PICKUP_ACCEPTED",
            "pickup_acknowledged",
            "prepare_handoff_execution",
            "service_owner_or_release_operator",
            "platform_owner",
        ),
        "PICKUP_RETURNED": (
            "PICKUP_RETURNED",
            "PICKUP_RETURNED",
            "pickup_returned",
            "revise_handoff_workspace",
            "service_owner_or_release_operator",
            "platform_owner",
        ),
        "HANDOFF_IN_PROGRESS": (
            "HANDOFF_IN_PROGRESS",
            "HANDOFF_IN_PROGRESS",
            "handoff_in_progress",
            "complete_handoff",
            "platform_owner",
            "platform_owner",
        ),
        "HANDOFF_COMPLETED": (
            "HANDOFF_COMPLETED",
            "HANDOFF_COMPLETED",
            "handoff_completed",
            "archive_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
        "WAITING_APPROVAL": (
            "WAITING_APPROVAL",
            "WAITING_APPROVAL",
            "approval_gate_pending",
            "await_manual_approval",
            "approver",
            "approver",
        ),
        "BLOCKED": (
            "BLOCKED",
            "BLOCKED",
            "pickup_blocked",
            "resolve_pickup_blockers",
            "platform_owner",
            "platform_owner",
        ),
        "NO_ACTION_REQUIRED": (
            "NO_ACTION_REQUIRED",
            "NO_ACTION_REQUIRED",
            "handoff_not_required",
            "archive_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
        "FAILED": (
            "FAILED",
            "FAILED",
            "pickup_event_failed",
            "repair_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
    }

    if event_status in static_mapping:
        transition_status, resulting_state_status, current_checkpoint, next_checkpoint, current_actor, next_actor = static_mapping[event_status]
        return (
            transition_status,
            resulting_state_status,
            current_checkpoint,
            next_checkpoint,
            current_actor,
            next_actor,
            warnings,
        )

    warnings.append("pickup transition could not map the current event state")
    return (
        "FAILED",
        None,
        "unknown_pickup_transition",
        "repair_handoff_state",
        "platform_owner",
        "platform_owner",
        warnings,
    )


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

pickup_event_path = resolve_ref(artifacts.get("gitopsAdapterPickupEvent"), input_path)
pickup_event = load_json(pickup_event_path)
pickup_event_body = as_dict(pickup_event.get("pickupEvent"))

handoff_state_path = resolve_ref(artifacts.get("gitopsAdapterHandoffState"), input_path)
handoff_state = load_json(handoff_state_path)
handoff_state_body = as_dict(handoff_state.get("handoffState"))

release = as_dict(pickup_event.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

selected_event = normalized_response(os.environ.get("GITOPS_ADAPTER_PICKUP_RESPONSE"))
allowed_events = [str(item) for item in as_list(pickup_event_body.get("allowedEvents"))]
transition_status, resulting_state_status, current_checkpoint, next_checkpoint, current_actor, next_actor, transition_warnings = transition_from(
    nullable_string(pickup_event_body.get("eventStatus")),
    selected_event,
    allowed_events,
)

response_source = "env:GITOPS_ADAPTER_PICKUP_RESPONSE" if selected_event else "pending_local_response"

workspace_dir = resolve_ref(first_not_none(
    pickup_event_body.get("workspaceDir"),
    handoff_state_body.get("workspaceDir"),
), input_path)

transition_control_path = workspace_dir / "pickup-transition-control.json" if workspace_dir else output_json.parent / f"pickup-transition-control-{release_id}.json"
transition_control_summary_path = workspace_dir / "pickup-transition-summary.md" if workspace_dir else output_json.parent / f"pickup-transition-summary-{release_id}.md"
transition_control_path.parent.mkdir(parents=True, exist_ok=True)

transition_control = {
    "schemaVersion": "gitops.adapter.pickup.transition.control/v1alpha1",
    "gitopsAdapterPickupTransitionId": f"gptn-{release_id}",
    "generatedAt": now(),
    "transitionStatus": transition_status,
    "selectedEvent": selected_event,
    "responseSource": response_source,
    "resultingStateStatus": resulting_state_status,
    "currentCheckpoint": current_checkpoint,
    "nextCheckpoint": next_checkpoint,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "localOnly": True,
}
transition_control_path.write_text(json.dumps(transition_control, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
transition_control_summary_path.write_text(
    "# GitOps Pickup Transition\n\n"
    + f"- transitionStatus: {transition_status}\n"
    + f"- selectedEvent: {selected_event or 'none'}\n"
    + f"- responseSource: {response_source}\n"
    + f"- resultingStateStatus: {resulting_state_status or 'none'}\n"
    + f"- currentCheckpoint: {current_checkpoint}\n"
    + f"- nextCheckpoint: {next_checkpoint}\n",
    encoding="utf-8",
)

warnings = [str(item) for item in as_list(pickup_event_body.get("warnings"))]
warnings.extend(transition_warnings)

pickup_transition = {
    "schemaVersion": "gitops.adapter.pickup.transition/v1alpha1",
    "gitopsAdapterPickupTransitionId": f"gptn-{release_id}",
    "generatedBy": "build-gitops-adapter-pickup-transition.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_pickup_transition",
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
        "gitopsAdapterPickupEvent": str(pickup_event_path) if pickup_event_path else None,
        "gitopsAdapterHandoffState": str(handoff_state_path) if handoff_state_path else None,
    },
    "pickupTransition": {
        "transitionStatus": transition_status,
        "eventStatus": nullable_string(pickup_event_body.get("eventStatus")),
        "handoffStateStatus": nullable_string(first_not_none(
            pickup_event_body.get("handoffStateStatus"),
            handoff_state_body.get("stateStatus"),
        )),
        "pickupStatus": nullable_string(pickup_event_body.get("pickupStatus")),
        "ackStatus": nullable_string(pickup_event_body.get("ackStatus")),
        "branchName": nullable_string(pickup_event_body.get("branchName")),
        "requestedOperation": nullable_string(pickup_event_body.get("requestedOperation")),
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "requestedEvent": nullable_string(pickup_event_body.get("expectedEvent")),
        "selectedEvent": selected_event,
        "allowedEvents": allowed_events,
        "responseSource": response_source,
        "resultingStateStatus": resulting_state_status,
        "currentCheckpoint": current_checkpoint,
        "nextCheckpoint": next_checkpoint,
        "currentActor": current_actor,
        "nextActor": next_actor,
        "summary": f"Pickup transition is {transition_status}; selectedEvent is {selected_event or 'none'} and next checkpoint is {next_checkpoint}.",
        "transitionControl": {
            "path": str(transition_control_path),
            "summaryPath": str(transition_control_summary_path),
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
        "derivedFromGitopsAdapterPickupEvent": as_dict(pickup_event.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(pickup_transition, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterPickupTransition"] = str(output_json)
evidence["gitopsAdapterPickupTransitionId"] = pickup_transition["gitopsAdapterPickupTransitionId"]
evidence["gitopsAdapterPickupTransitionRef"] = {
    "json": str(output_json),
    "transitionStatus": pickup_transition["pickupTransition"]["transitionStatus"],
    "selectedEvent": pickup_transition["pickupTransition"]["selectedEvent"],
    "nextCheckpoint": pickup_transition["pickupTransition"]["nextCheckpoint"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterPickupTransition"] = {
    "gitopsAdapterPickupTransitionId": pickup_transition["gitopsAdapterPickupTransitionId"],
    "transitionStatus": pickup_transition["pickupTransition"]["transitionStatus"],
    "eventStatus": pickup_transition["pickupTransition"]["eventStatus"],
    "handoffStateStatus": pickup_transition["pickupTransition"]["handoffStateStatus"],
    "pickupStatus": pickup_transition["pickupTransition"]["pickupStatus"],
    "ackStatus": pickup_transition["pickupTransition"]["ackStatus"],
    "branchName": pickup_transition["pickupTransition"]["branchName"],
    "requestedOperation": pickup_transition["pickupTransition"]["requestedOperation"],
    "workspaceDir": pickup_transition["pickupTransition"]["workspaceDir"],
    "requestedEvent": pickup_transition["pickupTransition"]["requestedEvent"],
    "selectedEvent": pickup_transition["pickupTransition"]["selectedEvent"],
    "responseSource": pickup_transition["pickupTransition"]["responseSource"],
    "resultingStateStatus": pickup_transition["pickupTransition"]["resultingStateStatus"],
    "currentCheckpoint": pickup_transition["pickupTransition"]["currentCheckpoint"],
    "nextCheckpoint": pickup_transition["pickupTransition"]["nextCheckpoint"],
    "currentActor": pickup_transition["pickupTransition"]["currentActor"],
    "nextActor": pickup_transition["pickupTransition"]["nextActor"],
    "allowedEvents": pickup_transition["pickupTransition"]["allowedEvents"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter pickup transition generated: {output_json}")
print(f"Latest GitOps adapter pickup transition: {latest_json}")
print(f"GitOps adapter pickup transition linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterPickupTransitionId": pickup_transition["gitopsAdapterPickupTransitionId"],
    "releaseId": release_id,
    "transitionStatus": pickup_transition["pickupTransition"]["transitionStatus"],
    "selectedEvent": pickup_transition["pickupTransition"]["selectedEvent"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_PICKUP_TRANSITION

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
