#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-execution-preview.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                Optional report directory.
  EXECUTION_PREVIEW_OUTPUT_DIR      Optional output directory.
  EXECUTION_PREVIEW_OUTPUT_FILE     Optional exact output file.
  EXECUTION_PREVIEW_RENDERED_PLAN   Optional rendered-release-plan.json override.

Behavior:
  - Reads release evidence, execution request, eligibility, action plan, and compiler outputs.
  - Generates execution-preview-*.json and execution-preview-latest.json.
  - Produces a dry-run preview only; it never executes GitOps, kubectl, rollback, promote, patch, delete, build, commit, or push.
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

OUTPUT_DIR="${EXECUTION_PREVIEW_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${EXECUTION_PREVIEW_OUTPUT_FILE:-$OUTPUT_DIR/execution-preview-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/execution-preview-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_EXEC_PREVIEW'
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


def unique_strings(values: list[Any]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for item in values:
        text = nullable_string(item)
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result


def slug(value: Any, fallback: str) -> str:
    text = nullable_string(value) or fallback
    cleaned = []
    for ch in text:
        cleaned.append(ch.lower() if ch.isalnum() else "-")
    result = "".join(cleaned).strip("-")
    while "--" in result:
        result = result.replace("--", "-")
    return result or fallback


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


def status_summary(final_status: str, requested_action: str | None, planned_count: int) -> str:
    action = requested_action or "UNKNOWN"
    if final_status == "READY_TO_EXECUTE":
        return f"Controlled executor preview is ready for {action}; {planned_count} dry-run actions were prepared."
    if final_status == "WAITING_APPROVAL":
        return f"Execution preview for {action} is assembled, but human approval is still required."
    if final_status == "BLOCKED":
        return f"Execution preview for {action} is blocked by gate decisions and remains advisory only."
    if final_status == "NO_ACTION_REQUIRED":
        return "No execution preview actions were generated because no release action is required."
    return f"Execution preview for {action} is incomplete and still needs more evidence."


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
decision_refs = as_dict(evidence.get("decisionRefs"))
environment = as_dict(evidence.get("environment"))

execution_request_path = resolve_ref(artifacts.get("executionRequest"), input_path)
execution_request = load_json(execution_request_path)
execution_request_body = as_dict(execution_request.get("request"))
execution_policy = as_dict(execution_request.get("policyBinding"))

execution_eligibility_path = resolve_ref(artifacts.get("executionEligibility"), input_path)
execution_eligibility = load_json(execution_eligibility_path)
eligibility_release = as_dict(execution_eligibility.get("release"))
eligibility_request = as_dict(execution_eligibility.get("executionRequest"))
eligibility_decision = as_dict(execution_eligibility.get("decision"))

action_plan_path = resolve_ref(artifacts.get("actionPlan"), input_path)
action_plan = load_json(action_plan_path)
action_plan_body = as_dict(action_plan.get("actionPlan"))
action_plan_target = as_dict(action_plan.get("target"))

supply_chain_path = resolve_ref(artifacts.get("supplyChainDecision"), input_path)
supply_chain = load_json(supply_chain_path)
supply_chain_decision = as_dict(supply_chain.get("decision"))

environment_config_path = resolve_ref(
    first_not_none(artifacts.get("environmentConfig"), evidence.get("environmentConfigRef"), environment.get("configRef")),
    input_path,
)
rendered_release_plan_path = infer_rendered_release_plan(evidence, input_path)
rendered_release_plan = load_json(rendered_release_plan_path)
rendered_outputs = as_dict(rendered_release_plan.get("outputs"))
rendered_strategy = as_dict(rendered_release_plan.get("strategy"))
rendered_release = as_dict(rendered_release_plan.get("release"))

release_id = nullable_string(first_not_none(
    eligibility_release.get("releaseId"),
    evidence.get("releaseId"),
    rendered_release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)
service = first_not_none(evidence.get("service"), eligibility_release.get("service"), rendered_release.get("service"))
env = first_not_none(evidence.get("env"), eligibility_release.get("env"), rendered_release.get("env"), environment.get("env"))
namespace = first_not_none(evidence.get("namespace"), eligibility_release.get("namespace"), rendered_release.get("namespace"), environment.get("namespace"))
policy_decision = first_not_none(evidence.get("policyDecision"), eligibility_release.get("policyDecision"), execution_policy.get("policyDecision"))
final_action = first_not_none(evidence.get("finalAction"), eligibility_release.get("finalAction"), execution_request_body.get("requestedAction"))
requested_action = nullable_string(first_not_none(
    eligibility_request.get("requestedAction"),
    execution_request_body.get("requestedAction"),
    evidence.get("requestedAction"),
    final_action,
))
preview_status = nullable_string(eligibility_decision.get("finalStatus")) or "NEEDS_MORE_EVIDENCE"
ready_to_execute = bool(eligibility_decision.get("readyToExecute"))
requires_human_approval = bool(first_not_none(
    execution_policy.get("requiresHumanApproval"),
    evidence.get("requiresHumanApproval"),
    False,
))

target_environment = {
    "env": env,
    "namespace": namespace,
    "clusterName": first_not_none(evidence.get("clusterName"), environment.get("clusterName"), rendered_release.get("clusterName")),
    "environmentClass": first_not_none(evidence.get("environmentClass"), environment.get("environmentClass"), rendered_release.get("environmentClass")),
    "policyProfile": first_not_none(evidence.get("policyProfile"), environment.get("policyProfile"), rendered_release.get("policyProfile")),
    "gitopsOverlayPath": first_not_none(evidence.get("gitopsOverlayPath"), environment.get("gitopsOverlayPath"), rendered_release_plan.get("inputs", {}).get("overlayPath") if isinstance(rendered_release_plan.get("inputs"), dict) else None),
}

planned_actions: list[dict[str, Any]] = []
blocked_actions: list[dict[str, Any]] = []

for idx, command in enumerate(as_list(action_plan_body.get("candidateCommands"))):
    if not isinstance(command, dict):
        continue
    title = nullable_string(command.get("name")) or f"command-{idx + 1}"
    command_text = nullable_string(command.get("command"))
    command_type = nullable_string(command.get("type")) or "read_only"
    blocked = "write" in command_type or preview_status == "BLOCKED"
    action = {
        "actionId": f"preview-cmd-{idx + 1}",
        "title": title.replace("_", " "),
        "category": "command_preview",
        "target": {
            "namespace": namespace,
            "rollout": action_plan_target.get("rollout"),
            "analysisRun": action_plan_target.get("analysisRun"),
        },
        "dryRunOnly": True,
        "blocked": blocked,
        "requiresApproval": requires_human_approval,
        "commandPreview": command_text,
        "description": f"Preview command from action plan ({command_type}).",
        "source": str(action_plan_path) if action_plan_path else None,
    }
    planned_actions.append(action)
    if blocked:
        blocked_actions.append({
            "actionId": action["actionId"],
            "reason": "write_candidate_requires_controlled_executor" if "write" in command_type else "execution_status_blocked",
            "commandPreview": command_text,
        })

gitops_changes: list[dict[str, Any]] = []
for idx, artifact in enumerate(as_list(rendered_outputs.get("artifacts"))):
    if not isinstance(artifact, dict):
        continue
    path = nullable_string(artifact.get("path"))
    renderer_ref = nullable_string(artifact.get("rendererRef"))
    kind = nullable_string(artifact.get("kind"))
    gitops_changes.append({
        "changeId": f"gitops-{idx + 1}",
        "kind": kind,
        "path": path,
        "rendererRef": renderer_ref,
        "action": "rendered_only",
        "dryRunOnly": True,
    })

if gitops_changes:
    planned_actions.append({
        "actionId": "preview-gitops-render",
        "title": "Render GitOps artifacts",
        "category": "gitops_preview",
        "target": {
            "overlayPath": target_environment.get("gitopsOverlayPath"),
            "outputDir": rendered_outputs.get("outputDir"),
        },
        "dryRunOnly": True,
        "blocked": False,
        "requiresApproval": requires_human_approval,
        "description": f"Preview {len(gitops_changes)} rendered GitOps artifacts without applying or committing them.",
        "source": str(rendered_release_plan_path) if rendered_release_plan_path else None,
    })

if not planned_actions and requested_action not in (None, "", "NOOP", "NONE"):
    planned_actions.append({
        "actionId": f"preview-{slug(requested_action, 'action')}",
        "title": f"Prepare {requested_action}",
        "category": "execution_preview",
        "target": {
            "env": env,
            "namespace": namespace,
        },
        "dryRunOnly": True,
        "blocked": preview_status == "BLOCKED",
        "requiresApproval": requires_human_approval,
        "description": "Synthesize a controlled executor preview from execution eligibility when no explicit command preview exists.",
        "source": str(execution_eligibility_path) if execution_eligibility_path else None,
    })
    if preview_status == "BLOCKED":
        blocked_actions.append({
            "actionId": f"preview-{slug(requested_action, 'action')}",
            "reason": "eligibility_blocked",
        })

human_checkpoints: list[dict[str, Any]] = []
for idx, step in enumerate(as_list(action_plan_body.get("humanSteps"))):
    text = nullable_string(step)
    if not text:
        continue
    human_checkpoints.append({
        "checkpointId": f"human-step-{idx + 1}",
        "type": "operator_step",
        "text": text,
        "required": True,
    })

for reason in unique_strings(
    as_list(eligibility_decision.get("approvalReasons")) +
    as_list(eligibility_decision.get("missingInputs")) +
    as_list(supply_chain_decision.get("warningReasons"))
):
    human_checkpoints.append({
        "checkpointId": f"checkpoint-{slug(reason, 'reason')}",
        "type": "gate_reason",
        "text": reason,
        "required": preview_status != "READY_TO_EXECUTE",
    })

rollout_plan = {
    "strategyId": first_not_none(evidence.get("strategyId"), rendered_strategy.get("strategyId")),
    "strategyType": rendered_strategy.get("strategyType"),
    "trafficSteps": rendered_strategy.get("trafficSteps") or [],
    "analysis": rendered_strategy.get("analysis") or {},
    "renderedArtifacts": len(gitops_changes),
    "analysisTemplate": rendered_outputs.get("analysisTemplate"),
    "rolloutManifest": rendered_outputs.get("rollout"),
    "kustomization": rendered_outputs.get("kustomization"),
}

summary = status_summary(preview_status, requested_action, len(planned_actions))

preview = {
    "schemaVersion": "execution.preview/v1alpha1",
    "executionPreviewId": f"ep-{release_id}",
    "generatedBy": "build-execution-preview.sh",
    "generatedAt": now(),
    "mode": "dry_run_execution_preview",
    "release": {
        "releaseId": release_id,
        "service": service,
        "env": env,
        "namespace": namespace,
        "version": first_not_none(rendered_release.get("appVersion"), evidence.get("version")),
        "commit": evidence.get("commit"),
        "policyDecision": policy_decision,
        "finalAction": final_action,
    },
    "inputs": {
        "releaseEvidence": str(input_path),
        "executionRequest": str(execution_request_path) if execution_request_path else None,
        "executionEligibility": str(execution_eligibility_path) if execution_eligibility_path else None,
        "actionPlan": str(action_plan_path) if action_plan_path else None,
        "renderedReleasePlan": str(rendered_release_plan_path) if rendered_release_plan_path else None,
        "environmentConfig": str(environment_config_path) if environment_config_path else None,
        "supplyChainDecision": str(supply_chain_path) if supply_chain_path else None,
    },
    "preview": {
        "previewStatus": preview_status,
        "readyToExecute": ready_to_execute,
        "requestedAction": requested_action,
        "summary": summary,
        "targetEnvironment": target_environment,
        "plannedActions": planned_actions,
        "blockedActions": blocked_actions,
        "humanCheckpoints": human_checkpoints,
        "gitopsChanges": gitops_changes,
        "rolloutPlan": rollout_plan,
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotRollback": True,
        "doesNotPromote": True,
        "doesNotPatchResources": True,
        "doesNotDeleteResources": True,
        "doesNotBuildImages": True,
        "doesNotCommitOrPush": True,
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(preview, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

release_evidence = evidence
artifacts = release_evidence.setdefault("artifacts", {})
artifacts["executionPreview"] = str(output_json)

release_evidence["executionPreviewId"] = preview["executionPreviewId"]
release_evidence["executionPreviewRef"] = {
    "json": str(output_json),
    "previewStatus": preview["preview"]["previewStatus"],
    "readyToExecute": preview["preview"]["readyToExecute"],
    "plannedActionCount": len(planned_actions),
}

decision_refs = release_evidence.setdefault("decisionRefs", {})
decision_refs["executionPreview"] = {
    "executionPreviewId": preview["executionPreviewId"],
    "previewStatus": preview["preview"]["previewStatus"],
    "readyToExecute": preview["preview"]["readyToExecute"],
    "requestedAction": requested_action,
    "plannedActionCount": len(planned_actions),
    "blockedActionCount": len(blocked_actions),
    "humanCheckpointCount": len(human_checkpoints),
    "gitopsChangeCount": len(gitops_changes),
    "renderedReleasePlan": str(rendered_release_plan_path) if rendered_release_plan_path else None,
    "source": str(output_json),
}

input_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Execution preview generated: {output_json}")
print(f"Latest execution preview: {latest_json}")
print(f"Execution preview linked into release evidence: {input_path}")
print(json.dumps({
    "executionPreviewId": preview["executionPreviewId"],
    "releaseId": release_id,
    "previewStatus": preview["preview"]["previewStatus"],
    "readyToExecute": preview["preview"]["readyToExecute"],
    "plannedActionCount": len(planned_actions),
    "blockedActionCount": len(blocked_actions),
    "humanCheckpointCount": len(human_checkpoints),
    "gitopsChangeCount": len(gitops_changes),
}, ensure_ascii=False, indent=2))
PY_EXEC_PREVIEW

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
