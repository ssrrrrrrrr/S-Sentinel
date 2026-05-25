#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-pickup-ack.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                      Optional report directory.
  GITOPS_ADAPTER_PICKUP_ACK_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_PICKUP_ACK_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, pickup, run, and delivery artifacts.
  - Generates gitops-adapter-pickup-ack-*.json and gitops-adapter-pickup-ack-latest.json.
  - Emits a local-only acknowledgement control receipt; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_PICKUP_ACK_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_PICKUP_ACK_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-pickup-ack-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-pickup-ack-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_PICKUP_ACK'
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


def ack_status_from(pickup_status: str | None) -> str:
    if pickup_status == "READY_FOR_PICKUP":
        return "WAITING_FOR_ACK"
    if pickup_status in {"BLOCKED", "WAITING_APPROVAL", "NO_ACTION_REQUIRED", "FAILED"}:
        return str(pickup_status)
    return "FAILED"


def checkpoint_from(ack_status: str) -> tuple[str, str]:
    mapping = {
        "WAITING_FOR_ACK": ("acknowledge_pickup_workspace", "service_owner_or_release_operator"),
        "WAITING_APPROVAL": ("await_manual_approval", "approver"),
        "BLOCKED": ("resolve_pickup_blockers", "platform_owner"),
        "NO_ACTION_REQUIRED": ("archive_pickup_ack", "platform_owner"),
        "FAILED": ("repair_pickup_state", "platform_owner"),
    }
    return mapping.get(ack_status, ("investigate_pickup_ack_state", "platform_owner"))


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

pickup_path = resolve_ref(artifacts.get("gitopsAdapterPickup"), input_path)
pickup = load_json(pickup_path)
pickup_body = as_dict(pickup.get("pickup"))

run_path = resolve_ref(artifacts.get("gitopsAdapterRun"), input_path)
run = load_json(run_path)
run_body = as_dict(run.get("run"))

delivery_path = resolve_ref(artifacts.get("gitopsAdapterDelivery"), input_path)
delivery = load_json(delivery_path)
delivery_body = as_dict(delivery.get("delivery"))

release = as_dict(pickup.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

workspace_dir = resolve_ref(pickup_body.get("workspaceDir"), input_path)
pickup_status = nullable_string(pickup_body.get("pickupStatus"))
ack_status = ack_status_from(pickup_status)
next_checkpoint, assigned_actor = checkpoint_from(ack_status)

ack_control_path = workspace_dir / "pickup-ack-control.json" if workspace_dir else output_json.parent / f"pickup-ack-control-{release_id}.json"
ack_control_summary_path = workspace_dir / "pickup-ack-summary.md" if workspace_dir else output_json.parent / f"pickup-ack-summary-{release_id}.md"
ack_control_path.parent.mkdir(parents=True, exist_ok=True)

ack_control = {
    "schemaVersion": "gitops.adapter.pickup.ack.control/v1alpha1",
    "gitopsAdapterPickupAckId": f"gack-{release_id}",
    "generatedAt": now(),
    "ackStatus": ack_status,
    "pickupStatus": pickup_status,
    "nextCheckpoint": next_checkpoint,
    "assignedActor": assigned_actor,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "localOnly": True,
}
ack_control_path.write_text(json.dumps(ack_control, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
ack_control_summary_path.write_text(
    "# GitOps Pickup Acknowledgement\n\n"
    + f"- ackStatus: {ack_status}\n"
    + f"- pickupStatus: {pickup_status}\n"
    + f"- nextCheckpoint: {next_checkpoint}\n"
    + f"- assignedActor: {assigned_actor}\n",
    encoding="utf-8",
)

warnings = [str(item) for item in as_list(pickup_body.get("warnings"))]
if ack_status == "FAILED":
    warnings.append("pickup acknowledgement failed because the pickup state was not ready for acknowledgement")

ack = {
    "schemaVersion": "gitops.adapter.pickup.ack/v1alpha1",
    "gitopsAdapterPickupAckId": f"gack-{release_id}",
    "generatedBy": "build-gitops-adapter-pickup-ack.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_pickup_ack",
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
        "gitopsAdapterRun": str(run_path) if run_path else None,
        "gitopsAdapterDelivery": str(delivery_path) if delivery_path else None,
    },
    "acknowledgement": {
        "ackStatus": ack_status,
        "pickupStatus": pickup_status,
        "branchName": nullable_string(first_not_none(
            pickup_body.get("branchName"),
            run_body.get("branchName"),
            delivery_body.get("branchName"),
        )),
        "requestedOperation": nullable_string(first_not_none(
            pickup_body.get("requestedOperation"),
            run_body.get("requestedOperation"),
            delivery_body.get("requestedOperation"),
        )),
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "assignedActor": assigned_actor,
        "nextCheckpoint": next_checkpoint,
        "summary": f"Pickup acknowledgement is {ack_status}; the next checkpoint is {next_checkpoint} for {assigned_actor}.",
        "ackControl": {
            "path": str(ack_control_path),
            "summaryPath": str(ack_control_summary_path),
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
        "derivedFromGitopsAdapterPickup": as_dict(pickup.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(ack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterPickupAck"] = str(output_json)
evidence["gitopsAdapterPickupAckId"] = ack["gitopsAdapterPickupAckId"]
evidence["gitopsAdapterPickupAckRef"] = {
    "json": str(output_json),
    "ackStatus": ack["acknowledgement"]["ackStatus"],
    "pickupStatus": ack["acknowledgement"]["pickupStatus"],
    "workspaceDir": ack["acknowledgement"]["workspaceDir"],
    "nextCheckpoint": ack["acknowledgement"]["nextCheckpoint"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterPickupAck"] = {
    "gitopsAdapterPickupAckId": ack["gitopsAdapterPickupAckId"],
    "ackStatus": ack["acknowledgement"]["ackStatus"],
    "pickupStatus": ack["acknowledgement"]["pickupStatus"],
    "branchName": ack["acknowledgement"]["branchName"],
    "requestedOperation": ack["acknowledgement"]["requestedOperation"],
    "workspaceDir": ack["acknowledgement"]["workspaceDir"],
    "nextCheckpoint": ack["acknowledgement"]["nextCheckpoint"],
    "assignedActor": ack["acknowledgement"]["assignedActor"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter pickup acknowledgement generated: {output_json}")
print(f"Latest GitOps adapter pickup acknowledgement: {latest_json}")
print(f"GitOps adapter pickup acknowledgement linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterPickupAckId": ack["gitopsAdapterPickupAckId"],
    "releaseId": release_id,
    "ackStatus": ack["acknowledgement"]["ackStatus"],
    "workspaceDir": ack["acknowledgement"]["workspaceDir"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_PICKUP_ACK

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
