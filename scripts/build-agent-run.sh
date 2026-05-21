#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-}"
RELEASE_EVIDENCE_FILE="${1:-latest}"
EVIDENCE_RECORD_FILE="${2:-}"
RELEASE_INTELLIGENCE_FILE="${3:-}"

if [ -z "$REPORT_DIR" ]; then
  if [ -d "/data/nfs/slo-rollout-watcher/reports" ]; then
    REPORT_DIR="/data/nfs/slo-rollout-watcher/reports"
  else
    REPORT_DIR="docs/release-reports"
  fi
fi

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-agent-run.sh [latest|RELEASE_EVIDENCE_JSON] [EVIDENCE_RECORD_JSON] [RELEASE_INTELLIGENCE_JSON]

Environment:
  RELEASE_REPORT_DIR       Optional report directory.
  AGENT_RUN_OUTPUT_DIR     Optional output directory. Defaults to release evidence directory.
  RELEASE_MEMORY_FILE      Optional release memory jsonl path.

Behavior:
  - Reads release evidence, optional evidence record, and optional release intelligence.
  - Generates agent-run-*.json and agent-run-latest.json.
  - Records a read-only Agent Run.
  - Does not modify Kubernetes, GitOps, Rollouts, Deployments, images, commits, or pushes.
USAGE
}

if [ "${RELEASE_EVIDENCE_FILE:-}" = "-h" ] || [ "${RELEASE_EVIDENCE_FILE:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 3 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ "$RELEASE_EVIDENCE_FILE" = "latest" ] || [ -z "$RELEASE_EVIDENCE_FILE" ]; then
  RELEASE_EVIDENCE_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | grep -v 'release-evidence-latest.json' | head -1 || true)"
fi

if [ -z "$RELEASE_EVIDENCE_FILE" ] || [ ! -f "$RELEASE_EVIDENCE_FILE" ]; then
  echo "ERROR: release evidence file does not exist: ${RELEASE_EVIDENCE_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$RELEASE_EVIDENCE_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

if [ -z "$EVIDENCE_RECORD_FILE" ]; then
  candidate="$REPORT_DIR/evidence-record-$SUFFIX"
  if [ -f "$candidate" ]; then
    EVIDENCE_RECORD_FILE="$candidate"
  fi
fi

if [ -n "$EVIDENCE_RECORD_FILE" ] && [ ! -f "$EVIDENCE_RECORD_FILE" ]; then
  echo "WARN: evidence record file not found, continuing without it: $EVIDENCE_RECORD_FILE" >&2
  EVIDENCE_RECORD_FILE=""
fi

if [ -z "$RELEASE_INTELLIGENCE_FILE" ]; then
  candidate="$REPORT_DIR/release-intelligence-$SUFFIX"
  if [ -f "$candidate" ]; then
    RELEASE_INTELLIGENCE_FILE="$candidate"
  fi
fi

if [ -n "$RELEASE_INTELLIGENCE_FILE" ] && [ ! -f "$RELEASE_INTELLIGENCE_FILE" ]; then
  echo "WARN: release intelligence file not found, continuing without it: $RELEASE_INTELLIGENCE_FILE" >&2
  RELEASE_INTELLIGENCE_FILE=""
fi

OUTPUT_DIR="${AGENT_RUN_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="$OUTPUT_DIR/agent-run-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/agent-run-latest.json"
MEMORY_FILE="${RELEASE_MEMORY_FILE:-$REPORT_DIR/release-memory.jsonl}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

python3 - "$RELEASE_EVIDENCE_FILE" "${EVIDENCE_RECORD_FILE:-}" "${RELEASE_INTELLIGENCE_FILE:-}" "$MEMORY_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

evidence_path = Path(sys.argv[1])
record_path = Path(sys.argv[2]) if sys.argv[2] else None
intelligence_path = Path(sys.argv[3]) if sys.argv[3] else None
memory_path = Path(sys.argv[4]) if sys.argv[4] else None
output_json = Path(sys.argv[5])
latest_json = Path(sys.argv[6])

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_json(path: Path | None) -> dict[str, Any]:
    if not path:
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

def release_id_from_path(path: Path) -> str:
    base = path.name
    if base.startswith("release-evidence-") and base.endswith(".json"):
        return base[len("release-evidence-"):-len(".json")]
    return path.stem

def first_not_none(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None

def compact_path(path: Path | None) -> str | None:
    return str(path) if path else None

def derive_priority(release_result: str, risk_level: str | None, risk_score: Any) -> str:
    if release_result == "PASS":
        return "none"
    if risk_level in ("critical", "high"):
        return str(risk_level)
    try:
        score = float(risk_score)
    except Exception:
        score = 0
    if score >= 90:
        return "critical"
    if score >= 70:
        return "high"
    if score >= 40:
        return "medium"
    return "low"

def derive_steps(release_result: str, failed_metrics: list[Any], recommended_action: str) -> list[str]:
    if release_result == "PASS":
        return ["archive_release_record", "continue_observing"]

    if release_result == "FAIL_BY_REQUEST_COUNT":
        return [
            "increase_canary_traffic_or_wait_for_more_samples",
            "rerun_slo_analysis",
            "avoid_treating_insufficient_traffic_as_code_failure"
        ]

    if str(release_result).startswith("FAIL"):
        steps = [
            "stop_promotion",
            "inspect_canary_logs",
            "compare_change_context",
            "review_policy_decision",
            "review_similar_historical_failures"
        ]
        if "error-rate" in failed_metrics:
            steps.append("inspect_5xx_error_logs")
        if "p95-latency" in failed_metrics:
            steps.append("inspect_tail_latency_and_slow_paths")
        return steps

    if recommended_action in ("INVESTIGATE", "MANUAL_REVIEW"):
        return ["continue_observing", "collect_more_evidence", "manual_review"]

    return ["continue_observing"]

def derive_conclusion(release_result: str, failed_metrics: list[Any], recommended_action: str) -> str:
    if release_result == "PASS":
        return "Release passed all available SLO and policy checks. The read-only agent recommends archiving the record and continuing observation."

    if release_result == "FAIL_BY_REQUEST_COUNT":
        return "Release has insufficient request volume. The read-only agent recommends collecting more traffic before making a stronger quality judgment."

    if release_result == "FAIL_BY_MULTIPLE_SLO":
        return "Release failed multiple SLO gates. The read-only agent recommends stopping promotion and requiring human review."

    if release_result == "FAIL_BY_ERROR_RATE":
        return "Release failed the error-rate SLO gate. The read-only agent recommends stopping promotion and inspecting canary errors."

    if release_result == "FAIL_BY_P95_LATENCY":
        return "Release failed the p95-latency SLO gate. The read-only agent recommends stopping promotion and inspecting tail latency."

    if str(release_result).startswith("FAIL"):
        return f"Release result is {release_result}. The read-only agent recommends {recommended_action} with human review."

    return "Release signal is incomplete or unknown. The read-only agent recommends continued observation and manual review."

evidence = load_json(evidence_path)
record = load_json(record_path)
intelligence = load_json(intelligence_path)

summary = as_dict(evidence.get("summary"))
artifacts = as_dict(evidence.get("artifacts"))
decision_refs = as_dict(evidence.get("decisionRefs"))
policy_ref = as_dict(decision_refs.get("policyDecision"))
ai_ref = as_dict(decision_refs.get("aiDecision"))

release_id = first_not_none(
    evidence.get("releaseId"),
    record.get("releaseId"),
    release_id_from_path(evidence_path)
)

release_result = str(evidence.get("releaseResult") or record.get("releaseResult") or "UNKNOWN")
policy_decision = str(evidence.get("policyDecision") or record.get("policyDecision") or "UNKNOWN")
final_action = str(evidence.get("finalAction") or "UNKNOWN")
requested_action = evidence.get("requestedAction") or policy_ref.get("requestedAction")
failed_metrics = as_list(summary.get("failedMetrics"))

risk_level = summary.get("riskLevel")
risk_score = summary.get("riskScore")
recommended_action = (
    intelligence.get("recommendedNextAction")
    or final_action
    or requested_action
    or "MANUAL_REVIEW"
)

conclusion = intelligence.get("conclusion") or derive_conclusion(release_result, failed_metrics, str(recommended_action))
priority = derive_priority(release_result, nullable_string(risk_level), risk_score)

observations: list[str] = [
    f"releaseResult={release_result}",
    f"policyDecision={policy_decision}",
    f"finalAction={final_action}",
    f"executionMode={evidence.get('executionMode')}",
]

if failed_metrics:
    observations.append("failedMetrics=" + ",".join(str(item) for item in failed_metrics))
if intelligence.get("riskPattern"):
    observations.append(f"riskPattern={intelligence.get('riskPattern')}")
if intelligence.get("repeatedRiskPattern") is True:
    observations.append("repeatedRiskPattern=true")

agent_run_id = "ar-" + str(release_id)

agent_run = {
    "schemaVersion": "agent.run/v1alpha1",
    "agentRunId": agent_run_id,
    "generatedBy": "build-agent-run.sh",
    "generatedAt": now(),
    "mode": "read_only",
    "release": {
        "releaseId": str(release_id),
        "service": first_not_none(evidence.get("service"), record.get("service")),
        "env": first_not_none(evidence.get("env"), record.get("env")),
        "namespace": record.get("namespace"),
        "version": record.get("version") or record.get("appVersion"),
        "commit": record.get("commit"),
        "imageDigest": record.get("imageDigest"),
        "releaseResult": release_result,
    },
    "inputs": {
        "releaseEvidence": str(evidence_path),
        "evidenceRecord": compact_path(record_path),
        "releaseIntelligence": compact_path(intelligence_path),
        "releaseMemory": str(memory_path) if memory_path and memory_path.exists() else None,
        "artifacts": artifacts,
    },
    "observation": {
        "releaseResult": release_result,
        "rolloutPhase": summary.get("rolloutPhase"),
        "rolloutAbort": summary.get("rolloutAbort"),
        "analysisRunPhase": summary.get("analysisRunPhase"),
        "riskLevel": risk_level,
        "riskScore": risk_score,
        "failedMetrics": failed_metrics,
        "sloId": first_not_none(evidence.get("sloId"), record.get("sloId")),
        "strategyId": first_not_none(evidence.get("strategyId"), record.get("strategyId")),
    },
    "policy": {
        "policyDecisionId": evidence.get("policyDecisionId") or policy_ref.get("policyDecisionId"),
        "policyDecision": policy_decision,
        "requestedAction": requested_action,
        "allowed": evidence.get("allowed") if "allowed" in evidence else policy_ref.get("allowed"),
        "finalAction": final_action,
        "executionMode": str(evidence.get("executionMode") or "unknown"),
        "requiresHumanApproval": bool(evidence.get("requiresHumanApproval", False)),
        "deniedReasons": as_list(evidence.get("deniedReasons") or policy_ref.get("deniedReasons")),
        "approvalRequiredReasons": as_list(evidence.get("approvalRequiredReasons") or policy_ref.get("approvalRequiredReasons")),
        "matchedRules": as_list(summary.get("matchedPolicyRules") or policy_ref.get("matchedRules")),
        "strategyPolicy": as_dict(evidence.get("strategyPolicy") or policy_ref.get("strategyPolicy")),
        "safety": as_dict(evidence.get("policySafety") or policy_ref.get("safety")),
    },
    "reasoning": {
        "riskPattern": intelligence.get("riskPattern"),
        "repeatedRiskPattern": intelligence.get("repeatedRiskPattern"),
        "similarFailureCount": intelligence.get("similarFailureCount"),
        "similarFailureIncludingCurrentCount": intelligence.get("similarFailureIncludingCurrentCount"),
        "conclusion": conclusion,
        "observations": observations,
        "aiDecision": {
            "decisionSource": ai_ref.get("decisionSource"),
            "confidence": ai_ref.get("confidence"),
            "agentAction": as_dict(ai_ref.get("agentAction")),
            "policyHints": as_list(ai_ref.get("policyHints")),
            "nextSteps": as_list(ai_ref.get("nextSteps")),
        },
    },
    "recommendation": {
        "recommendedAction": str(recommended_action or "MANUAL_REVIEW"),
        "priority": priority,
        "humanNextSteps": derive_steps(release_result, failed_metrics, str(recommended_action)),
        "willExecute": False,
    },
    "evidenceLinks": {
        "releaseEvidence": str(evidence_path),
        "evidenceRecord": compact_path(record_path),
        "releaseIntelligence": compact_path(intelligence_path),
        "aiDecision": artifacts.get("aiDecision"),
        "policyDecision": artifacts.get("policyDecision"),
        "releaseSummary": artifacts.get("releaseSummary"),
        "actionPlan": artifacts.get("actionPlan"),
        "failureEvidence": artifacts.get("failureEvidence"),
        "approvalRecord": artifacts.get("approvalRecord") or artifacts.get("approval"),
        "timeline": artifacts.get("releaseTimeline") or artifacts.get("timeline"),
        "runbook": artifacts.get("runbook"),
        "rca": artifacts.get("rca"),
    },
    "guardrails": {
        "readOnly": True,
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
output_json.write_text(json.dumps(agent_run, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Agent run generated: {output_json}")
print(f"Latest agent run: {latest_json}")
print(json.dumps({
    "agentRunId": agent_run["agentRunId"],
    "releaseId": agent_run["release"]["releaseId"],
    "releaseResult": agent_run["release"]["releaseResult"],
    "policyDecision": agent_run["policy"]["policyDecision"],
    "recommendedAction": agent_run["recommendation"]["recommendedAction"],
    "mode": agent_run["mode"],
    "willExecute": agent_run["guardrails"]["willExecute"],
}, ensure_ascii=False, indent=2))
PY

validate_generated_release_contract "$OUTPUT_JSON"

python3 - "$RELEASE_EVIDENCE_FILE" "$OUTPUT_JSON" <<'PY_AGENT_LINK'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
agent_run_path = Path(sys.argv[2])

evidence = json.loads(evidence_path.read_text(encoding="utf-8-sig"))
agent_run = json.loads(agent_run_path.read_text(encoding="utf-8-sig"))

artifacts = evidence.setdefault("artifacts", {})
artifacts["agentRun"] = str(agent_run_path)

evidence["agentRunId"] = agent_run.get("agentRunId")

decision_refs = evidence.setdefault("decisionRefs", {})
decision_refs["agentRun"] = {
    "agentRunId": agent_run.get("agentRunId"),
    "mode": agent_run.get("mode"),
    "recommendedAction": (agent_run.get("recommendation") or {}).get("recommendedAction"),
    "priority": (agent_run.get("recommendation") or {}).get("priority"),
    "willExecute": (agent_run.get("recommendation") or {}).get("willExecute"),
    "guardrails": agent_run.get("guardrails") or {},
}

evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Agent run linked into release evidence: {evidence_path}")
PY_AGENT_LINK

validate_generated_release_contract "$RELEASE_EVIDENCE_FILE"

cat "$OUTPUT_JSON"
