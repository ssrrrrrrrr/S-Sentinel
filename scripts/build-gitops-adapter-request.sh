#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-request.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                   Optional report directory.
  GITOPS_ADAPTER_REQUEST_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_REQUEST_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, GitOps patch proposal, PR bundle, and handoff bundle.
  - Generates gitops-adapter-request-*.json and gitops-adapter-request-latest.json.
  - Produces an adapter-ready request only; it never commits, pushes, creates PRs, or mutates GitOps/Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_REQUEST_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_REQUEST_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-request-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-request-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_REQUEST'
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


def request_status_from(handoff_status: str | None) -> str:
    if handoff_status == "READY_FOR_REVIEW":
        return "READY_FOR_ADAPTER"
    if handoff_status in {"BLOCKED", "WAITING_APPROVAL", "NO_CHANGES_REQUIRED"}:
        return handoff_status
    return "NEEDS_MORE_EVIDENCE"


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))

proposal_path = resolve_ref(artifacts.get("gitopsPatchProposal"), input_path)
proposal = load_json(proposal_path)

bundle_path = resolve_ref(artifacts.get("gitopsPRBundle"), input_path)
bundle = load_json(bundle_path)
bundle_body = as_dict(bundle.get("bundle"))
bundle_pr = as_dict(bundle_body.get("pullRequest"))

handoff_path = resolve_ref(artifacts.get("gitopsHandoffBundle"), input_path)
handoff = load_json(handoff_path)
handoff_body = as_dict(handoff.get("handoff"))

release = as_dict(bundle.get("release"))
release_id = nullable_string(first_not_none(
    release.get("releaseId"),
    evidence.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

request_status = request_status_from(nullable_string(handoff_body.get("handoffStatus")))
branch_name = nullable_string(handoff_body.get("branchName"))
commit_message = nullable_string(handoff_body.get("commitMessage"))
pull_request_title = nullable_string(handoff_body.get("pullRequestTitle"))
materialized_files = [item for item in as_list(handoff_body.get("materializedFiles")) if isinstance(item, dict)]

request = {
    "schemaVersion": "gitops.adapter.request/v1alpha1",
    "gitopsAdapterRequestId": f"ga-{release_id}",
    "generatedBy": "build-gitops-adapter-request.sh",
    "generatedAt": now(),
    "mode": "review_only_gitops_adapter_request",
    "release": {
        "releaseId": release_id,
        "service": release.get("service"),
        "env": release.get("env"),
        "namespace": release.get("namespace"),
        "policyDecision": release.get("policyDecision"),
        "finalAction": release.get("finalAction"),
        "requestedAction": release.get("requestedAction"),
    },
    "inputs": {
        "releaseEvidence": str(input_path),
        "gitopsPatchProposal": str(proposal_path) if proposal_path else None,
        "gitopsPRBundle": str(bundle_path) if bundle_path else None,
        "gitopsHandoffBundle": str(handoff_path) if handoff_path else None,
    },
    "request": {
        "requestStatus": request_status,
        "adapterType": "gitops-handoff-local",
        "requestedOperation": "prepare_review_handoff_delivery",
        "bundleDir": handoff_body.get("bundleDir"),
        "delivery": {
            "branchName": branch_name,
            "commitMessage": commit_message,
            "pullRequestTitle": pull_request_title,
            "localOnly": True,
            "doesNotCallExternalGitProvider": True,
        },
        "handoffFiles": materialized_files,
        "summary": proposal.get("proposal", {}).get("summary") if isinstance(proposal.get("proposal"), dict) else (
            f"Adapter-ready request for {release.get('requestedAction') or 'UNKNOWN'} is prepared as a local-only handoff."
        ),
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotModifyGitOps": True,
        "doesNotCommit": True,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotModifyKubernetes": True,
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

release_evidence = evidence
artifacts = release_evidence.setdefault("artifacts", {})
artifacts["gitopsAdapterRequest"] = str(output_json)

release_evidence["gitopsAdapterRequestId"] = request["gitopsAdapterRequestId"]
release_evidence["gitopsAdapterRequestRef"] = {
    "json": str(output_json),
    "requestStatus": request["request"]["requestStatus"],
    "adapterType": request["request"]["adapterType"],
    "handoffFileCount": len(materialized_files),
}

decision_refs = release_evidence.setdefault("decisionRefs", {})
decision_refs["gitopsAdapterRequest"] = {
    "gitopsAdapterRequestId": request["gitopsAdapterRequestId"],
    "requestStatus": request["request"]["requestStatus"],
    "adapterType": request["request"]["adapterType"],
    "requestedOperation": request["request"]["requestedOperation"],
    "branchName": branch_name,
    "handoffFileCount": len(materialized_files),
    "source": str(output_json),
}

input_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter request generated: {output_json}")
print(f"Latest GitOps adapter request: {latest_json}")
print(f"GitOps adapter request linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterRequestId": request["gitopsAdapterRequestId"],
    "releaseId": release_id,
    "requestStatus": request["request"]["requestStatus"],
    "adapterType": request["request"]["adapterType"],
    "handoffFileCount": len(materialized_files),
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_REQUEST

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
