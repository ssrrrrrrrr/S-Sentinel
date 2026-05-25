#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-gitops-adapter-run.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR               Optional report directory.
  GITOPS_ADAPTER_RUN_OUTPUT_DIR    Optional output directory.
  GITOPS_ADAPTER_RUN_OUTPUT_FILE   Optional exact output file.

Behavior:
  - Reads release evidence, adapter delivery, adapter result, and adapter request.
  - Generates gitops-adapter-run-*.json and gitops-adapter-run-latest.json.
  - Emits a local-only handoff readiness receipt; it never commits, pushes, creates PRs, mutates GitOps, or modifies Kubernetes.
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

OUTPUT_DIR="${GITOPS_ADAPTER_RUN_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${GITOPS_ADAPTER_RUN_OUTPUT_FILE:-$OUTPUT_DIR/gitops-adapter-run-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/gitops-adapter-run-latest.json"

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

"$PYTHON_BIN" - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_GITOPS_ADAPTER_RUN'
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


def run_status_from(delivery_status: str | None, checks_ok: bool) -> str:
    if delivery_status == "WORKSPACE_READY" and checks_ok:
        return "HANDOFF_READY"
    if delivery_status in {"BLOCKED", "WAITING_APPROVAL", "NO_ACTION_REQUIRED", "NEEDS_MORE_EVIDENCE"}:
        return delivery_status
    if delivery_status == "WORKSPACE_READY" and not checks_ok:
        return "FAILED"
    return "FAILED"


evidence = load_json(input_path)
artifacts = as_dict(evidence.get("artifacts"))
environment = as_dict(evidence.get("environment"))

delivery_path = resolve_ref(artifacts.get("gitopsAdapterDelivery"), input_path)
delivery = load_json(delivery_path)
delivery_meta = as_dict(delivery.get("delivery"))

result_path = resolve_ref(artifacts.get("gitopsAdapterResult"), input_path)
result = load_json(result_path)
result_delivery = as_dict(result.get("delivery"))

request_path = resolve_ref(artifacts.get("gitopsAdapterRequest"), input_path)
request = load_json(request_path)
request_body = as_dict(request.get("request"))

release = as_dict(delivery.get("release"))
release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release.get("releaseId"),
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

workspace_dir = resolve_ref(delivery_meta.get("workspaceDir"), input_path)
manifest_file = resolve_ref(delivery_meta.get("manifestFile"), input_path)
instructions_file = resolve_ref(delivery_meta.get("pickupInstructionsFile"), input_path)
workspace_files = []
checks = []

for item in as_list(delivery_meta.get("copiedFiles")):
    if not isinstance(item, dict):
        continue
    workspace_path = resolve_ref(item.get("workspacePath"), input_path)
    exists = bool(workspace_path and workspace_path.exists() and workspace_path.is_file())
    workspace_files.append({
        "fileId": item.get("fileId"),
        "workspacePath": str(workspace_path) if workspace_path else item.get("workspacePath"),
        "exists": exists,
        "contentType": item.get("contentType"),
        "description": item.get("description"),
    })

checks.extend([
    {
        "checkId": "workspace_dir_exists",
        "title": "Workspace directory exists",
        "status": "PASS" if workspace_dir and workspace_dir.exists() else "FAIL",
    },
    {
        "checkId": "manifest_exists",
        "title": "Delivery manifest exists",
        "status": "PASS" if manifest_file and manifest_file.exists() else "FAIL",
    },
    {
        "checkId": "pickup_instructions_exist",
        "title": "Pickup instructions exist",
        "status": "PASS" if instructions_file and instructions_file.exists() else "FAIL",
    },
    {
        "checkId": "workspace_files_present",
        "title": "Workspace files are materialized",
        "status": "PASS" if workspace_files and all(item["exists"] for item in workspace_files) else "FAIL",
    },
])

checks_ok = all(item["status"] == "PASS" for item in checks)
run_status = run_status_from(nullable_string(delivery_meta.get("deliveryStatus")), checks_ok)

receipt_path = workspace_dir / "adapter-run-receipt.json" if workspace_dir else output_json.parent / f"adapter-run-receipt-{release_id}.json"
summary_path = workspace_dir / "adapter-run-summary.md" if workspace_dir else output_json.parent / f"adapter-run-summary-{release_id}.md"
receipt_path.parent.mkdir(parents=True, exist_ok=True)

receipt = {
    "schemaVersion": "gitops.adapter.run.receipt/v1alpha1",
    "gitopsAdapterRunId": f"grun-{release_id}",
    "generatedAt": now(),
    "runStatus": run_status,
    "workspaceDir": str(workspace_dir) if workspace_dir else None,
    "checks": checks,
    "localOnly": True,
}
receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
summary_path.write_text(
    "# GitOps Adapter Run\n\n"
    + f"- runStatus: {run_status}\n"
    + f"- branchName: {first_not_none(delivery_meta.get('branchName'), result_delivery.get('receipt', {}).get('branchName') if isinstance(result_delivery.get('receipt'), dict) else None)}\n"
    + f"- workspaceDir: {str(workspace_dir) if workspace_dir else 'none'}\n"
    + f"- checkCount: {len(checks)}\n",
    encoding="utf-8",
)

warnings = [str(item) for item in as_list(delivery_meta.get("warnings"))]
if not checks_ok:
    warnings.append("one or more adapter run checks failed")

run = {
    "schemaVersion": "gitops.adapter.run/v1alpha1",
    "gitopsAdapterRunId": f"grun-{release_id}",
    "generatedBy": "build-gitops-adapter-run.sh",
    "generatedAt": now(),
    "mode": "local_gitops_adapter_run",
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
        "gitopsAdapterDelivery": str(delivery_path) if delivery_path else None,
        "gitopsAdapterResult": str(result_path) if result_path else None,
        "gitopsAdapterRequest": str(request_path) if request_path else None,
    },
    "adapter": {
        "adapter": "gitops-handoff-local",
        "adapterType": "gitops-handoff-local",
        "runMode": "local_handoff_readiness",
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotCallExternalGitProvider": True,
        "emitsRunReceipt": True,
    },
    "run": {
        "runStatus": run_status,
        "workspaceDir": str(workspace_dir) if workspace_dir else None,
        "requestedOperation": nullable_string(first_not_none(
            delivery_meta.get("requestedOperation"),
            result_delivery.get("requestedOperation"),
            request_body.get("requestedOperation"),
        )),
        "branchName": nullable_string(first_not_none(
            delivery_meta.get("branchName"),
            as_dict(result_delivery.get("receipt")).get("branchName"),
            as_dict(request_body.get("delivery")).get("branchName"),
        )),
        "summary": f"Local adapter run validated {len(workspace_files)} workspace files and advanced the handoff state to {run_status}.",
        "checks": checks,
        "pickupReceipt": {
            "path": str(receipt_path),
            "summaryPath": str(summary_path),
            "generatedAt": now(),
            "localOnly": True,
        },
        "workspaceFiles": workspace_files,
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
        "derivedFromGitopsAdapterDelivery": as_dict(delivery.get("guardrails")),
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(run, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

artifacts["gitopsAdapterRun"] = str(output_json)
evidence["gitopsAdapterRunId"] = run["gitopsAdapterRunId"]
evidence["gitopsAdapterRunRef"] = {
    "json": str(output_json),
    "runStatus": run["run"]["runStatus"],
    "workspaceDir": run["run"]["workspaceDir"],
    "checkCount": len(checks),
}

decision_refs = as_dict(evidence.get("decisionRefs"))
decision_refs["gitopsAdapterRun"] = {
    "gitopsAdapterRunId": run["gitopsAdapterRunId"],
    "runStatus": run["run"]["runStatus"],
    "branchName": run["run"]["branchName"],
    "requestedOperation": run["run"]["requestedOperation"],
    "workspaceFileCount": len(workspace_files),
    "source": str(output_json),
}
evidence["decisionRefs"] = decision_refs
evidence["artifacts"] = artifacts

input_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"GitOps adapter run generated: {output_json}")
print(f"Latest GitOps adapter run: {latest_json}")
print(f"GitOps adapter run linked into release evidence: {input_path}")
print(json.dumps({
    "gitopsAdapterRunId": run["gitopsAdapterRunId"],
    "releaseId": release_id,
    "runStatus": run["run"]["runStatus"],
    "workspaceDir": run["run"]["workspaceDir"],
    "workspaceFileCount": len(workspace_files),
}, ensure_ascii=False, indent=2))
PY_GITOPS_ADAPTER_RUN

validate_generated_release_contract "$OUTPUT_JSON"

cat "$OUTPUT_JSON"
