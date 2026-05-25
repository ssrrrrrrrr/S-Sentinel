#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-result.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                  Optional report directory.
  GITOPS_ADAPTER_RESULT_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_RESULT_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, adapter request, handoff bundle, and PR bundle.
  - Generates gitops-adapter-result-*.json and gitops-adapter-result-latest.json.
  - Emits a local-only delivery receipt; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_RESULT_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_RESULT_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-result-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-result-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_RESULT'
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
            if candidate.exists() and candidate.is_file():
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


def delivery_status_from(request_status: str | None) -> str:
    if request_status == "READY_FOR_ADAPTER":
        return "RECEIPT_RECORDED"
    if request_status in {"BLOCKED", "WAITING_APPROVAL", "NO_ACTION_REQUIRED", "NEEDS_MORE_EVIDENCE"}:
        return request_status
    return "FAILED"


def delivery_summary(status: str, action: str | None, file_count: int, branch_name: str | None) -> str:
    target = action or "UNKNOWN"
    if status == "RECEIPT_RECORDED":
        branch_hint = f" on branch {branch_name}" if branch_name else ""
        return f"Local GitOps adapter recorded a delivery receipt for {target}{branch_hint} with {file_count} materialized handoff files."
    if status == "WAITING_APPROVAL":
        return f"GitOps adapter received the handoff for {target}, but delivery remains paused until human approval is complete."
    if status == "BLOCKED":
        return f"GitOps adapter declined delivery for {target} because upstream eligibility or policy still blocks the request."
    if status == "NO_ACTION_REQUIRED":
        return f"GitOps adapter recorded that no GitOps delivery is required for {target}."
    if status == "NEEDS_MORE_EVIDENCE":
        return f"GitOps adapter cannot deliver {target} yet because required evidence inputs are still incomplete."
    return f"GitOps adapter could not produce a stable delivery receipt for {target}."


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
decision_refs = as_dict(evidence.get("decisionRefs"))
environment = as_dict(evidence.get("environment"))

adapter_request_path = resolve_ref(artifacts.get("gitopsAdapterRequest"), input_path)
adapter_request = load_json(adapter_request_path)
adapter_request_body = as_dict(adapter_request.get("request"))
adapter_request_delivery = as_dict(adapter_request_body.get("delivery"))

handoff_path = resolve_ref(artifacts.get("gitopsHandoffBundle"), input_path)
handoff = load_json(handoff_path)
handoff_body = as_dict(handoff.get("handoff"))

bundle_path = resolve_ref(artifacts.get("gitopsPRBundle"), input_path)
bundle = load_json(bundle_path)
bundle_body = as_dict(bundle.get("bundle"))
bundle_pr = as_dict(bundle_body.get("pullRequest"))

release = as_dict(adapter_request.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)
requested_action = nullable_string(first_not_none(
    release.get("requestedAction"),
    evidence.get("requestedAction"),
    evidence.get("finalAction"),
))
request_status = nullable_string(adapter_request_body.get("requestStatus"))
delivery_status = delivery_status_from(request_status)
branch_name = nullable_string(first_not_none(
    adapter_request_delivery.get("branchName"),
    handoff_body.get("branchName"),
    bundle_body.get("branchName"),
))
commit_message = nullable_string(first_not_none(
    adapter_request_delivery.get("commitMessage"),
    handoff_body.get("commitMessage"),
    bundle_body.get("commitMessage"),
))
pull_request_title = nullable_string(first_not_none(
    adapter_request_delivery.get("pullRequestTitle"),
    handoff_body.get("pullRequestTitle"),
    bundle_pr.get("title"),
))
output_files = [item for item in as_list(adapter_request_body.get("handoffFiles")) if isinstance(item, dict)]
warnings = []
if delivery_status == "WAITING_APPROVAL":
    warnings.append("human approval required before external delivery")
if delivery_status == "BLOCKED":
    warnings.append("upstream policy or eligibility blocked adapter delivery")
if not output_files:
    warnings.append("no materialized handoff files were found")

result = {
    "schemaVersion": "gitops.adapter.result/v1alpha1",
    "gitopsAdapterResultId": f"gar-{release_id}",
    "generatedBy": "build-gitops-adapter-result.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_result",
    "release": {
        "releaseId": release_id,
        "service": first_not_none(evidence.get("service"), release.get("service")),
        "env": first_not_none(evidence.get("env"), release.get("env"), environment.get("env")),
        "namespace": first_not_none(evidence.get("namespace"), release.get("namespace"), environment.get("namespace")),
        "policyDecision": first_not_none(evidence.get("policyDecision"), release.get("policyDecision")),
        "finalAction": first_not_none(evidence.get("finalAction"), release.get("finalAction")),
        "requestedAction": requested_action,
    },
    "inputs": {
        "releaseEvidence": str(input_path),
        "gitopsAdapterRequest": str(adapter_request_path) if adapter_request_path else None,
        "gitopsHandoffBundle": str(handoff_path) if handoff_path else None,
        "gitopsPRBundle": str(bundle_path) if bundle_path else None,
    },
    "adapter": {
        "adapter": "gitops-handoff-local",
        "adapterType": nullable_string(adapter_request_body.get("adapterType")) or "gitops-handoff-local",
        "deliveryMode": "local_only_delivery_receipt",
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotCallExternalGitProvider": True,
        "emitsDeliveryReceipt": True,
    },
    "delivery": {
        "deliveryStatus": delivery_status,
        "requestedOperation": nullable_string(adapter_request_body.get("requestedOperation")),
        "summary": delivery_summary(delivery_status, requested_action, len(output_files), branch_name),
        "receipt": {
            "bundleDir": nullable_string(first_not_none(
                adapter_request_body.get("bundleDir"),
                handoff_body.get("bundleDir"),
            )),
            "branchName": branch_name,
            "commitMessage": commit_message,
            "pullRequestTitle": pull_request_title,
            "localOnly": True,
            "receivedAt": now(),
            "processedAt": now(),
        },
        "outputFiles": output_files,
        "warnings": warnings,
        "failureReason": None if delivery_status != "FAILED" else "gitops adapter request did not resolve to a supported delivery state",
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
        "derivedFromGitopsAdapterRequest": as_dict(adapter_request.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterResult"] = str(output_json)
evidence["gitopsAdapterResultId"] = result["gitopsAdapterResultId"]
evidence["gitopsAdapterResultRef"] = {
    "json": str(output_json),
    "deliveryStatus": result["delivery"]["deliveryStatus"],
    "adapterType": result["adapter"]["adapterType"],
    "outputFileCount": len(output_files),
}

decision_refs["gitopsAdapterResult"] = {
    "gitopsAdapterResultId": result["gitopsAdapterResultId"],
    "deliveryStatus": result["delivery"]["deliveryStatus"],
    "adapterType": result["adapter"]["adapterType"],
    "requestedOperation": result["delivery"]["requestedOperation"],
    "branchName": branch_name,
    "outputFileCount": len(output_files),
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter result generated: {output_json}")
print(f"Latest GitOps adapter result: {latest_json}")
print(f"GitOps adapter result linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterResultId": result["gitopsAdapterResultId"],
    "releaseId": release_id,
    "deliveryStatus": result["delivery"]["deliveryStatus"],
    "adapterType": result["adapter"]["adapterType"],
    "outputFileCount": len(output_files),
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_RESULT

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
