#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-handoff-bundle.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                    Optional report directory.
  GITOPS_HANDOFF_OUTPUT_DIR             Optional output directory.
  GITOPS_HANDOFF_OUTPUT_FILE            Optional exact output file.

Behavior:
  - Reads release evidence, GitOps patch proposal, and GitOps PR bundle.
  - Generates gitops-handoff-bundle-*.json and gitops-handoff-bundle-latest.json.
  - Materializes review-only handoff files (manifest, PR markdown, patch entries, checklist).
  - Never commits, pushes, creates PRs, or mutates GitOps/Kubernetes.
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

OUTPUT_DIR="${GITOPS_HANDOFF_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_HANDOFF_OUTPUT_FILE:-$OUTPUT_DIR/gitops-handoff-bundle-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-handoff-bundle-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_HANDOFF'
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


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))

proposal_path = resolve_ref(artifacts.get("gitopsPatchProposal"), input_path)
proposal = load_json(proposal_path)
proposal_body = as_dict(proposal.get("proposal"))

bundle_path = resolve_ref(artifacts.get("gitopsPRBundle"), input_path)
bundle = load_json(bundle_path)
bundle_body = as_dict(bundle.get("bundle"))
bundle_repo = as_dict(bundle_body.get("repository"))
bundle_pr = as_dict(bundle_body.get("pullRequest"))

release = as_dict(bundle.get("release"))
release_id = nullable_string(first_not_none(
    release.get("releaseId"),
    evidence.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

handoff_dir = output_json.parent / f"gitops-handoff-{release_id}"
handoff_dir.mkdir(parents=True, exist_ok=True)

manifest_path = handoff_dir / "manifest.json"
patch_entries_path = handoff_dir / "patch-entries.json"
pull_request_path = handoff_dir / "pull-request.md"
checklist_path = handoff_dir / "handoff-checklist.md"

patch_entries = [item for item in as_list(bundle_body.get("patchEntries")) if isinstance(item, dict)]
checklist = [str(item) for item in as_list(bundle_body.get("handoffChecklist")) if str(item).strip()]

manifest = {
    "schemaVersion": "gitops.handoff.manifest/v1alpha1",
    "generatedAt": now(),
    "generatedBy": "build-gitops-handoff-bundle.sh",
    "releaseId": release_id,
    "bundleStatus": bundle_body.get("bundleStatus"),
    "branchName": bundle_body.get("branchName"),
    "commitMessage": bundle_body.get("commitMessage"),
    "pullRequestTitle": bundle_pr.get("title"),
    "overlayPath": bundle_repo.get("overlayPath"),
    "patchEntryCount": len(patch_entries),
    "handoffChecklistCount": len(checklist),
}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
patch_entries_path.write_text(json.dumps(patch_entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

pull_request_lines = [
    f"# {bundle_pr.get('title') or 'GitOps Review Handoff'}",
    "",
    bundle_pr.get("body") or "",
]
pull_request_path.write_text("\n".join(pull_request_lines).strip() + "\n", encoding="utf-8")

checklist_lines = ["# Handoff Checklist", ""]
checklist_lines.extend([f"- {item}" for item in checklist] if checklist else ["- none"])
checklist_path.write_text("\n".join(checklist_lines) + "\n", encoding="utf-8")

materialized_files = [
    {
        "fileId": "manifest",
        "path": str(manifest_path),
        "contentType": "application/json",
        "description": "Materialized handoff manifest.",
    },
    {
        "fileId": "patchEntries",
        "path": str(patch_entries_path),
        "contentType": "application/json",
        "description": "Materialized patch entries for review handoff.",
    },
    {
        "fileId": "pullRequest",
        "path": str(pull_request_path),
        "contentType": "text/markdown",
        "description": "Materialized PR body markdown.",
    },
    {
        "fileId": "handoffChecklist",
        "path": str(checklist_path),
        "contentType": "text/markdown",
        "description": "Materialized handoff checklist markdown.",
    },
]

handoff = {
    "schemaVersion": "gitops.handoff.bundle/v1alpha1",
    "gitopsHandoffBundleId": f"hb-{release_id}",
    "generatedBy": "build-gitops-handoff-bundle.sh",
    "generatedAt": now(),
    "mode": "review_only_gitops_handoff_bundle",
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
    },
    "handoff": {
        "handoffStatus": bundle_body.get("bundleStatus"),
        "bundleDir": str(handoff_dir),
        "materializedFiles": materialized_files,
        "branchName": bundle_body.get("branchName"),
        "commitMessage": bundle_body.get("commitMessage"),
        "pullRequestTitle": bundle_pr.get("title"),
        "summary": proposal_body.get("summary"),
        "patchEntryCount": len(patch_entries),
        "handoffChecklistCount": len(checklist),
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
output_json.write_text(json.dumps(handoff, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

release_evidence = evidence
artifacts = release_evidence.setdefault("artifacts", {})
artifacts["gitopsHandoffBundle"] = str(output_json)

release_evidence["gitopsHandoffBundleId"] = handoff["gitopsHandoffBundleId"]
release_evidence["gitopsHandoffBundleRef"] = {
    "json": str(output_json),
    "handoffStatus": handoff["handoff"]["handoffStatus"],
    "bundleDir": str(handoff_dir),
    "materializedFileCount": len(materialized_files),
}

decision_refs = release_evidence.setdefault("decisionRefs", {})
decision_refs["gitopsHandoffBundle"] = {
    "gitopsHandoffBundleId": handoff["gitopsHandoffBundleId"],
    "handoffStatus": handoff["handoff"]["handoffStatus"],
    "bundleDir": str(handoff_dir),
    "branchName": handoff["handoff"]["branchName"],
    "materializedFileCount": len(materialized_files),
    "patchEntryCount": len(patch_entries),
    "handoffChecklistCount": len(checklist),
    "source": str(output_json),
}

input_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps handoff bundle generated: {output_json}")
print(f"Latest GitOps handoff bundle: {latest_json}")
print(f"GitOps handoff bundle linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsHandoffBundleId": handoff["gitopsHandoffBundleId"],
    "releaseId": release_id,
    "handoffStatus": handoff["handoff"]["handoffStatus"],
    "bundleDir": str(handoff_dir),
    "materializedFileCount": len(materialized_files),
}, ensure_ascii=False, indent=2))
PY_GITOPS_HANDOFF

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
