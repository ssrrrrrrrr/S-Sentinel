#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-patch-proposal.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                    Optional report directory.
  GITOPS_PATCH_PROPOSAL_OUTPUT_DIR      Optional output directory.
  GITOPS_PATCH_PROPOSAL_OUTPUT_FILE     Optional exact output file.
  GITOPS_PROPOSAL_RENDERED_PLAN         Optional rendered-release-plan.json override.

Behavior:
  - Reads release evidence, execution preview/result, and rendered release plan outputs.
  - Generates gitops-patch-proposal-*.json and gitops-patch-proposal-latest.json.
  - Produces a review-only proposal; it never commits, pushes, creates PRs, or mutates GitOps/Kubernetes.
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

OUTPUT_DIR="${GITOPS_PATCH_PROPOSAL_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_PATCH_PROPOSAL_OUTPUT_FILE:-$OUTPUT_DIR/gitops-patch-proposal-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-patch-proposal-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_PROPOSAL'
from __future__ import annotations

import json
import os
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


def infer_rendered_release_plan(evidence: dict[str, Any], source_path: Path) -> Path | None:
    artifacts = as_dict(evidence.get("artifacts"))
    explicit = resolve_ref(
        first_not_none(
            artifacts.get("renderedReleasePlan"),
            evidence.get("renderedReleasePlan"),
            os.environ.get("GITOPS_PROPOSAL_RENDERED_PLAN"),
            os.environ.get("EXECUTION_PREVIEW_RENDERED_PLAN"),
        ),
        source_path,
    )
    if explicit:
        return explicit

    env = nullable_string(first_not_none(evidence.get("env"), as_dict(evidence.get("environment")).get("env")))
    if env:
        candidates = [
            Path.cwd() / "build" / "compiled" / env / "rendered-release-plan.json",
            source_path.parent / "build" / "compiled" / env / "rendered-release-plan.json",
        ]
        for candidate in candidates:
            try:
                if candidate.exists() and candidate.is_file():
                    return candidate
            except OSError:
                continue
    return None


def proposal_status_from(preview_status: str, ready_to_execute: bool, patch_count: int, blocked_count: int) -> str:
    if blocked_count > 0 and preview_status == "BLOCKED":
        return "BLOCKED"
    if patch_count == 0:
        if preview_status == "NO_ACTION_REQUIRED":
            return "NO_CHANGES_REQUIRED"
        return "NEEDS_MORE_EVIDENCE"
    if preview_status == "WAITING_APPROVAL":
        return "WAITING_APPROVAL"
    if preview_status == "READY_TO_EXECUTE" or ready_to_execute:
        return "READY_FOR_REVIEW"
    if preview_status == "BLOCKED":
        return "BLOCKED"
    return "NEEDS_MORE_EVIDENCE"


def proposal_summary(status: str, requested_action: str | None, patch_count: int, overlay_path: str | None) -> str:
    action = requested_action or "UNKNOWN"
    overlay = overlay_path or "unknown overlay"
    if status == "READY_FOR_REVIEW":
        return f"GitOps patch proposal for {action} is ready for review with {patch_count} rendered change(s) targeting {overlay}."
    if status == "WAITING_APPROVAL":
        return f"GitOps patch proposal for {action} was assembled, but human approval is still required before review handoff."
    if status == "BLOCKED":
        return f"GitOps patch proposal for {action} is blocked by execution gates and remains advisory only."
    if status == "NO_CHANGES_REQUIRED":
        return "No GitOps patch proposal was generated because the release does not require GitOps changes."
    return f"GitOps patch proposal for {action} is incomplete and still needs more evidence before review."


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
decision_refs = as_dict(evidence.get("decisionRefs"))
environment = as_dict(evidence.get("environment"))

execution_preview_path = resolve_ref(artifacts.get("executionPreview"), input_path)
execution_preview = load_json(execution_preview_path)
preview_body = as_dict(execution_preview.get("preview"))
preview_target = as_dict(preview_body.get("targetEnvironment"))

execution_result_path = resolve_ref(artifacts.get("executionResult"), input_path)
execution_result = load_json(execution_result_path)
result_body = as_dict(execution_result.get("result"))

environment_config_path = resolve_ref(
    first_not_none(artifacts.get("environmentConfig"), evidence.get("environmentConfigRef"), environment.get("configRef")),
    input_path,
)
rendered_release_plan_path = infer_rendered_release_plan(evidence, input_path)
rendered_release_plan = load_json(rendered_release_plan_path)
rendered_inputs = as_dict(rendered_release_plan.get("inputs"))
rendered_outputs = as_dict(rendered_release_plan.get("outputs"))
rendered_release = as_dict(rendered_release_plan.get("release"))
rendered_refs = as_dict(rendered_release_plan.get("sourceConfigRefs"))
environment_config_ref = as_dict(rendered_refs.get("environmentConfig"))

release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    as_dict(execution_preview.get("release")).get("releaseId"),
    as_dict(execution_result.get("release")).get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)
service = first_not_none(
    evidence.get("service"),
    as_dict(execution_preview.get("release")).get("service"),
    rendered_release.get("service"),
)
env = first_not_none(
    evidence.get("env"),
    as_dict(execution_preview.get("release")).get("env"),
    rendered_release.get("env"),
    environment.get("env"),
)
namespace = first_not_none(
    evidence.get("namespace"),
    as_dict(execution_preview.get("release")).get("namespace"),
    rendered_release.get("namespace"),
    environment.get("namespace"),
)
policy_decision = first_not_none(
    evidence.get("policyDecision"),
    as_dict(execution_preview.get("release")).get("policyDecision"),
)
final_action = first_not_none(
    evidence.get("finalAction"),
    as_dict(execution_preview.get("release")).get("finalAction"),
)
requested_action = nullable_string(first_not_none(
    preview_body.get("requestedAction"),
    result_body.get("requestedAction"),
    evidence.get("requestedAction"),
    final_action,
))
preview_status = nullable_string(preview_body.get("previewStatus")) or "NEEDS_MORE_EVIDENCE"
ready_to_execute = bool(first_not_none(preview_body.get("readyToExecute"), result_body.get("readyForExecution"), False))
overlay_path = nullable_string(first_not_none(
    preview_target.get("gitopsOverlayPath"),
    evidence.get("gitopsOverlayPath"),
    environment.get("gitopsOverlayPath"),
    rendered_inputs.get("overlayPath"),
))
output_dir = nullable_string(rendered_outputs.get("outputDir"))
repository_root = nullable_string(first_not_none(
    environment_config_ref.get("repositoryRoot"),
    rendered_release_plan.get("repositoryRoot"),
))

patch_set: list[dict[str, Any]] = []
for idx, change in enumerate(as_list(preview_body.get("gitopsChanges"))):
    if not isinstance(change, dict):
        continue
    rel_path = nullable_string(change.get("path"))
    renderer_ref = nullable_string(change.get("rendererRef"))
    kind = nullable_string(change.get("kind"))
    patch_set.append({
        "patchId": f"patch-{idx + 1}",
        "changeType": "rendered_manifest_update",
        "path": rel_path,
        "summary": f"Review rendered {kind or 'artifact'} update for {rel_path or 'unknown path'}.",
        "overlayPath": overlay_path,
        "rendererRef": renderer_ref,
        "resourceKind": kind,
        "outputDir": output_dir,
        "targetRef": f"{overlay_path}/{rel_path}" if overlay_path and rel_path else rel_path,
        "dryRunOnly": True,
    })

blocked_changes: list[dict[str, Any]] = []
for idx, blocked in enumerate(as_list(preview_body.get("blockedActions"))):
    if not isinstance(blocked, dict):
        continue
    blocked_changes.append({
        "blockedChangeId": f"blocked-{idx + 1}",
        "actionId": blocked.get("actionId"),
        "reason": blocked.get("reason"),
        "commandPreview": blocked.get("commandPreview"),
        "dryRunOnly": True,
    })

proposal_status = proposal_status_from(preview_status, ready_to_execute, len(patch_set), len(blocked_changes))
review_hints = unique_strings(
    [
        f"Review overlay path: {overlay_path}" if overlay_path else None,
        f"Review rendered output directory: {output_dir}" if output_dir else None,
        "Confirm rendered manifests match policy-bound execution intent." if patch_set else None,
        "Open a GitOps PR manually or via a future adapter after review." if patch_set else None,
    ]
    + as_list(as_dict(decision_refs.get("executionEligibility")).get("approvalReasons"))
    + as_list(as_dict(decision_refs.get("executionEligibility")).get("missingInputs"))
)

proposal = {
    "schemaVersion": "gitops.patch.proposal/v1alpha1",
    "gitopsPatchProposalId": f"gp-{release_id}",
    "generatedBy": "build-gitops-patch-proposal.sh",
    "generatedAt": now(),
    "mode": "review_only_gitops_patch_proposal",
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
        "executionPreview": str(execution_preview_path) if execution_preview_path else None,
        "executionResult": str(execution_result_path) if execution_result_path else None,
        "renderedReleasePlan": str(rendered_release_plan_path) if rendered_release_plan_path else None,
        "environmentConfig": str(environment_config_path) if environment_config_path else None,
    },
    "proposal": {
        "proposalStatus": proposal_status,
        "requestedAction": requested_action,
        "summary": proposal_summary(proposal_status, requested_action, len(patch_set), overlay_path),
        "overlayPath": overlay_path,
        "repository": {
            "root": repository_root,
            "outputDir": output_dir,
            "environmentConfigRef": first_not_none(
                evidence.get("environmentConfigRef"),
                environment.get("configRef"),
                rendered_inputs.get("environmentConfigRef"),
            ),
        },
        "patchSet": patch_set,
        "blockedChanges": blocked_changes,
        "reviewHints": review_hints,
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
output_json.write_text(json.dumps(proposal, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

release_evidence = evidence
artifacts = release_evidence.setdefault("artifacts", {})
artifacts["gitopsPatchProposal"] = str(output_json)

release_evidence["gitopsPatchProposalId"] = proposal["gitopsPatchProposalId"]
release_evidence["gitopsPatchProposalRef"] = {
    "json": str(output_json),
    "proposalStatus": proposal["proposal"]["proposalStatus"],
    "overlayPath": overlay_path,
    "patchCount": len(patch_set),
}

decision_refs = release_evidence.setdefault("decisionRefs", {})
decision_refs["gitopsPatchProposal"] = {
    "gitopsPatchProposalId": proposal["gitopsPatchProposalId"],
    "proposalStatus": proposal["proposal"]["proposalStatus"],
    "requestedAction": requested_action,
    "overlayPath": overlay_path,
    "patchCount": len(patch_set),
    "blockedChangeCount": len(blocked_changes),
    "repositoryRoot": repository_root,
    "outputDir": output_dir,
    "source": str(output_json),
}

input_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps patch proposal generated: {output_json}")
print(f"Latest GitOps patch proposal: {latest_json}")
print(f"GitOps patch proposal linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsPatchProposalId": proposal["gitopsPatchProposalId"],
    "releaseId": release_id,
    "proposalStatus": proposal["proposal"]["proposalStatus"],
    "overlayPath": overlay_path,
    "patchCount": len(patch_set),
    "blockedChangeCount": len(blocked_changes),
}, ensure_ascii=False, indent=2))
PY_GITOPS_PROPOSAL

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
