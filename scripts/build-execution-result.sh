#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-execution-result.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR               Optional report directory.
  EXECUTION_RESULT_OUTPUT_DIR      Optional output directory.
  EXECUTION_RESULT_OUTPUT_FILE     Optional exact output file.

Behavior:
  - Reads release evidence, execution request, eligibility, and execution preview.
  - Generates execution-result-*.json and execution-result-latest.json.
  - Emits execution evidence only; it never executes GitOps, kubectl, rollback, promote, patch, delete, build, commit, or push.
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

OUTPUT_DIR="${EXECUTION_RESULT_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${EXECUTION_RESULT_OUTPUT_FILE:-$OUTPUT_DIR/execution-result-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/execution-result-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_EXEC_RESULT'
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


def result_status(preview_status: str | None, ready_to_execute: bool, has_preview: bool) -> str:
    if not has_preview:
        return "NOT_EXECUTED"
    if preview_status == "BLOCKED":
        return "BLOCKED"
    if ready_to_execute:
        return "READY_FOR_EXECUTOR"
    return "PREVIEW_ONLY"


def result_summary(execution_status: str, requested_action: str | None, planned_count: int, blocked_count: int) -> str:
    action = requested_action or "UNKNOWN"
    if execution_status == "READY_FOR_EXECUTOR":
        return f"No-op executor recorded {planned_count} planned actions for {action}; execution remains delegated to a future controlled executor."
    if execution_status == "BLOCKED":
        return f"No-op executor recorded {planned_count} planned actions for {action}, but {blocked_count} actions remain blocked and nothing was executed."
    if execution_status == "PREVIEW_ONLY":
        return f"No-op executor captured {planned_count} preview-only actions for {action} and emitted execution evidence without mutating any target."
    return "No execution result could be produced because the execution preview input is missing."


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
decision_refs = as_dict(evidence.get("decisionRefs"))
environment = as_dict(evidence.get("environment"))

execution_request_path = resolve_ref(artifacts.get("executionRequest"), input_path)
execution_request = load_json(execution_request_path)
execution_request_body = as_dict(execution_request.get("request"))

execution_eligibility_path = resolve_ref(artifacts.get("executionEligibility"), input_path)
execution_eligibility = load_json(execution_eligibility_path)
eligibility_release = as_dict(execution_eligibility.get("release"))
eligibility_decision = as_dict(execution_eligibility.get("decision"))

execution_preview_path = resolve_ref(artifacts.get("executionPreview"), input_path)
execution_preview = load_json(execution_preview_path)
execution_preview_body = as_dict(execution_preview.get("preview"))
execution_preview_guardrails = as_dict(execution_preview.get("guardrails"))

release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    eligibility_release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)
service = first_not_none(evidence.get("service"), eligibility_release.get("service"))
env = first_not_none(evidence.get("env"), eligibility_release.get("env"), environment.get("env"))
namespace = first_not_none(evidence.get("namespace"), eligibility_release.get("namespace"), environment.get("namespace"))
policy_decision = first_not_none(evidence.get("policyDecision"), eligibility_release.get("policyDecision"))
final_action = first_not_none(evidence.get("finalAction"), eligibility_release.get("finalAction"))
requested_action = nullable_string(first_not_none(
    execution_preview_body.get("requestedAction"),
    execution_request_body.get("requestedAction"),
    decision_refs.get("executionPreview", {}).get("requestedAction") if isinstance(decision_refs.get("executionPreview"), dict) else None,
    evidence.get("requestedAction"),
    final_action,
))

planned_actions = []
for item in as_list(execution_preview_body.get("plannedActions")):
    if not isinstance(item, dict):
        continue
    planned_actions.append({
        "actionId": item.get("actionId"),
        "title": item.get("title"),
        "category": item.get("category"),
        "dryRunOnly": True,
        "outcome": "preview_recorded",
        "blocked": bool(item.get("blocked")),
        "requiresApproval": bool(item.get("requiresApproval")),
        "source": item.get("source"),
    })

blocked_actions = []
for item in as_list(execution_preview_body.get("blockedActions")):
    if not isinstance(item, dict):
        continue
    blocked_actions.append({
        "actionId": item.get("actionId"),
        "reason": item.get("reason"),
        "commandPreview": item.get("commandPreview"),
    })

preview_status = nullable_string(execution_preview_body.get("previewStatus"))
ready_to_execute = bool(execution_preview_body.get("readyToExecute"))
has_preview = bool(execution_preview)
execution_status = result_status(preview_status, ready_to_execute, has_preview)

result = {
    "schemaVersion": "execution.result/v1alpha1",
    "executionResultId": f"xr-{release_id}",
    "generatedBy": "build-execution-result.sh",
    "generatedAt": now(),
    "mode": "noop_executor_result",
    "executor": {
        "adapter": "noop-executor",
        "adapterType": "local-noop",
        "dryRunOnly": True,
        "readOnly": True,
        "willExecute": False,
        "mutatesGitOps": False,
        "mutatesKubernetes": False,
        "emitsExecutionEvidence": True,
    },
    "release": {
        "releaseId": release_id,
        "service": service,
        "env": env,
        "namespace": namespace,
        "policyDecision": policy_decision,
        "finalAction": final_action,
    },
    "inputs": {
        "releaseEvidence": str(input_path),
        "executionRequest": str(execution_request_path) if execution_request_path else None,
        "executionEligibility": str(execution_eligibility_path) if execution_eligibility_path else None,
        "executionPreview": str(execution_preview_path) if execution_preview_path else None,
    },
    "result": {
        "executionStatus": execution_status,
        "readyForExecution": ready_to_execute,
        "requestedAction": requested_action,
        "summary": result_summary(execution_status, requested_action, len(planned_actions), len(blocked_actions)),
        "executedActions": planned_actions,
        "blockedActions": blocked_actions,
        "evidenceArtifacts": {
            "executionLog": None,
            "sourceExecutionPreview": str(execution_preview_path) if execution_preview_path else None,
        },
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
        "derivedFromExecutionPreview": execution_preview_guardrails if execution_preview_guardrails else {},
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["executionResult"] = str(output_json)
evidence["executionResultId"] = result["executionResultId"]
evidence["executionResultRef"] = {
    "json": str(output_json),
    "executionStatus": result["result"]["executionStatus"],
    "readyForExecution": result["result"]["readyForExecution"],
    "executedActionCount": len(planned_actions),
}

decision_refs["executionResult"] = {
    "executionResultId": result["executionResultId"],
    "executionStatus": result["result"]["executionStatus"],
    "readyForExecution": result["result"]["readyForExecution"],
    "requestedAction": requested_action,
    "executedActionCount": len(planned_actions),
    "blockedActionCount": len(blocked_actions),
    "executorAdapter": result["executor"]["adapter"],
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Execution result generated: {output_json}")
print(f"Latest execution result: {latest_json}")
print(f"Execution result linked into release evidence: {input_path}")
print(json.dumps({
    "executionResultId": result["executionResultId"],
    "releaseId": release_id,
    "executionStatus": result["result"]["executionStatus"],
    "readyForExecution": result["result"]["readyForExecution"],
    "executedActionCount": len(planned_actions),
    "blockedActionCount": len(blocked_actions),
}, ensure_ascii=False, indent=2))
PY_EXEC_RESULT

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
