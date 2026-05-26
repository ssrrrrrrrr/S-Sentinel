#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-dispatch.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                    Optional report directory.
  GITOPS_ADAPTER_DISPATCH_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_DISPATCH_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, adapter payload, delivery workspace, and PR bundle.
  - Generates gitops-adapter-dispatch-*.json and gitops-adapter-dispatch-latest.json.
  - Produces an external-adapter-style stub dispatch receipt only.
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

OUTPUT_DIR="${GITOPS_ADAPTER_DISPATCH_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_DISPATCH_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-dispatch-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-dispatch-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_DISPATCH'
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


def dispatch_status_from(payload_status: str | None) -> str:
    if payload_status == "PAYLOAD_READY":
        return "STUB_DISPATCHED"
    if payload_status in {"WAITING_APPROVAL", "BLOCKED", "RETURNED_FOR_REWORK", "NO_ACTION_REQUIRED", "NEEDS_MORE_EVIDENCE", "FAILED"}:
        return str(payload_status)
    return "NEEDS_MORE_EVIDENCE"


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

payload_path = resolve_ref(artifacts.get("gitopsAdapterPayload"), input_path)
payload = load_json(payload_path)
payload_body = as_dict(payload.get("payload"))

delivery_path = resolve_ref(artifacts.get("gitopsAdapterDelivery"), input_path)
delivery = load_json(delivery_path)
delivery_body = as_dict(delivery.get("delivery"))

pr_bundle_path = resolve_ref(artifacts.get("gitopsPRBundle"), input_path)
pr_bundle = load_json(pr_bundle_path)
pr_bundle_body = as_dict(pr_bundle.get("bundle"))
pull_request = as_dict(pr_bundle_body.get("pullRequest"))

release = as_dict(payload.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

payload_dir = resolve_ref(payload_body.get("workspaceDir"), input_path)
payload_manifest = resolve_ref(as_dict(payload_body.get("payloadManifest")).get("path"), input_path)
commit_payload = resolve_ref(as_dict(payload_body.get("payloadManifest")).get("commitPayloadPath"), input_path)

dispatch_dir = (payload_dir / "external-adapter-stub") if payload_dir else (output_json.parent / f"gitops-dispatch-{release_id}")
dispatch_dir.mkdir(parents=True, exist_ok=True)
dispatch_manifest_path = dispatch_dir / "dispatch-manifest.json"
dispatch_summary_path = dispatch_dir / "dispatch-summary.md"
provider_request_path = dispatch_dir / "provider-request.json"

payload_status = nullable_string(payload_body.get("payloadStatus"))
dispatch_status = dispatch_status_from(payload_status)
branch_name = nullable_string(first_not_none(
    payload_body.get("branchName"),
    delivery_body.get("branchName"),
))
requested_operation = nullable_string(first_not_none(
    payload_body.get("requestedOperation"),
    delivery_body.get("requestedOperation"),
))

dispatch_checklist = [
    "verify payload manifest",
    "verify commit payload",
    "verify branch naming",
    "handoff to real git provider adapter",
]
warnings = [str(item) for item in as_list(payload_body.get("warnings"))]
if not payload_path:
    warnings.append("gitops adapter dispatch could not resolve adapter payload input")
if not commit_payload:
    warnings.append("gitops adapter dispatch could not resolve commit payload file")

provider_request = {
    "schemaVersion": "gitops.adapter.provider.request.stub/v1alpha1",
    "gitopsAdapterDispatchId": f"gdisp-{release_id}",
    "generatedAt": now(),
    "adapterType": "external-gitops-pr-stub",
    "branchName": branch_name,
    "requestedOperation": requested_operation,
    "pullRequestTitle": nullable_string(first_not_none(
        pull_request.get("title"),
        as_dict(load_json(commit_payload)).get("pullRequestTitle") if commit_payload else None,
    )),
    "payloadManifestPath": str(payload_manifest) if payload_manifest else None,
    "commitPayloadPath": str(commit_payload) if commit_payload else None,
    "localOnly": True,
}
provider_request_path.write_text(json.dumps(provider_request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

dispatch_manifest = {
    "schemaVersion": "gitops.adapter.dispatch.manifest/v1alpha1",
    "gitopsAdapterDispatchId": f"gdisp-{release_id}",
    "generatedAt": now(),
    "dispatchStatus": dispatch_status,
    "payloadStatus": payload_status,
    "branchName": branch_name,
    "requestedOperation": requested_operation,
    "providerRequestPath": str(provider_request_path),
    "localOnly": True,
}
dispatch_manifest_path.write_text(json.dumps(dispatch_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

dispatch_summary_path.write_text(
    "# External GitOps Adapter Stub Dispatch\n\n"
    + f"- dispatchStatus: {dispatch_status}\n"
    + f"- payloadStatus: {payload_status or 'unknown'}\n"
    + f"- branchName: {branch_name or 'none'}\n"
    + f"- requestedOperation: {requested_operation or 'none'}\n"
    + f"- providerRequestPath: {provider_request_path}\n",
    encoding="utf-8",
)

dispatch = {
    "schemaVersion": "gitops.adapter.dispatch/v1alpha1",
    "gitopsAdapterDispatchId": f"gdisp-{release_id}",
    "generatedBy": "build-gitops-adapter-dispatch.sh",
    "generatedAt": now(),
    "mode": "external_gitops_adapter_stub_dispatch",
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
        "gitopsAdapterPayload": str(payload_path) if payload_path else None,
        "gitopsAdapterDelivery": str(delivery_path) if delivery_path else None,
        "gitopsPRBundle": str(pr_bundle_path) if pr_bundle_path else None,
    },
    "dispatch": {
        "dispatchStatus": dispatch_status,
        "adapterType": "external-gitops-pr-stub",
        "dispatchMode": "local_only_stub_dispatch",
        "payloadStatus": payload_status,
        "branchName": branch_name,
        "requestedOperation": requested_operation,
        "payloadDir": str(payload_dir) if payload_dir else None,
        "payloadManifestPath": str(payload_manifest) if payload_manifest else None,
        "commitPayloadPath": str(commit_payload) if commit_payload else None,
        "providerRequestPath": str(provider_request_path),
        "patchEntryCount": int(payload_body.get("patchEntryCount") or 0),
        "workspaceArtifactCount": int(payload_body.get("workspaceArtifactCount") or 0),
        "dispatchReceipt": {
            "path": str(dispatch_manifest_path),
            "summaryPath": str(dispatch_summary_path),
            "generatedAt": now(),
            "localOnly": True,
        },
        "dispatchChecklist": dispatch_checklist,
        "summary": f"External GitOps adapter stub recorded dispatch status {dispatch_status} for branch {branch_name or 'unknown'}.",
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
        "derivedFromGitopsAdapterPayload": as_dict(payload.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(dispatch, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterDispatch"] = str(output_json)
evidence["gitopsAdapterDispatchId"] = dispatch["gitopsAdapterDispatchId"]
evidence["gitopsAdapterDispatchRef"] = {
    "json": str(output_json),
    "dispatchStatus": dispatch["dispatch"]["dispatchStatus"],
    "branchName": dispatch["dispatch"]["branchName"],
    "requestedOperation": dispatch["dispatch"]["requestedOperation"],
    "workspaceArtifactCount": dispatch["dispatch"]["workspaceArtifactCount"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterDispatch"] = {
    "gitopsAdapterDispatchId": dispatch["gitopsAdapterDispatchId"],
    "dispatchStatus": dispatch["dispatch"]["dispatchStatus"],
    "payloadStatus": dispatch["dispatch"]["payloadStatus"],
    "branchName": dispatch["dispatch"]["branchName"],
    "requestedOperation": dispatch["dispatch"]["requestedOperation"],
    "payloadDir": dispatch["dispatch"]["payloadDir"],
    "payloadManifestPath": dispatch["dispatch"]["payloadManifestPath"],
    "commitPayloadPath": dispatch["dispatch"]["commitPayloadPath"],
    "providerRequestPath": dispatch["dispatch"]["providerRequestPath"],
    "patchEntryCount": dispatch["dispatch"]["patchEntryCount"],
    "workspaceArtifactCount": dispatch["dispatch"]["workspaceArtifactCount"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter dispatch generated: {output_json}")
print(f"Latest GitOps adapter dispatch: {latest_json}")
print(f"GitOps adapter dispatch linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterDispatchId": dispatch["gitopsAdapterDispatchId"],
    "releaseId": release_id,
    "dispatchStatus": dispatch["dispatch"]["dispatchStatus"],
    "branchName": dispatch["dispatch"]["branchName"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_DISPATCH

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
