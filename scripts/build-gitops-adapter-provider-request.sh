#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-provider-request.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                             Optional report directory.
  GITOPS_ADAPTER_PROVIDER_REQUEST_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_PROVIDER_REQUEST_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, adapter dispatch, adapter payload, and PR bundle.
  - Generates gitops-adapter-provider-request-*.json and gitops-adapter-provider-request-latest.json.
  - Produces a provider-ready PR request contract only.
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

OUTPUT_DIR="${GITOPS_ADAPTER_PROVIDER_REQUEST_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_PROVIDER_REQUEST_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-provider-request-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-provider-request-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_PROVIDER_REQUEST'
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


def request_status_from(dispatch_status: str | None) -> str:
    if dispatch_status == "STUB_DISPATCHED":
        return "PROVIDER_REQUEST_READY"
    if dispatch_status in {"WAITING_APPROVAL", "BLOCKED", "RETURNED_FOR_REWORK", "NO_ACTION_REQUIRED", "NEEDS_MORE_EVIDENCE", "FAILED"}:
        return str(dispatch_status)
    return "NEEDS_MORE_EVIDENCE"


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

dispatch_path = resolve_ref(artifacts.get("gitopsAdapterDispatch"), input_path)
dispatch = load_json(dispatch_path)
dispatch_body = as_dict(dispatch.get("dispatch"))

payload_path = resolve_ref(artifacts.get("gitopsAdapterPayload"), input_path)
payload = load_json(payload_path)
payload_body = as_dict(payload.get("payload"))
payload_manifest = as_dict(payload_body.get("payloadManifest"))

pr_bundle_path = resolve_ref(artifacts.get("gitopsPRBundle"), input_path)
pr_bundle = load_json(pr_bundle_path)
pr_bundle_body = as_dict(pr_bundle.get("bundle"))
pull_request = as_dict(pr_bundle_body.get("pullRequest"))

release = as_dict(dispatch.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

dispatch_status = nullable_string(dispatch_body.get("dispatchStatus"))
request_status = request_status_from(dispatch_status)
branch_name = nullable_string(first_not_none(
    dispatch_body.get("branchName"),
    payload_body.get("branchName"),
))
requested_operation = nullable_string(first_not_none(
    dispatch_body.get("requestedOperation"),
    payload_body.get("requestedOperation"),
))
payload_manifest_path = nullable_string(first_not_none(
    dispatch_body.get("payloadManifestPath"),
    payload_manifest.get("path"),
))
commit_payload_path = nullable_string(first_not_none(
    dispatch_body.get("commitPayloadPath"),
    payload_manifest.get("commitPayloadPath"),
))
provider_request_path = nullable_string(dispatch_body.get("providerRequestPath"))

provider_dir = output_json.parent / f"gitops-provider-request-{release_id}"
provider_dir.mkdir(parents=True, exist_ok=True)
provider_request_doc_path = provider_dir / "provider-request.json"
provider_summary_path = provider_dir / "provider-request-summary.md"
pull_request_body_path = provider_dir / "pull-request-body.md"

commit_payload = load_json(resolve_ref(commit_payload_path, input_path))
pull_request_title = nullable_string(first_not_none(
    pull_request.get("title"),
    commit_payload.get("pullRequestTitle"),
))
commit_message = nullable_string(first_not_none(
    commit_payload.get("commitMessage"),
    dispatch_body.get("requestedOperation"),
))

body_lines = [
    "# S Sentinel Provider-ready PR Request",
    "",
    f"- releaseId: {release_id}",
    f"- branchName: {branch_name or 'none'}",
    f"- requestedOperation: {requested_operation or 'none'}",
    f"- payloadManifestPath: {payload_manifest_path or 'none'}",
    f"- commitPayloadPath: {commit_payload_path or 'none'}",
]
pull_request_body_path.write_text("\n".join(body_lines) + "\n", encoding="utf-8")

provider_request_doc = {
    "schemaVersion": "gitops.adapter.provider.request.document/v1alpha1",
    "gitopsAdapterProviderRequestId": f"gprq-{release_id}",
    "generatedAt": now(),
    "providerType": "github-pr",
    "branchName": branch_name,
    "requestedOperation": requested_operation,
    "commitMessage": commit_message,
    "pullRequestTitle": pull_request_title,
    "pullRequestBodyPath": str(pull_request_body_path),
    "payloadManifestPath": payload_manifest_path,
    "commitPayloadPath": commit_payload_path,
    "dispatchProviderRequestPath": provider_request_path,
    "localOnly": True,
}
provider_request_doc_path.write_text(json.dumps(provider_request_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

provider_summary_path.write_text(
    "# GitOps Provider Request\n\n"
    + f"- requestStatus: {request_status}\n"
    + f"- branchName: {branch_name or 'none'}\n"
    + f"- requestedOperation: {requested_operation or 'none'}\n"
    + f"- pullRequestTitle: {pull_request_title or 'none'}\n",
    encoding="utf-8",
)

labels = [
    "s-sentinel",
    f"env:{release.get('env') or environment.get('env') or 'unknown'}",
    f"action:{release.get('requestedAction') or 'unknown'}",
]

warnings = [str(item) for item in as_list(dispatch_body.get("warnings"))]
if not dispatch_path:
    warnings.append("gitops provider request could not resolve dispatch input")
if not payload_manifest_path:
    warnings.append("gitops provider request could not resolve payload manifest path")
if not commit_payload_path:
    warnings.append("gitops provider request could not resolve commit payload path")

request = {
    "schemaVersion": "gitops.adapter.provider.request/v1alpha1",
    "gitopsAdapterProviderRequestId": f"gprq-{release_id}",
    "generatedBy": "build-gitops-adapter-provider-request.sh",
    "generatedAt": now(),
    "mode": "provider_ready_gitops_pr_request",
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
        "gitopsAdapterDispatch": str(dispatch_path) if dispatch_path else None,
        "gitopsAdapterPayload": str(payload_path) if payload_path else None,
        "gitopsPRBundle": str(pr_bundle_path) if pr_bundle_path else None,
    },
    "providerRequest": {
        "requestStatus": request_status,
        "providerType": "github-pr",
        "branchName": branch_name,
        "requestedOperation": requested_operation,
        "commitMessage": commit_message,
        "pullRequestTitle": pull_request_title,
        "pullRequestBodyPath": str(pull_request_body_path),
        "payloadManifestPath": payload_manifest_path,
        "commitPayloadPath": commit_payload_path,
        "providerRequestPath": str(provider_request_doc_path),
        "patchEntryCount": int(first_not_none(dispatch_body.get("patchEntryCount"), payload_body.get("patchEntryCount")) or 0),
        "workspaceArtifactCount": int(first_not_none(dispatch_body.get("workspaceArtifactCount"), payload_body.get("workspaceArtifactCount")) or 0),
        "labels": labels,
        "summary": f"Provider-ready PR request is {request_status} for branch {branch_name or 'unknown'}.",
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
        "derivedFromGitopsAdapterDispatch": as_dict(dispatch.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterProviderRequest"] = str(output_json)
evidence["gitopsAdapterProviderRequestId"] = request["gitopsAdapterProviderRequestId"]
evidence["gitopsAdapterProviderRequestRef"] = {
    "json": str(output_json),
    "requestStatus": request["providerRequest"]["requestStatus"],
    "branchName": request["providerRequest"]["branchName"],
    "requestedOperation": request["providerRequest"]["requestedOperation"],
    "workspaceArtifactCount": request["providerRequest"]["workspaceArtifactCount"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterProviderRequest"] = {
    "gitopsAdapterProviderRequestId": request["gitopsAdapterProviderRequestId"],
    "requestStatus": request["providerRequest"]["requestStatus"],
    "providerType": request["providerRequest"]["providerType"],
    "branchName": request["providerRequest"]["branchName"],
    "requestedOperation": request["providerRequest"]["requestedOperation"],
    "payloadManifestPath": request["providerRequest"]["payloadManifestPath"],
    "commitPayloadPath": request["providerRequest"]["commitPayloadPath"],
    "providerRequestPath": request["providerRequest"]["providerRequestPath"],
    "patchEntryCount": request["providerRequest"]["patchEntryCount"],
    "workspaceArtifactCount": request["providerRequest"]["workspaceArtifactCount"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter provider request generated: {output_json}")
print(f"Latest GitOps adapter provider request: {latest_json}")
print(f"GitOps adapter provider request linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterProviderRequestId": request["gitopsAdapterProviderRequestId"],
    "releaseId": release_id,
    "requestStatus": request["providerRequest"]["requestStatus"],
    "branchName": request["providerRequest"]["branchName"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_PROVIDER_REQUEST

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
