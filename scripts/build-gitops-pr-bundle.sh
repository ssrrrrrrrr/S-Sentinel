#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-pr-bundle.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR               Optional report directory.
  GITOPS_PR_BUNDLE_OUTPUT_DIR      Optional output directory.
  GITOPS_PR_BUNDLE_OUTPUT_FILE     Optional exact output file.

Behavior:
  - Reads release evidence, GitOps patch proposal, execution preview, and execution result.
  - Generates gitops-pr-bundle-*.json and gitops-pr-bundle-latest.json.
  - Produces a PR-ready handoff bundle only; it never commits, pushes, opens PRs, or mutates GitOps/Kubernetes.
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

OUTPUT_DIR="${GITOPS_PR_BUNDLE_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_PR_BUNDLE_OUTPUT_FILE:-$OUTPUT_DIR/gitops-pr-bundle-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-pr-bundle-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_PR_BUNDLE'
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


def slug(value: Any, fallback: str) -> str:
    text = nullable_string(value) or fallback
    cleaned = []
    for ch in text:
        cleaned.append(ch.lower() if ch.isalnum() else "-")
    result = "".join(cleaned).strip("-")
    while "--" in result:
        result = result.replace("--", "-")
    return result or fallback


def unique_strings(values: list[Any]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in values:
        text = nullable_string(item)
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result


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


def bundle_summary(status: str, requested_action: str | None, patch_count: int) -> str:
    action = requested_action or "UNKNOWN"
    if status == "READY_FOR_REVIEW":
        return f"PR-ready GitOps bundle for {action} is ready with {patch_count} patch entrie(s)."
    if status == "WAITING_APPROVAL":
        return f"PR-ready GitOps bundle for {action} is assembled, but approval is still pending."
    if status == "BLOCKED":
        return f"PR-ready GitOps bundle for {action} is blocked and remains advisory only."
    if status == "NO_CHANGES_REQUIRED":
        return "No GitOps PR bundle was generated because no patch handoff is required."
    return f"PR-ready GitOps bundle for {action} still needs more evidence."


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
decision_refs = as_dict(evidence.get("decisionRefs"))

proposal_path = resolve_ref(artifacts.get("gitopsPatchProposal"), input_path)
proposal = load_json(proposal_path)
proposal_body = as_dict(proposal.get("proposal"))
proposal_repo = as_dict(proposal_body.get("repository"))

execution_preview_path = resolve_ref(artifacts.get("executionPreview"), input_path)
execution_preview = load_json(execution_preview_path)
preview_body = as_dict(execution_preview.get("preview"))

execution_result_path = resolve_ref(artifacts.get("executionResult"), input_path)
execution_result = load_json(execution_result_path)
result_body = as_dict(execution_result.get("result"))

release = as_dict(proposal.get("release"))
release_id = nullable_string(first_not_none(
    release.get("releaseId"),
    evidence.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)
service = first_not_none(release.get("service"), evidence.get("service"))
env = first_not_none(release.get("env"), evidence.get("env"))
namespace = first_not_none(release.get("namespace"), evidence.get("namespace"))
policy_decision = first_not_none(release.get("policyDecision"), evidence.get("policyDecision"))
final_action = first_not_none(release.get("finalAction"), evidence.get("finalAction"))
requested_action = nullable_string(first_not_none(
    proposal_body.get("requestedAction"),
    preview_body.get("requestedAction"),
    result_body.get("requestedAction"),
    evidence.get("requestedAction"),
    final_action,
))
proposal_status = nullable_string(proposal_body.get("proposalStatus")) or "NEEDS_MORE_EVIDENCE"
overlay_path = nullable_string(proposal_body.get("overlayPath"))
patch_set = [item for item in as_list(proposal_body.get("patchSet")) if isinstance(item, dict)]
review_hints = unique_strings(as_list(proposal_body.get("reviewHints")))
approval_reasons = unique_strings(as_list(as_dict(decision_refs.get("executionEligibility")).get("approvalReasons")))
missing_inputs = unique_strings(as_list(as_dict(decision_refs.get("executionEligibility")).get("missingInputs")))

branch_suffix = slug(f"{service}-{env}-{requested_action}", "release")
branch_name = f"ssentinel/{branch_suffix}-{release_id}"
commit_message = f"chore(gitops): prepare {requested_action or 'release update'} for {service or 'service'} [{release_id}]"
pr_title = f"[S Sentinel] {requested_action or 'Review release update'} for {service or 'service'} ({env or 'env'})"

body_lines = [
    f"Release ID: `{release_id}`",
    f"Requested action: `{requested_action or 'UNKNOWN'}`",
    f"Bundle status: `{proposal_status}`",
    f"Policy decision: `{policy_decision or 'UNKNOWN'}`",
    f"Final action: `{final_action or 'UNKNOWN'}`",
    f"Overlay path: `{overlay_path or 'unknown'}`",
    "",
    "Patch entries:",
]

for patch in patch_set:
    path = nullable_string(patch.get("path")) or "unknown-path"
    summary = nullable_string(patch.get("summary")) or "review rendered change"
    body_lines.append(f"- `{path}`: {summary}")

if not patch_set:
    body_lines.append("- none")

if review_hints:
    body_lines.extend(["", "Review hints:"])
    body_lines.extend([f"- {hint}" for hint in review_hints])

if approval_reasons or missing_inputs:
    body_lines.extend(["", "Gate notes:"])
    body_lines.extend([f"- {item}" for item in approval_reasons + missing_inputs])

bundle_status = proposal_status
handoff_checklist = unique_strings([
    "Validate rendered manifests against target overlay before creating a PR." if patch_set else None,
    "Keep PR review-only; do not merge automatically." if patch_set else None,
    "Attach execution evidence, preview, and proposal objects to the review handoff." if patch_set else None,
    "Wait for explicit approval before handing off the bundle." if bundle_status == "WAITING_APPROVAL" else None,
] + review_hints + approval_reasons + missing_inputs)

patch_entries = []
for idx, patch in enumerate(patch_set):
    patch_entries.append({
        "entryId": f"bundle-entry-{idx + 1}",
        "path": patch.get("path"),
        "summary": patch.get("summary"),
        "changeType": patch.get("changeType"),
        "targetRef": patch.get("targetRef"),
        "rendererRef": patch.get("rendererRef"),
        "resourceKind": patch.get("resourceKind"),
        "dryRunOnly": True,
    })

bundle = {
    "schemaVersion": "gitops.pr.bundle/v1alpha1",
    "gitopsPRBundleId": f"gb-{release_id}",
    "generatedBy": "build-gitops-pr-bundle.sh",
    "generatedAt": now(),
    "mode": "review_only_gitops_pr_bundle",
    "release": {
        "releaseId": release_id,
        "service": service,
        "env": env,
        "namespace": namespace,
        "policyDecision": policy_decision,
        "finalAction": final_action,
        "requestedAction": requested_action,
    },
    "inputs": {
        "releaseEvidence": str(input_path),
        "gitopsPatchProposal": str(proposal_path) if proposal_path else None,
        "executionPreview": str(execution_preview_path) if execution_preview_path else None,
        "executionResult": str(execution_result_path) if execution_result_path else None,
    },
    "bundle": {
        "bundleStatus": bundle_status,
        "branchName": branch_name if patch_entries else None,
        "commitMessage": commit_message if patch_entries else None,
        "summary": bundle_summary(bundle_status, requested_action, len(patch_entries)),
        "repository": {
            "root": proposal_repo.get("root"),
            "outputDir": proposal_repo.get("outputDir"),
            "overlayPath": overlay_path,
        },
        "pullRequest": {
            "title": pr_title if patch_entries else "No GitOps PR required",
            "body": "\n".join(body_lines),
        },
        "patchEntries": patch_entries,
        "handoffChecklist": handoff_checklist,
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
output_json.write_text(json.dumps(bundle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

release_evidence = evidence
artifacts = release_evidence.setdefault("artifacts", {})
artifacts["gitopsPRBundle"] = str(output_json)

release_evidence["gitopsPRBundleId"] = bundle["gitopsPRBundleId"]
release_evidence["gitopsPRBundleRef"] = {
    "json": str(output_json),
    "bundleStatus": bundle["bundle"]["bundleStatus"],
    "branchName": bundle["bundle"]["branchName"],
    "patchEntryCount": len(patch_entries),
}

decision_refs = release_evidence.setdefault("decisionRefs", {})
decision_refs["gitopsPRBundle"] = {
    "gitopsPRBundleId": bundle["gitopsPRBundleId"],
    "bundleStatus": bundle["bundle"]["bundleStatus"],
    "branchName": bundle["bundle"]["branchName"],
    "commitMessage": bundle["bundle"]["commitMessage"],
    "pullRequestTitle": bundle["bundle"]["pullRequest"]["title"],
    "patchEntryCount": len(patch_entries),
    "handoffChecklistCount": len(handoff_checklist),
    "source": str(output_json),
}

input_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps PR bundle generated: {output_json}")
print(f"Latest GitOps PR bundle: {latest_json}")
print(f"GitOps PR bundle linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsPRBundleId": bundle["gitopsPRBundleId"],
    "releaseId": release_id,
    "bundleStatus": bundle["bundle"]["bundleStatus"],
    "branchName": bundle["bundle"]["branchName"],
    "patchEntryCount": len(patch_entries),
}, ensure_ascii=False, indent=2))
PY_GITOPS_PR_BUNDLE

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
