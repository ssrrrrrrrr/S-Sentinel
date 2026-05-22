#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
OUTPUT_DIR="${AGENT_TRACE_OUTPUT_DIR:-$REPORT_DIR}"
OUTPUT_FILE="${AGENT_TRACE_OUTPUT_FILE:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-agent-trace.sh [latest|AI_DECISION_JSON]

Environment:
  RELEASE_REPORT_DIR          Optional report directory.
  AGENT_TRACE_OUTPUT_DIR      Optional output directory.
  AGENT_TRACE_OUTPUT_FILE     Optional exact output file.

Behavior:
  - Reads ai-decision-*.json as the trace anchor.
  - Optionally links policy-decision, policy-runtime-result, signed-release-gate, and release-evidence files with the same release suffix.
  - Generates agent-trace-*.json and agent-trace-latest.json.
  - Read-only only: does not modify Kubernetes, GitOps, images, commits, or pushes.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

INPUT="${1:-latest}"

if [ "$INPUT" = "latest" ]; then
  INPUT="$(ls -t "$REPORT_DIR"/ai-decision-*.json 2>/dev/null | head -1 || true)"
elif [ -f "$INPUT" ]; then
  INPUT="$INPUT"
elif [ -f "$REPORT_DIR/$INPUT" ]; then
  INPUT="$REPORT_DIR/$INPUT"
fi

if [ -z "$INPUT" ]; then
  echo "ERROR: no ai-decision-*.json found under $REPORT_DIR" >&2
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "ERROR: input file does not exist: $INPUT" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

python3 - "$INPUT" "$REPORT_DIR" "$OUTPUT_DIR" "$OUTPUT_FILE" <<'PY'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ai_path = Path(sys.argv[1])
report_dir = Path(sys.argv[2])
output_dir = Path(sys.argv[3])
output_file = Path(sys.argv[4]) if sys.argv[4] else None

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_json(path: Path | None) -> dict[str, Any]:
    if path is None or not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}

def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def first_non_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None

def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}

def path_str(path: Path | None) -> str | None:
    return str(path) if path is not None and path.exists() else None

def suffix_from_ai(path: Path) -> tuple[str, str]:
    name = path.name
    if name.startswith("ai-decision-") and name.endswith(".json"):
        suffix = name[len("ai-decision-"):]
        return suffix, suffix[:-len(".json")]
    return name, path.stem

def find_related(prefix: str, suffix: str, release_id: str) -> Path | None:
    candidates = [
        report_dir / f"{prefix}{suffix}",
        report_dir / f"{prefix}{release_id}.json",
        ai_path.parent / f"{prefix}{suffix}",
        ai_path.parent / f"{prefix}{release_id}.json",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None

def add_tool_trace(items: list[dict[str, Any]], name: str, tool: str, input_ref: str | None, output_ref: str | None, summary: dict[str, Any] | None = None) -> None:
    if not input_ref and not output_ref:
        return
    items.append({
        "name": name,
        "tool": tool,
        "status": "AVAILABLE",
        "inputRef": input_ref,
        "outputRef": output_ref,
        "summary": summary or {},
        "readOnly": True,
        "willExecute": False,
    })

ai = load_json(ai_path)
suffix, file_release_id = suffix_from_ai(ai_path)

evidence = as_dict(ai.get("evidence"))
release_id = str(first_non_empty(ai.get("releaseId"), evidence.get("releaseId"), file_release_id))

policy_path = find_related("policy-decision-", suffix, release_id)
policy_runtime_path = find_related("policy-runtime-result-", suffix, release_id)
signed_gate_path = find_related("signed-release-gate-", suffix, release_id)
release_evidence_path = find_related("release-evidence-", suffix, release_id)

policy = load_json(policy_path)
policy_runtime = load_json(policy_runtime_path)
signed_gate = load_json(signed_gate_path)
release_evidence = load_json(release_evidence_path)

signed_gate_decision = as_dict(signed_gate.get("decision"))
signed_gate_risk = as_dict(signed_gate.get("risk"))
policy_summary = as_dict(policy_runtime.get("summary"))
runtime = as_dict(policy_runtime.get("runtime"))

agent_trace_id = f"at-{release_id}"
trace_id = str(first_non_empty(
    ai.get("traceId"),
    policy.get("traceId"),
    policy_runtime.get("traceId"),
    signed_gate.get("traceId"),
    release_evidence.get("traceId"),
    f"trace-{release_id}",
))

agent_run_id = str(first_non_empty(ai.get("agentRunId"), f"ar-{release_id}"))
policy_decision_id = first_non_empty(policy.get("policyDecisionId"), f"pd-{release_id}" if policy else None)
policy_runtime_result_id = f"prr-{release_id}" if policy_runtime else None
signed_release_gate_id = first_non_empty(signed_gate.get("signedReleaseGateId"), f"srg-{release_id}" if signed_gate else None)

release = {
    "releaseId": release_id,
    "service": first_non_empty(ai.get("service"), evidence.get("service"), release_evidence.get("service"), as_dict(signed_gate.get("release")).get("service")),
    "env": first_non_empty(ai.get("env"), evidence.get("env"), release_evidence.get("env"), as_dict(signed_gate.get("release")).get("env")),
    "namespace": first_non_empty(as_dict(ai.get("rollout")).get("namespace"), release_evidence.get("namespace"), as_dict(signed_gate.get("release")).get("namespace")),
    "version": first_non_empty(ai.get("version"), evidence.get("version"), release_evidence.get("version"), as_dict(signed_gate.get("release")).get("version")),
    "commit": first_non_empty(ai.get("commit"), evidence.get("commit"), release_evidence.get("commit"), as_dict(signed_gate.get("release")).get("commit")),
    "image": first_non_empty(ai.get("image"), evidence.get("image"), release_evidence.get("image"), as_dict(signed_gate.get("image")).get("image")),
    "imageDigest": first_non_empty(ai.get("imageDigest"), evidence.get("imageDigest"), release_evidence.get("imageDigest"), as_dict(signed_gate.get("image")).get("imageDigest")),
}

tool_traces: list[dict[str, Any]] = []
add_tool_trace(
    tool_traces,
    "ai_release_advisor",
    "ai-release-advisor.sh",
    path_str(as_dict(ai.get("sources")).get("releaseContext") and Path(str(as_dict(ai.get("sources")).get("releaseContext")))),
    str(ai_path),
    {
        "releaseResult": ai.get("releaseResult"),
        "recommendedAction": ai.get("recommendedAction"),
        "requiresHumanApproval": ai.get("requiresHumanApproval"),
    },
)
add_tool_trace(
    tool_traces,
    "policy_runtime_adapter",
    "policy-runtime-adapter.py",
    path_str(policy_runtime_path),
    path_str(policy_runtime_path),
    {
        "runtime": runtime.get("name"),
        "policyDecision": policy_summary.get("policyDecision"),
    },
)
add_tool_trace(
    tool_traces,
    "policy_guard",
    "evaluate-agent-decision.sh",
    path_str(ai_path),
    path_str(policy_path),
    {
        "policyDecision": policy.get("policyDecision"),
        "finalAction": policy.get("finalAction"),
        "matchedRules": policy.get("matchedRules") or [],
    },
)
add_tool_trace(
    tool_traces,
    "signed_release_gate",
    "build-signed-release-gate.sh",
    path_str(find_related("supply-chain-decision-", suffix, release_id)),
    path_str(signed_gate_path),
    {
        "decision": signed_gate_decision.get("decision"),
        "allowed": signed_gate_decision.get("allowed"),
        "requiresHumanApproval": signed_gate_decision.get("requiresHumanApproval"),
    },
)
add_tool_trace(
    tool_traces,
    "release_evidence",
    "build-release-evidence.sh",
    path_str(policy_path),
    path_str(release_evidence_path),
    {
        "releaseResult": release_evidence.get("releaseResult"),
        "policyDecision": release_evidence.get("policyDecision"),
    },
)

trace = {
    "schemaVersion": "agent.trace/v1alpha1",
    "agentTraceId": agent_trace_id,
    "traceId": trace_id,
    "releaseId": release_id,
    "generatedBy": "build-agent-trace.sh",
    "generatedAt": now(),
    "release": release,
    "correlation": {
        "releaseId": release_id,
        "agentRunId": agent_run_id,
        "policyDecisionId": policy_decision_id,
        "policyRuntimeResultId": policy_runtime_result_id,
        "signedReleaseGateId": signed_release_gate_id,
    },
    "agentRun": {
        "agentRunId": agent_run_id,
        "agent": "ai-release-advisor",
        "decisionRef": str(ai_path),
        "releaseResult": ai.get("releaseResult"),
        "recommendedAction": ai.get("recommendedAction"),
        "requiresHumanApproval": ai.get("requiresHumanApproval"),
        "status": "COMPLETED",
    },
    "policyTrace": {
        "policyDecisionId": policy_decision_id,
        "policyRuntimeResultId": policy_runtime_result_id,
        "runtime": runtime,
        "policyDecision": first_non_empty(policy.get("policyDecision"), policy_summary.get("policyDecision")),
        "finalAction": first_non_empty(policy.get("finalAction"), policy_summary.get("finalAction")),
        "allowed": first_non_empty(policy.get("allowed"), policy_summary.get("allowed")),
        "requiresHumanApproval": first_non_empty(policy.get("requiresHumanApproval"), policy_summary.get("requiresHumanApproval")),
        "matchedRules": first_non_empty(policy.get("matchedRules"), policy_summary.get("matchedRules"), []),
        "source": {
            "policyDecision": path_str(policy_path),
            "policyRuntimeResult": path_str(policy_runtime_path),
        },
    },
    "signedReleaseGateTrace": {
        "signedReleaseGateId": signed_release_gate_id,
        "decision": signed_gate_decision.get("decision"),
        "allowed": signed_gate_decision.get("allowed"),
        "requiresHumanApproval": signed_gate_decision.get("requiresHumanApproval"),
        "riskLevel": signed_gate_risk.get("riskLevel"),
        "riskScore": signed_gate_risk.get("riskScore"),
        "source": path_str(signed_gate_path),
    },
    "toolCallTraces": tool_traces,
    "evidenceTrace": {
        "releaseEvidence": path_str(release_evidence_path),
        "aiDecision": str(ai_path),
        "policyDecision": path_str(policy_path),
        "policyRuntimeResult": path_str(policy_runtime_path),
        "signedReleaseGate": path_str(signed_gate_path),
        "availableObjectTypes": [
            item["name"] for item in tool_traces
        ],
    },
    "guardrails": {
        "readOnly": True,
        "willExecute": False,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotBuildImages": True,
        "doesNotPushImages": True,
        "doesNotCommitOrPush": True,
    },
}

if output_file is None:
    output_file = output_dir / f"agent-trace-{release_id}.json"

write_json(output_file, trace)
latest = output_dir / "agent-trace-latest.json"
write_json(latest, trace)

print(json.dumps({
    "schemaVersion": "agent.trace.build/v1alpha1",
    "agentTrace": str(output_file),
    "latest": str(latest),
    "traceId": trace_id,
    "agentTraceId": agent_trace_id,
    "releaseId": release_id,
    "policyDecision": trace["policyTrace"]["policyDecision"],
    "signedReleaseGateDecision": trace["signedReleaseGateTrace"]["decision"],
}, ensure_ascii=False, indent=2))
PY
