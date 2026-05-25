#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-handoff-state.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                        Optional report directory.
  GITOPS_ADAPTER_HANDOFF_STATE_OUTPUT_DIR  Optional output directory.
  GITOPS_ADAPTER_HANDOFF_STATE_OUTPUT_FILE Optional exact output file.

Behavior:
  - Reads release evidence, pickup, pickup acknowledgement, run, and delivery artifacts.
  - Generates gitops-adapter-handoff-state-*.json and gitops-adapter-handoff-state-latest.json.
  - Emits a local-only handoff lifecycle state; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_HANDOFF_STATE_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_HANDOFF_STATE_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-handoff-state-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-handoff-state-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_HANDOFF_STATE'
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


def progression_from(ack_status: str | None) -> tuple[str, str, str, str, str]:
    mapping = {
        "WAITING_FOR_ACK": (
            "READY_FOR_ACKNOWLEDGEMENT",
            "pickup_ack_pending",
            "acknowledge_pickup_workspace",
            "service_owner_or_release_operator",
            "service_owner_or_release_operator",
        ),
        "ACKNOWLEDGED": (
            "PICKUP_ACCEPTED",
            "pickup_acknowledged",
            "prepare_handoff_execution",
            "service_owner_or_release_operator",
            "platform_owner",
        ),
        "RETURNED": (
            "PICKUP_RETURNED",
            "pickup_returned",
            "revise_handoff_workspace",
            "service_owner_or_release_operator",
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
            "pickup_blocked",
            "resolve_pickup_blockers",
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
        "FAILED": (
            "FAILED",
            "pickup_ack_failed",
            "repair_handoff_state",
            "platform_owner",
            "platform_owner",
        ),
    }
    return mapping.get(ack_status or "", (
        "FAILED",
        "unknown_handoff_state",
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

run_path = resolve_ref(artifacts.get("gitopsAdapterRun"), input_path)
run = load_json(run_path)
run_body = as_dict(run.get("run"))

delivery_path = resolve_ref(artifacts.get("gitopsAdapterDelivery"), input_path)
delivery = load_json(delivery_path)
delivery_body = as_dict(delivery.get("delivery"))

release = as_dict(pickup_ack.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

state_status, current_checkpoint, next_checkpoint, current_actor, next_actor = progression_from(
    nullable_string(pickup_ack_body.get("ackStatus"))
)

workspace_dir = resolve_ref(first_not_none(
    pickup_ack_body.get("workspaceDir"),
    pickup_body.get("workspaceDir"),
), input_path)

state_control_path = workspace_dir / "handoff-state-control.json" if workspace_dir else output_json.parent / f"handoff-state-control-{release_id}.json"
state_control_summary_path = workspace_dir / "handoff-state-summary.md" if workspace_dir else output_json.parent / f"handoff-state-summary-{release_id}.md"
state_control_path.parent.mkdir(parents=True, exist_ok=True)

state_control = {
    "schemaVersion": "gitops.adapter.handoff.state.control/v1alpha1",
    "gitopsAdapterHandoffStateId": f"ghs-{release_id}",
    "generatedAt": now(),
    "stateStatus": state_status,
    "ackStatus": pickup_ack_body.get("ackStatus"),
    "pickupStatus": pickup_ack_body.get("pickupStatus"),
    "currentCheckpoint": current_checkpoint,
    "nextCheckpoint": next_checkpoint,
    "currentActor": current_actor,
    "nextActor": next_actor,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "localOnly": True,
}
state_control_path.write_text(json.dumps(state_control, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
state_control_summary_path.write_text(
    "# GitOps Handoff State\n\n"
    + f"- stateStatus: {state_status}\n"
    + f"- ackStatus: {pickup_ack_body.get('ackStatus')}\n"
    + f"- currentCheckpoint: {current_checkpoint}\n"
    + f"- nextCheckpoint: {next_checkpoint}\n"
    + f"- currentActor: {current_actor}\n"
    + f"- nextActor: {next_actor}\n",
    encoding="utf-8",
)

warnings = [str(item) for item in as_list(pickup_ack_body.get("warnings"))]
if state_status == "FAILED":
    warnings.append("handoff state progression failed because pickup acknowledgement could not be mapped to a lifecycle state")

handoff_state = {
    "schemaVersion": "gitops.adapter.handoff.state/v1alpha1",
    "gitopsAdapterHandoffStateId": f"ghs-{release_id}",
    "generatedBy": "build-gitops-adapter-handoff-state.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_handoff_state",
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
        "gitopsAdapterRun": str(run_path) if run_path else None,
        "gitopsAdapterDelivery": str(delivery_path) if delivery_path else None,
    },
    "handoffState": {
        "stateStatus": state_status,
        "ackStatus": nullable_string(pickup_ack_body.get("ackStatus")),
        "pickupStatus": nullable_string(first_not_none(
            pickup_ack_body.get("pickupStatus"),
            pickup_body.get("pickupStatus"),
        )),
        "branchName": nullable_string(first_not_none(
            pickup_ack_body.get("branchName"),
            pickup_body.get("branchName"),
            run_body.get("branchName"),
            delivery_body.get("branchName"),
        )),
        "requestedOperation": nullable_string(first_not_none(
            pickup_ack_body.get("requestedOperation"),
            pickup_body.get("requestedOperation"),
            run_body.get("requestedOperation"),
            delivery_body.get("requestedOperation"),
        )),
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "currentCheckpoint": current_checkpoint,
        "nextCheckpoint": next_checkpoint,
        "currentActor": current_actor,
        "nextActor": next_actor,
        "summary": f"Handoff state is {state_status}; current checkpoint is {current_checkpoint} and next checkpoint is {next_checkpoint}.",
        "stateControl": {
            "path": str(state_control_path),
            "summaryPath": str(state_control_summary_path),
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
        "derivedFromGitopsAdapterPickupAck": as_dict(pickup_ack.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(handoff_state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterHandoffState"] = str(output_json)
evidence["gitopsAdapterHandoffStateId"] = handoff_state["gitopsAdapterHandoffStateId"]
evidence["gitopsAdapterHandoffStateRef"] = {
    "json": str(output_json),
    "stateStatus": handoff_state["handoffState"]["stateStatus"],
    "ackStatus": handoff_state["handoffState"]["ackStatus"],
    "currentCheckpoint": handoff_state["handoffState"]["currentCheckpoint"],
    "nextCheckpoint": handoff_state["handoffState"]["nextCheckpoint"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterHandoffState"] = {
    "gitopsAdapterHandoffStateId": handoff_state["gitopsAdapterHandoffStateId"],
    "stateStatus": handoff_state["handoffState"]["stateStatus"],
    "ackStatus": handoff_state["handoffState"]["ackStatus"],
    "pickupStatus": handoff_state["handoffState"]["pickupStatus"],
    "branchName": handoff_state["handoffState"]["branchName"],
    "requestedOperation": handoff_state["handoffState"]["requestedOperation"],
    "workspaceDir": handoff_state["handoffState"]["workspaceDir"],
    "currentCheckpoint": handoff_state["handoffState"]["currentCheckpoint"],
    "nextCheckpoint": handoff_state["handoffState"]["nextCheckpoint"],
    "currentActor": handoff_state["handoffState"]["currentActor"],
    "nextActor": handoff_state["handoffState"]["nextActor"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter handoff state generated: {output_json}")
print(f"Latest GitOps adapter handoff state: {latest_json}")
print(f"GitOps adapter handoff state linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterHandoffStateId": handoff_state["gitopsAdapterHandoffStateId"],
    "releaseId": release_id,
    "stateStatus": handoff_state["handoffState"]["stateStatus"],
    "nextCheckpoint": handoff_state["handoffState"]["nextCheckpoint"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_HANDOFF_STATE

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
