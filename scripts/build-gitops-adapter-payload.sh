#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-payload.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                   Optional report directory.
  GITOPS_ADAPTER_PAYLOAD_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_PAYLOAD_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, handoff progress, delivery workspace, PR bundle, and handoff bundle.
  - Generates gitops-adapter-payload-*.json and gitops-adapter-payload-latest.json.
  - Materializes a local-only commit-ready payload manifest for future external adapters.
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

OUTPUT_DIR="${GITOPS_ADAPTER_PAYLOAD_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_PAYLOAD_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-payload-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-payload-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_PAYLOAD'
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


def payload_status_from(progress_status: str | None, workspace_file_count: int) -> str:
    if progress_status in {"BLOCKED", "WAITING_APPROVAL", "NO_ACTION_REQUIRED"}:
        return str(progress_status)
    if progress_status in {"INVALID_ACTION", "FAILED"}:
        return "FAILED"
    if progress_status == "RETURNED_FOR_REWORK":
        return "RETURNED_FOR_REWORK"
    if workspace_file_count <= 0:
        return "NEEDS_MORE_EVIDENCE"
    if progress_status in {"WAITING_TO_START", "HANDOFF_IN_PROGRESS", "HANDOFF_COMPLETED"}:
        return "PAYLOAD_READY"
    return "NEEDS_MORE_EVIDENCE"


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

handoff_progress_path = resolve_ref(artifacts.get("gitopsAdapterHandoffProgress"), input_path)
handoff_progress = load_json(handoff_progress_path)
handoff_progress_body = as_dict(handoff_progress.get("handoffProgress"))

adapter_delivery_path = resolve_ref(artifacts.get("gitopsAdapterDelivery"), input_path)
adapter_delivery = load_json(adapter_delivery_path)
adapter_delivery_body = as_dict(adapter_delivery.get("delivery"))

pr_bundle_path = resolve_ref(artifacts.get("gitopsPRBundle"), input_path)
pr_bundle = load_json(pr_bundle_path)
pr_bundle_body = as_dict(pr_bundle.get("bundle"))
pr_bundle_pull_request = as_dict(pr_bundle_body.get("pullRequest"))

handoff_bundle_path = resolve_ref(artifacts.get("gitopsHandoffBundle"), input_path)
handoff_bundle = load_json(handoff_bundle_path)
handoff_bundle_body = as_dict(handoff_bundle.get("handoff"))

release = as_dict(handoff_progress.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

workspace_dir = resolve_ref(
    first_not_none(
        adapter_delivery_body.get("workspaceDir"),
        handoff_progress_body.get("workspaceDir"),
    ),
    input_path,
)
bundle_dir = resolve_ref(handoff_bundle_body.get("bundleDir"), input_path)

copied_files = [
    item for item in as_list(adapter_delivery_body.get("copiedFiles"))
    if isinstance(item, dict)
]
materialized_files = [
    item for item in as_list(handoff_bundle_body.get("materializedFiles"))
    if isinstance(item, dict)
]
patch_entries = [
    item for item in as_list(pr_bundle_body.get("patchEntries"))
    if isinstance(item, dict)
]
handoff_checklist = [
    item for item in as_list(handoff_bundle_body.get("handoffChecklist"))
    if isinstance(item, str)
]

payload_files: list[dict[str, Any]] = []
for item in copied_files:
    payload_files.append({
        "fileId": item.get("fileId"),
        "path": item.get("workspacePath") or item.get("sourcePath"),
        "contentType": item.get("contentType"),
        "description": item.get("description"),
    })

if not payload_files:
    for item in materialized_files:
        payload_files.append({
            "fileId": item.get("fileId"),
            "path": item.get("path"),
            "contentType": item.get("contentType"),
            "description": item.get("description"),
        })

workspace_artifact_count = len(payload_files)
progress_status = nullable_string(handoff_progress_body.get("progressStatus"))
payload_status = payload_status_from(progress_status, workspace_artifact_count)

payload_dir = (workspace_dir / "adapter-payload") if workspace_dir else (output_json.parent / f"gitops-payload-{release_id}")
payload_dir.mkdir(parents=True, exist_ok=True)
manifest_path = payload_dir / "payload-manifest.json"
summary_path = payload_dir / "payload-summary.md"
commit_payload_path = payload_dir / "commit-payload.json"

warnings = [str(item) for item in as_list(handoff_progress_body.get("warnings"))]
if not handoff_progress_path:
    warnings.append("gitops adapter payload could not resolve handoff progress input")
if not adapter_delivery_path:
    warnings.append("gitops adapter payload could not resolve adapter delivery input")
if workspace_artifact_count == 0:
    warnings.append("gitops adapter payload did not find any workspace payload files")

branch_name = nullable_string(first_not_none(
    handoff_progress_body.get("branchName"),
    adapter_delivery_body.get("branchName"),
    handoff_bundle_body.get("branchName"),
))
requested_operation = nullable_string(first_not_none(
    handoff_progress_body.get("requestedOperation"),
    adapter_delivery_body.get("requestedOperation"),
))

manifest = {
    "schemaVersion": "gitops.adapter.payload.manifest/v1alpha1",
    "gitopsAdapterPayloadId": f"gpay-{release_id}",
    "generatedAt": now(),
    "payloadStatus": payload_status,
    "branchName": branch_name,
    "requestedOperation": requested_operation,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "bundleDir": str(bundle_dir) if bundle_dir else None,
    "patchEntryCount": len(patch_entries),
    "handoffFileCount": len(materialized_files),
    "workspaceArtifactCount": workspace_artifact_count,
    "localOnly": True,
}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

summary_path.write_text(
    "# GitOps Adapter Payload\n\n"
    + f"- payloadStatus: {payload_status}\n"
    + f"- progressStatus: {progress_status or 'unknown'}\n"
    + f"- branchName: {branch_name or 'none'}\n"
    + f"- requestedOperation: {requested_operation or 'none'}\n"
    + f"- patchEntryCount: {len(patch_entries)}\n"
    + f"- handoffFileCount: {len(materialized_files)}\n"
    + f"- workspaceArtifactCount: {workspace_artifact_count}\n",
    encoding="utf-8",
)

commit_payload = {
    "schemaVersion": "gitops.adapter.commit.payload/v1alpha1",
    "gitopsAdapterPayloadId": f"gpay-{release_id}",
    "generatedAt": now(),
    "branchName": branch_name,
    "commitMessage": nullable_string(first_not_none(
        handoff_bundle_body.get("commitMessage"),
        pr_bundle_pull_request.get("commitMessage"),
    )),
    "pullRequestTitle": nullable_string(first_not_none(
        handoff_bundle_body.get("pullRequestTitle"),
        pr_bundle_pull_request.get("title"),
    )),
    "requestedOperation": requested_operation,
    "patchEntries": patch_entries,
    "payloadFiles": payload_files,
    "handoffChecklist": handoff_checklist,
    "localOnly": True,
}
commit_payload_path.write_text(json.dumps(commit_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

payload = {
    "schemaVersion": "gitops.adapter.payload/v1alpha1",
    "gitopsAdapterPayloadId": f"gpay-{release_id}",
    "generatedBy": "build-gitops-adapter-payload.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_payload",
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
        "gitopsAdapterHandoffProgress": str(handoff_progress_path) if handoff_progress_path else None,
        "gitopsAdapterDelivery": str(adapter_delivery_path) if adapter_delivery_path else None,
        "gitopsPRBundle": str(pr_bundle_path) if pr_bundle_path else None,
        "gitopsHandoffBundle": str(handoff_bundle_path) if handoff_bundle_path else None,
    },
    "payload": {
        "payloadStatus": payload_status,
        "progressStatus": progress_status,
        "prepStatus": nullable_string(handoff_progress_body.get("prepStatus")),
        "transitionStatus": nullable_string(handoff_progress_body.get("transitionStatus")),
        "eventStatus": nullable_string(handoff_progress_body.get("eventStatus")),
        "handoffStateStatus": nullable_string(handoff_progress_body.get("handoffStateStatus")),
        "pickupStatus": nullable_string(handoff_progress_body.get("pickupStatus")),
        "ackStatus": nullable_string(handoff_progress_body.get("ackStatus")),
        "branchName": branch_name,
        "requestedOperation": requested_operation,
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "bundleDir": str(bundle_dir) if bundle_dir else None,
        "payloadFiles": payload_files,
        "patchEntryCount": len(patch_entries),
        "handoffFileCount": len(materialized_files),
        "workspaceArtifactCount": workspace_artifact_count,
        "summary": f"GitOps adapter payload is {payload_status}; branch={branch_name or 'none'}, operation={requested_operation or 'none'}, files={workspace_artifact_count}.",
        "payloadManifest": {
            "path": str(manifest_path),
            "summaryPath": str(summary_path),
            "commitPayloadPath": str(commit_payload_path),
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
        "derivedFromGitopsAdapterHandoffProgress": as_dict(handoff_progress.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterPayload"] = str(output_json)
evidence["gitopsAdapterPayloadId"] = payload["gitopsAdapterPayloadId"]
evidence["gitopsAdapterPayloadRef"] = {
    "json": str(output_json),
    "payloadStatus": payload["payload"]["payloadStatus"],
    "branchName": payload["payload"]["branchName"],
    "requestedOperation": payload["payload"]["requestedOperation"],
    "workspaceArtifactCount": payload["payload"]["workspaceArtifactCount"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterPayload"] = {
    "gitopsAdapterPayloadId": payload["gitopsAdapterPayloadId"],
    "payloadStatus": payload["payload"]["payloadStatus"],
    "progressStatus": payload["payload"]["progressStatus"],
    "prepStatus": payload["payload"]["prepStatus"],
    "transitionStatus": payload["payload"]["transitionStatus"],
    "eventStatus": payload["payload"]["eventStatus"],
    "handoffStateStatus": payload["payload"]["handoffStateStatus"],
    "pickupStatus": payload["payload"]["pickupStatus"],
    "ackStatus": payload["payload"]["ackStatus"],
    "branchName": payload["payload"]["branchName"],
    "requestedOperation": payload["payload"]["requestedOperation"],
    "workspaceDir": payload["payload"]["workspaceDir"],
    "bundleDir": payload["payload"]["bundleDir"],
    "patchEntryCount": payload["payload"]["patchEntryCount"],
    "handoffFileCount": payload["payload"]["handoffFileCount"],
    "workspaceArtifactCount": payload["payload"]["workspaceArtifactCount"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter payload generated: {output_json}")
print(f"Latest GitOps adapter payload: {latest_json}")
print(f"GitOps adapter payload linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterPayloadId": payload["gitopsAdapterPayloadId"],
    "releaseId": release_id,
    "payloadStatus": payload["payload"]["payloadStatus"],
    "workspaceArtifactCount": payload["payload"]["workspaceArtifactCount"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_PAYLOAD

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
