#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-delivery.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                    Optional report directory.
  GITOPS_ADAPTER_DELIVERY_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_DELIVERY_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, adapter result, adapter request, and handoff bundle.
  - Generates gitops-adapter-delivery-*.json and gitops-adapter-delivery-latest.json.
  - Materializes a local pickup workspace with manifest + copied handoff files.
  - Never commits, pushes, creates PRs, mutates GitOps repos, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_DELIVERY_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_DELIVERY_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-delivery-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-delivery-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_DELIVERY'
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


def delivery_status_from(result_status: str | None) -> str:
    if result_status == "RECEIPT_RECORDED":
        return "WORKSPACE_READY"
    if result_status in {"BLOCKED", "WAITING_APPROVAL", "NO_ACTION_REQUIRED", "NEEDS_MORE_EVIDENCE"}:
        return result_status
    return "FAILED"


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

adapter_result_path = resolve_ref(artifacts.get("gitopsAdapterResult"), input_path)
adapter_result = load_json(adapter_result_path)
adapter_meta = as_dict(adapter_result.get("adapter"))
adapter_delivery = as_dict(adapter_result.get("delivery"))
adapter_receipt = as_dict(adapter_delivery.get("receipt"))

adapter_request_path = resolve_ref(artifacts.get("gitopsAdapterRequest"), input_path)
adapter_request = load_json(adapter_request_path)
adapter_request_body = as_dict(adapter_request.get("request"))

handoff_path = resolve_ref(artifacts.get("gitopsHandoffBundle"), input_path)
handoff = load_json(handoff_path)
handoff_body = as_dict(handoff.get("handoff"))

release = as_dict(adapter_result.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

delivery_status = delivery_status_from(nullable_string(adapter_delivery.get("deliveryStatus")))
workspace_dir = output_json.parent / f"gitops-delivery-{release_id}"
workspace_files_dir = workspace_dir / "delivery-files"
workspace_files_dir.mkdir(parents=True, exist_ok=True)

bundle_dir = resolve_ref(adapter_receipt.get("bundleDir"), input_path)
copied_files: list[dict[str, Any]] = []
warnings: list[str] = []

for item in as_list(adapter_delivery.get("outputFiles")):
    if not isinstance(item, dict):
        continue
    relative_path = Path(str(item.get("path") or item.get("fileId") or "artifact"))
    source_path = None
    if bundle_dir:
        candidate = bundle_dir / relative_path
        if candidate.exists() and candidate.is_file():
            source_path = candidate
    if source_path is None:
        fallback = resolve_ref(item.get("path"), input_path)
        if fallback and fallback.is_file():
            source_path = fallback

    workspace_path = workspace_files_dir / relative_path.name
    if source_path and source_path.exists():
        shutil.copyfile(source_path, workspace_path)
    else:
        warnings.append(f"missing handoff source file for {item.get('fileId') or relative_path.name}")
        workspace_path.write_text(
            f"# Missing source\n\nExpected handoff file for {item.get('fileId') or relative_path.name} was not found.\n",
            encoding="utf-8",
        )

    copied_files.append({
        "fileId": item.get("fileId"),
        "sourcePath": str(source_path) if source_path else None,
        "workspacePath": str(workspace_path),
        "contentType": item.get("contentType"),
        "description": item.get("description"),
    })

pickup_instructions = [
    "Review delivery-manifest.json for release metadata and guardrails.",
    "Inspect files under delivery-files/ before any manual GitOps handoff.",
    "If human approval is still pending, do not submit these files to any external Git provider.",
    "Use pickup-instructions.md as the operator handoff note.",
]

manifest_path = workspace_dir / "delivery-manifest.json"
instructions_path = workspace_dir / "pickup-instructions.md"

manifest_doc = {
    "schemaVersion": "gitops.adapter.delivery.manifest/v1alpha1",
    "gitopsAdapterDeliveryId": f"gad-{release_id}",
    "generatedAt": now(),
    "releaseId": release_id,
    "deliveryStatus": delivery_status,
    "branchName": adapter_receipt.get("branchName"),
    "requestedOperation": first_not_none(
        adapter_delivery.get("requestedOperation"),
        adapter_request_body.get("requestedOperation"),
    ),
    "workspaceDir": str(workspace_dir),
    "copiedFiles": copied_files,
    "warnings": warnings,
}
manifest_path.write_text(json.dumps(manifest_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
instructions_path.write_text(
    "# GitOps Delivery Pickup\n\n" + "\n".join(f"- {item}" for item in pickup_instructions) + "\n",
    encoding="utf-8",
)

result = {
    "schemaVersion": "gitops.adapter.delivery/v1alpha1",
    "gitopsAdapterDeliveryId": f"gad-{release_id}",
    "generatedBy": "build-gitops-adapter-delivery.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_delivery_workspace",
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
        "gitopsAdapterResult": str(adapter_result_path) if adapter_result_path else None,
        "gitopsAdapterRequest": str(adapter_request_path) if adapter_request_path else None,
        "gitopsHandoffBundle": str(handoff_path) if handoff_path else None,
    },
    "adapter": {
        "adapter": "gitops-handoff-local",
        "adapterType": nullable_string(adapter_meta.get("adapterType")) or "gitops-handoff-local",
        "deliveryMode": "local_workspace_materialization",
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotCallExternalGitProvider": True,
        "emitsWorkspace": True,
    },
    "delivery": {
        "deliveryStatus": delivery_status,
        "workspaceDir": str(workspace_dir),
        "manifestFile": str(manifest_path),
        "pickupInstructionsFile": str(instructions_path),
        "branchName": nullable_string(first_not_none(
            adapter_receipt.get("branchName"),
            handoff_body.get("branchName"),
        )),
        "requestedOperation": nullable_string(first_not_none(
            adapter_delivery.get("requestedOperation"),
            adapter_request_body.get("requestedOperation"),
        )),
        "copiedFiles": copied_files,
        "pickupInstructions": pickup_instructions,
        "summary": f"Local delivery workspace prepared for release {release_id} with {len(copied_files)} copied handoff files.",
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
        "derivedFromGitopsAdapterResult": as_dict(adapter_result.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterDelivery"] = str(output_json)
evidence["gitopsAdapterDeliveryId"] = result["gitopsAdapterDeliveryId"]
evidence["gitopsAdapterDeliveryRef"] = {
    "json": str(output_json),
    "deliveryStatus": result["delivery"]["deliveryStatus"],
    "workspaceDir": result["delivery"]["workspaceDir"],
    "copiedFileCount": len(copied_files),
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterDelivery"] = {
    "gitopsAdapterDeliveryId": result["gitopsAdapterDeliveryId"],
    "deliveryStatus": result["delivery"]["deliveryStatus"],
    "branchName": result["delivery"]["branchName"],
    "requestedOperation": result["delivery"]["requestedOperation"],
    "copiedFileCount": len(copied_files),
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter delivery generated: {output_json}")
print(f"Latest GitOps adapter delivery: {latest_json}")
print(f"GitOps adapter delivery linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterDeliveryId": result["gitopsAdapterDeliveryId"],
    "releaseId": release_id,
    "deliveryStatus": result["delivery"]["deliveryStatus"],
    "workspaceDir": result["delivery"]["workspaceDir"],
    "copiedFileCount": len(copied_files),
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_DELIVERY

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
