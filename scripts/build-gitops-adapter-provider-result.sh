#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-provider-result.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                            Optional report directory.
  GITOPS_ADAPTER_PROVIDER_RESULT_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_PROVIDER_RESULT_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, provider request, dispatch, and payload.
  - Generates gitops-adapter-provider-result-*.json and gitops-adapter-provider-result-latest.json.
  - Materializes a local PR-ready package only.
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

OUTPUT_DIR="${GITOPS_ADAPTER_PROVIDER_RESULT_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_PROVIDER_RESULT_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-provider-result-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-provider-result-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_PROVIDER_RESULT'
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


def result_status_from(request_status: str | None) -> str:
    if request_status == "PROVIDER_REQUEST_READY":
        return "PROVIDER_RESULT_READY"
    if request_status in {"WAITING_APPROVAL", "BLOCKED", "RETURNED_FOR_REWORK", "NO_ACTION_REQUIRED", "NEEDS_MORE_EVIDENCE", "FAILED"}:
        return str(request_status)
    return "NEEDS_MORE_EVIDENCE"


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

provider_request_path = resolve_ref(artifacts.get("gitopsAdapterProviderRequest"), input_path)
provider_request = load_json(provider_request_path)
provider_request_body = as_dict(provider_request.get("providerRequest"))

dispatch_path = resolve_ref(artifacts.get("gitopsAdapterDispatch"), input_path)
dispatch = load_json(dispatch_path)
dispatch_body = as_dict(dispatch.get("dispatch"))

payload_path = resolve_ref(artifacts.get("gitopsAdapterPayload"), input_path)
payload = load_json(payload_path)
payload_body = as_dict(payload.get("payload"))
payload_manifest = as_dict(payload_body.get("payloadManifest"))

release = as_dict(provider_request.get("release")) or as_dict(dispatch.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

request_status = nullable_string(provider_request_body.get("requestStatus"))
result_status = result_status_from(request_status)
branch_name = nullable_string(first_not_none(
    provider_request_body.get("branchName"),
    dispatch_body.get("branchName"),
    payload_body.get("branchName"),
))
requested_operation = nullable_string(first_not_none(
    provider_request_body.get("requestedOperation"),
    dispatch_body.get("requestedOperation"),
    payload_body.get("requestedOperation"),
))
provider_type = nullable_string(provider_request_body.get("providerType")) or "github-pr"

package_dir = output_json.parent / f"gitops-provider-ready-{release_id}"
package_dir.mkdir(parents=True, exist_ok=True)

branch_name_path = package_dir / "branch-name.txt"
commit_message_path = package_dir / "commit-message.txt"
pull_request_title_path = package_dir / "pull-request-title.txt"
pull_request_body_path = package_dir / "pull-request-body.md"
package_manifest_path = package_dir / "package-manifest.json"
provider_request_doc_path = package_dir / "provider-request.json"
summary_path = package_dir / "provider-result-summary.md"

commit_message = nullable_string(first_not_none(
    provider_request_body.get("commitMessage"),
    requested_operation,
))
pull_request_title = nullable_string(provider_request_body.get("pullRequestTitle"))
source_pr_body_path = resolve_ref(provider_request_body.get("pullRequestBodyPath"), input_path)
source_provider_request_doc = resolve_ref(provider_request_body.get("providerRequestPath"), input_path)

branch_name_path.write_text((branch_name or "unknown") + "\n", encoding="utf-8")
commit_message_path.write_text((commit_message or "unknown") + "\n", encoding="utf-8")
pull_request_title_path.write_text((pull_request_title or "unknown") + "\n", encoding="utf-8")

if source_pr_body_path and source_pr_body_path.exists():
    shutil.copyfile(source_pr_body_path, pull_request_body_path)
else:
    pull_request_body_path.write_text(
        "# Pull Request Body\n\nNo pull request body was available.\n",
        encoding="utf-8",
    )

if source_provider_request_doc and source_provider_request_doc.exists():
    shutil.copyfile(source_provider_request_doc, provider_request_doc_path)
else:
    provider_request_doc_path.write_text(
        json.dumps(
            {
                "schemaVersion": "gitops.adapter.provider.request.document/v1alpha1",
                "missing": True,
                "source": str(provider_request_path) if provider_request_path else None,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

materialized_files = [
    branch_name_path,
    commit_message_path,
    pull_request_title_path,
    pull_request_body_path,
    provider_request_doc_path,
]

package_manifest = {
    "schemaVersion": "gitops.adapter.provider.package/v1alpha1",
    "generatedAt": now(),
    "releaseId": release_id,
    "providerType": provider_type,
    "branchName": branch_name,
    "requestedOperation": requested_operation,
    "files": [str(path) for path in materialized_files],
    "payloadManifestPath": provider_request_body.get("payloadManifestPath"),
    "commitPayloadPath": provider_request_body.get("commitPayloadPath"),
}
package_manifest_path.write_text(
    json.dumps(package_manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
materialized_files.append(package_manifest_path)

summary_path.write_text(
    "# GitOps Provider Result\n\n"
    + f"- resultStatus: {result_status}\n"
    + f"- providerType: {provider_type}\n"
    + f"- branchName: {branch_name or 'none'}\n"
    + f"- requestedOperation: {requested_operation or 'none'}\n"
    + f"- packageDir: {package_dir}\n",
    encoding="utf-8",
)
materialized_files.append(summary_path)

warnings = [str(item) for item in as_list(provider_request_body.get("warnings"))]
if not provider_request_path:
    warnings.append("gitops provider result could not resolve provider request input")
if not branch_name:
    warnings.append("gitops provider result could not resolve branch name")
if not requested_operation:
    warnings.append("gitops provider result could not resolve requested operation")

result = {
    "schemaVersion": "gitops.adapter.provider.result/v1alpha1",
    "gitopsAdapterProviderResultId": f"gprs-{release_id}",
    "generatedBy": "build-gitops-adapter-provider-result.sh",
    "generatedAt": now(),
    "mode": "provider_ready_gitops_pr_result",
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
        "gitopsAdapterProviderRequest": str(provider_request_path) if provider_request_path else None,
        "gitopsAdapterDispatch": str(dispatch_path) if dispatch_path else None,
        "gitopsAdapterPayload": str(payload_path) if payload_path else None,
    },
    "providerResult": {
        "resultStatus": result_status,
        "providerType": provider_type,
        "branchName": branch_name,
        "requestedOperation": requested_operation,
        "packageDir": str(package_dir),
        "packageManifestPath": str(package_manifest_path),
        "branchNamePath": str(branch_name_path),
        "commitMessagePath": str(commit_message_path),
        "pullRequestTitlePath": str(pull_request_title_path),
        "pullRequestBodyPath": str(pull_request_body_path),
        "providerRequestPath": str(provider_request_doc_path),
        "patchEntryCount": int(first_not_none(provider_request_body.get("patchEntryCount"), payload_body.get("patchEntryCount")) or 0),
        "workspaceArtifactCount": int(first_not_none(provider_request_body.get("workspaceArtifactCount"), payload_body.get("workspaceArtifactCount")) or 0),
        "materializedFileCount": len(materialized_files),
        "materializedFiles": [str(path) for path in materialized_files],
        "warnings": warnings,
        "summary": f"Provider-ready PR package is {result_status} for branch {branch_name or 'unknown'}.",
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
        "derivedFromGitopsAdapterProviderRequest": as_dict(provider_request.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterProviderResult"] = str(output_json)
evidence["gitopsAdapterProviderResultId"] = result["gitopsAdapterProviderResultId"]
evidence["gitopsAdapterProviderResultRef"] = {
    "json": str(output_json),
    "resultStatus": result["providerResult"]["resultStatus"],
    "branchName": result["providerResult"]["branchName"],
    "requestedOperation": result["providerResult"]["requestedOperation"],
    "materializedFileCount": result["providerResult"]["materializedFileCount"],
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterProviderResult"] = {
    "gitopsAdapterProviderResultId": result["gitopsAdapterProviderResultId"],
    "resultStatus": result["providerResult"]["resultStatus"],
    "providerType": result["providerResult"]["providerType"],
    "branchName": result["providerResult"]["branchName"],
    "requestedOperation": result["providerResult"]["requestedOperation"],
    "packageDir": result["providerResult"]["packageDir"],
    "packageManifestPath": result["providerResult"]["packageManifestPath"],
    "providerRequestPath": result["providerResult"]["providerRequestPath"],
    "patchEntryCount": result["providerResult"]["patchEntryCount"],
    "workspaceArtifactCount": result["providerResult"]["workspaceArtifactCount"],
    "materializedFileCount": result["providerResult"]["materializedFileCount"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter provider result generated: {output_json}")
print(f"Latest GitOps adapter provider result: {latest_json}")
print(f"GitOps adapter provider result linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterProviderResultId": result["gitopsAdapterProviderResultId"],
    "releaseId": release_id,
    "resultStatus": result["providerResult"]["resultStatus"],
    "branchName": result["providerResult"]["branchName"],
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_PROVIDER_RESULT

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
