#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-pickup-event.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                       Optional report directory.
  GITOPS_ADAPTER_PICKUP_EVENT_OUTPUT_DIR  Optional output directory.
  GITOPS_ADAPTER_PICKUP_EVENT_OUTPUT_FILE Optional exact output file.

Behavior:
  - Reads release evidence, pickup, pickup acknowledgement, and handoff state artifacts.
  - Generates gitops-adapter-pickup-event-*.json and gitops-adapter-pickup-event-latest.json.
  - Emits a local-only pickup event envelope; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_PICKUP_EVENT_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_PICKUP_EVENT_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-pickup-event-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-pickup-event-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_PICKUP_EVENT'
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


def event_from(state_status: str | None) -> tuple[str, str | None, list[str], str, str, str, str]:
    mapping = {
        "READY_FOR_ACKNOWLEDGEMENT": (
            "WAITING_FOR_EVENT",
            "ACCEPT_OR_RETURN_PICKUP",
            ["ACCEPT_PICKUP", "RETURN_PICKUP"],
            "pickup_ack_pending",
            "await_pickup_event",
            "service_owner_or_release_operator",
            "service_owner_or_release_operator",
        ),
        "PICKUP_ACCEPTED": (
            "PICKUP_ACCEPTED",
            "PREPARE_HANDOFF_EXECUTION",
            ["START_HANDOFF"],
            "pickup_acknowledged",
            "prepare_handoff_execution",
            "service_owner_or_release_operator",
            "platform_owner",
        ),
        "PICKUP_RETURNED": (
            "PICKUP_RETURNED",
            "REVISE_HANDOFF_WORKSPACE",
            ["REVISE_HANDOFF"],
            "pickup_returned",
            "revise_handoff_workspace",
            "service_owner_or_release_operator",
            "platform_owner",
        ),
        "HANDOFF_IN_PROGRESS": (
            "HANDOFF_IN_PROGRESS",
            "COMPLETE_HANDOFF",
            ["COMPLETE_HANDOFF", "RETURN_PICKUP"],
            "handoff_in_progress",
            "complete_handoff",
            "platform_owner",
            "platform_owner",
        ),
        "HANDOFF_COMPLETED": (
            "HANDOFF_COMPLETED",
            None,
            [],
            "handoff_completed",
            "archive_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
        "WAITING_APPROVAL": (
            "WAITING_APPROVAL",
            "WAIT_FOR_APPROVAL",
            ["WAIT_FOR_APPROVAL"],
            "approval_gate_pending",
            "await_manual_approval",
            "approver",
            "approver",
        ),
        "BLOCKED": (
            "BLOCKED",
            "UNBLOCK_HANDOFF",
            ["RESOLVE_BLOCKERS"],
            "pickup_blocked",
            "resolve_pickup_blockers",
            "platform_owner",
            "platform_owner",
        ),
        "NO_ACTION_REQUIRED": (
            "NO_ACTION_REQUIRED",
            None,
            [],
            "handoff_not_required",
            "archive_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
        "FAILED": (
            "FAILED",
            "REPAIR_HANDOFF_STATE",
            ["REPAIR_HANDOFF_STATE"],
            "pickup_event_failed",
            "repair_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
    }
    return mapping.get(state_status or "", (
        "FAILED",
        "REPAIR_HANDOFF_STATE",
        ["REPAIR_HANDOFF_STATE"],
        "unknown_pickup_event",
        "repair_handoff_state",
        "platform_owner",
        "platform_owner",
    ))


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

pickup_path = resolve_ref(artifacts.get("gitopsAdapterPickup"), input_path)
pickup = load_json(pickup_path)
pickup_body = as_dict(pickup.get("pickup"))

pickup_ack_path = resolve_ref(artifacts.get("gitopsAdapterPickupAck"), input_path)
pickup_ack = load_json(pickup_ack_path)
pickup_ack_body = as_dict(pickup_ack.get("acknowledgement"))

handoff_state_path = resolve_ref(artifacts.get("gitopsAdapterHandoffState"), input_path)
handoff_state = load_json(handoff_state_path)
handoff_state_body = as_dict(handoff_state.get("handoffState"))

release = as_dict(handoff_state.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

event_status, expected_event, allowed_events, current_checkpoint, next_checkpoint, current_actor, next_actor = event_from(
    nullable_string(handoff_state_body.get("stateStatus"))
)

workspace_dir = resolve_ref(first_not_none(
    handoff_state_body.get("workspaceDir"),
    pickup_ack_body.get("workspaceDir"),
    pickup_body.get("workspaceDir"),
), input_path)

event_control_path = workspace_dir / "pickup-event-control.json" if workspace_dir else output_json.parent / f"pickup-event-control-{release_id}.json"
event_control_summary_path = workspace_dir / "pickup-event-summary.md" if workspace_dir else output_json.parent / f"pickup-event-summary-{release_id}.md"
event_control_path.parent.mkdir(parents=True, exist_ok=True)

event_control = {
    "schemaVersion": "gitops.adapter.pickup.event.control/v1alpha1",
    "gitopsAdapterPickupEventId": f"gpe-{release_id}",
    "generatedAt": now(),
    "eventStatus": event_status,
    "expectedEvent": expected_event,
    "allowedEvents": allowed_events,
    "currentCheckpoint": current_checkpoint,
    "nextCheckpoint": next_checkpoint,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "localOnly": True,
}
event_control_path.write_text(json.dumps(event_control, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
event_control_summary_path.write_text(
    "# GitOps Pickup Event\n\n"
    + f"- eventStatus: {event_status}\n"
    + f"- expectedEvent: {expected_event}\n"
    + f"- allowedEvents: {', '.join(allowed_events) if allowed_events else 'none'}\n"
    + f"- currentCheckpoint: {current_checkpoint}\n"
    + f"- nextCheckpoint: {next_checkpoint}\n",
    encoding="utf-8",
)

warnings = [
    str(item)
    for item in as_list(first_not_none(
        handoff_state_body.get("warnings"),
        pickup_ack_body.get("warnings"),
        pickup_body.get("warnings"),
    ))
]
if event_status == "FAILED":
    warnings.append("pickup event generation failed because handoff state could not be mapped to a valid event envelope")

pickup_event = {
    "schemaVersion": "gitops.adapter.pickup.event/v1alpha1",
    "gitopsAdapterPickupEventId": f"gpe-{release_id}",
    "generatedBy": "build-gitops-adapter-pickup-event.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_pickup_event",
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
        "gitopsAdapterPickup": str(pickup_path) if pickup_path else None,
        "gitopsAdapterPickupAck": str(pickup_ack_path) if pickup_ack_path else None,
        "gitopsAdapterHandoffState": str(handoff_state_path) if handoff_state_path else None,
    },
    "pickupEvent": {
        "eventStatus": event_status,
        "handoffStateStatus": nullable_string(handoff_state_body.get("stateStatus")),
        "pickupStatus": nullable_string(first_not_none(
            handoff_state_body.get("pickupStatus"),
            pickup_ack_body.get("pickupStatus"),
            pickup_body.get("pickupStatus"),
        )),
        "ackStatus": nullable_string(first_not_none(
            handoff_state_body.get("ackStatus"),
            pickup_ack_body.get("ackStatus"),
        )),
        "branchName": nullable_string(first_not_none(
            handoff_state_body.get("branchName"),
            pickup_ack_body.get("branchName"),
            pickup_body.get("branchName"),
        )),
        "requestedOperation": nullable_string(first_not_none(
            handoff_state_body.get("requestedOperation"),
            pickup_ack_body.get("requestedOperation"),
            pickup_body.get("requestedOperation"),
        )),
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "currentCheckpoint": current_checkpoint,
        "nextCheckpoint": next_checkpoint,
        "currentActor": current_actor,
        "nextActor": next_actor,
        "expectedEvent": expected_event,
        "allowedEvents": allowed_events,
        "summary": f"Pickup event is {event_status}; control plane expects {expected_event or 'no further event'} at checkpoint {next_checkpoint}.",
        "eventControl": {
            "path": str(event_control_path),
            "summaryPath": str(event_control_summary_path),
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
        "derivedFromGitopsAdapterHandoffState": as_dict(handoff_state.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(pickup_event, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterPickupEvent"] = str(output_json)
evidence["gitopsAdapterPickupEventId"] = pickup_event["gitopsAdapterPickupEventId"]
evidence["gitopsAdapterPickupEventRef"] = {
    "json": str(output_json),
    "eventStatus": pickup_event["pickupEvent"]["eventStatus"],
    "expectedEvent": pickup_event["pickupEvent"]["expectedEvent"],
    "nextCheckpoint": pickup_event["pickupEvent"]["nextCheckpoint"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterPickupEvent"] = {
    "gitopsAdapterPickupEventId": pickup_event["gitopsAdapterPickupEventId"],
    "eventStatus": pickup_event["pickupEvent"]["eventStatus"],
    "handoffStateStatus": pickup_event["pickupEvent"]["handoffStateStatus"],
    "pickupStatus": pickup_event["pickupEvent"]["pickupStatus"],
    "ackStatus": pickup_event["pickupEvent"]["ackStatus"],
    "branchName": pickup_event["pickupEvent"]["branchName"],
    "requestedOperation": pickup_event["pickupEvent"]["requestedOperation"],
    "workspaceDir": pickup_event["pickupEvent"]["workspaceDir"],
    "currentCheckpoint": pickup_event["pickupEvent"]["currentCheckpoint"],
    "nextCheckpoint": pickup_event["pickupEvent"]["nextCheckpoint"],
    "currentActor": pickup_event["pickupEvent"]["currentActor"],
    "nextActor": pickup_event["pickupEvent"]["nextActor"],
    "expectedEvent": pickup_event["pickupEvent"]["expectedEvent"],
    "allowedEvents": pickup_event["pickupEvent"]["allowedEvents"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter pickup event generated: {output_json}")
print(f"Latest GitOps adapter pickup event: {latest_json}")
print(f"GitOps adapter pickup event linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterPickupEventId": pickup_event["gitopsAdapterPickupEventId"],
    "releaseId": release_id,
    "eventStatus": pickup_event["pickupEvent"]["eventStatus"],
    "expectedEvent": pickup_event["pickupEvent"]["expectedEvent"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_PICKUP_EVENT

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
