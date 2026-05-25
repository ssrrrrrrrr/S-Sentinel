#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-pickup.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                  Optional report directory.
  GITOPS_ADAPTER_PICKUP_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_PICKUP_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, adapter run, delivery, and request artifacts.
  - Generates gitops-adapter-pickup-*.json and gitops-adapter-pickup-latest.json.
  - Emits a local-only pickup control receipt; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_PICKUP_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_PICKUP_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-pickup-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-pickup-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_PICKUP'
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


def pickup_status_from(run_status: str | None) -> str:
    if run_status == "HANDOFF_READY":
        return "READY_FOR_PICKUP"
    if run_status in {"BLOCKED", "WAITING_APPROVAL", "NO_ACTION_REQUIRED", "NEEDS_MORE_EVIDENCE", "FAILED"}:
        return str(run_status)
    return "FAILED"


def next_checkpoint_from(pickup_status: str) -> tuple[str, str]:
    mapping = {
        "READY_FOR_PICKUP": ("human_pickup_workspace_review", "service_owner_or_release_operator"),
        "WAITING_APPROVAL": ("await_manual_approval", "approver"),
        "BLOCKED": ("resolve_blockers", "platform_owner"),
        "NEEDS_MORE_EVIDENCE": ("refresh_release_evidence", "release_operator"),
        "NO_ACTION_REQUIRED": ("archive_handoff_state", "platform_owner"),
        "FAILED": ("repair_workspace_materialization", "platform_owner"),
    }
    return mapping.get(pickup_status, ("investigate_pickup_state", "platform_owner"))


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

run_path = resolve_ref(artifacts.get("gitopsAdapterRun"), input_path)
run = load_json(run_path)
run_body = as_dict(run.get("run"))

delivery_path = resolve_ref(artifacts.get("gitopsAdapterDelivery"), input_path)
delivery = load_json(delivery_path)
delivery_body = as_dict(delivery.get("delivery"))

request_path = resolve_ref(artifacts.get("gitopsAdapterRequest"), input_path)
request = load_json(request_path)
request_body = as_dict(request.get("request"))
request_delivery = as_dict(request_body.get("delivery"))

release = as_dict(run.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

workspace_dir = resolve_ref(run_body.get("workspaceDir"), input_path)
pickup_receipt = as_dict(run_body.get("pickupReceipt"))
pickup_receipt_path = resolve_ref(pickup_receipt.get("path"), input_path)
pickup_summary_path = resolve_ref(pickup_receipt.get("summaryPath"), input_path)
pickup_status = pickup_status_from(nullable_string(run_body.get("runStatus")))
next_checkpoint, next_actor = next_checkpoint_from(pickup_status)

pickup_control_path = workspace_dir / "pickup-control.json" if workspace_dir else output_json.parent / f"pickup-control-{release_id}.json"
pickup_control_summary_path = workspace_dir / "pickup-control-summary.md" if workspace_dir else output_json.parent / f"pickup-control-summary-{release_id}.md"
pickup_control_path.parent.mkdir(parents=True, exist_ok=True)

files = []
for item in as_list(run_body.get("workspaceFiles")):
    if not isinstance(item, dict):
        continue
    path = resolve_ref(item.get("workspacePath"), input_path)
    files.append({
        "fileId": item.get("fileId"),
        "path": str(path) if path else item.get("workspacePath"),
        "exists": bool(path and path.exists()),
        "description": item.get("description"),
        "contentType": item.get("contentType"),
    })

control = {
    "schemaVersion": "gitops.adapter.pickup.control/v1alpha1",
    "gitopsAdapterPickupId": f"gpick-{release_id}",
    "generatedAt": now(),
    "pickupStatus": pickup_status,
    "nextCheckpoint": next_checkpoint,
    "nextActor": next_actor,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "localOnly": True,
}
pickup_control_path.write_text(json.dumps(control, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
pickup_control_summary_path.write_text(
    "# GitOps Pickup Control\n\n"
    + f"- pickupStatus: {pickup_status}\n"
    + f"- nextCheckpoint: {next_checkpoint}\n"
    + f"- nextActor: {next_actor}\n"
    + f"- workspaceDir: {str(workspace_dir) if workspace_dir else 'none'}\n",
    encoding="utf-8",
)

warnings = [str(item) for item in as_list(run_body.get("warnings"))]
if pickup_status == "FAILED":
    warnings.append("pickup control failed because the upstream run was not handoff-ready")

pickup = {
    "schemaVersion": "gitops.adapter.pickup/v1alpha1",
    "gitopsAdapterPickupId": f"gpick-{release_id}",
    "generatedBy": "build-gitops-adapter-pickup.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_pickup",
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
        "gitopsAdapterRun": str(run_path) if run_path else None,
        "gitopsAdapterDelivery": str(delivery_path) if delivery_path else None,
        "gitopsAdapterRequest": str(request_path) if request_path else None,
    },
    "pickup": {
        "pickupStatus": pickup_status,
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "branchName": nullable_string(first_not_none(
            run_body.get("branchName"),
            delivery_body.get("branchName"),
            request_delivery.get("branchName"),
        )),
        "requestedOperation": nullable_string(first_not_none(
            run_body.get("requestedOperation"),
            delivery_body.get("requestedOperation"),
            request_body.get("requestedOperation"),
        )),
        "nextCheckpoint": next_checkpoint,
        "nextActor": next_actor,
        "summary": f"Local pickup state is {pickup_status}; the next checkpoint is {next_checkpoint} for {next_actor}.",
        "files": files,
        "pickupControl": {
            "path": str(pickup_control_path),
            "summaryPath": str(pickup_control_summary_path),
            "generatedAt": now(),
            "localOnly": True,
        },
        "pickupReceipt": {
            "path": str(pickup_receipt_path) if pickup_receipt_path else pickup_receipt.get("path"),
            "summaryPath": str(pickup_summary_path) if pickup_summary_path else pickup_receipt.get("summaryPath"),
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
        "derivedFromGitopsAdapterRun": as_dict(run.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(pickup, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterPickup"] = str(output_json)
evidence["gitopsAdapterPickupId"] = pickup["gitopsAdapterPickupId"]
evidence["gitopsAdapterPickupRef"] = {
    "json": str(output_json),
    "pickupStatus": pickup["pickup"]["pickupStatus"],
    "workspaceDir": pickup["pickup"]["workspaceDir"],
    "nextCheckpoint": pickup["pickup"]["nextCheckpoint"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterPickup"] = {
    "gitopsAdapterPickupId": pickup["gitopsAdapterPickupId"],
    "pickupStatus": pickup["pickup"]["pickupStatus"],
    "branchName": pickup["pickup"]["branchName"],
    "requestedOperation": pickup["pickup"]["requestedOperation"],
    "workspaceFileCount": len(files),
    "nextCheckpoint": pickup["pickup"]["nextCheckpoint"],
    "nextActor": pickup["pickup"]["nextActor"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter pickup generated: {output_json}")
print(f"Latest GitOps adapter pickup: {latest_json}")
print(f"GitOps adapter pickup linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterPickupId": pickup["gitopsAdapterPickupId"],
    "releaseId": release_id,
    "pickupStatus": pickup["pickup"]["pickupStatus"],
    "workspaceDir": pickup["pickup"]["workspaceDir"],
    "workspaceFileCount": len(files),
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_PICKUP

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
