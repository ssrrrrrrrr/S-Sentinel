#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-}"
AGENT_RUN_FILE="${1:-latest}"
RELEASE_EVIDENCE_FILE="${2:-}"
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
  scripts/build-plan-run.sh [latest|AGENT_RUN_JSON] [RELEASE_EVIDENCE_JSON] [RELEASE_INTELLIGENCE_JSON]

Environment:
  RELEASE_REPORT_DIR       Optional report directory.
  PLAN_RUN_OUTPUT_DIR      Optional output directory. Defaults to agent run directory.
  RELEASE_MEMORY_FILE      Optional release memory jsonl path.

Behavior:
  - Reads a read-only agent run.
  - Performs lightweight rule-based RAG over release memory.
  - Generates plan-run-*.json and plan-run-latest.json.
  - Produces a read-only investigation plan.
  - Does not modify Kubernetes, GitOps, Rollouts, Deployments, images, commits, or pushes.
USAGE
}

if [ "${AGENT_RUN_FILE:-}" = "-h" ] || [ "${AGENT_RUN_FILE:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 3 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ "$AGENT_RUN_FILE" = "latest" ] || [ -z "$AGENT_RUN_FILE" ]; then
  AGENT_RUN_FILE="$(ls -t "$REPORT_DIR"/agent-run-*.json 2>/dev/null | grep -v 'agent-run-latest.json' | head -1 || true)"
fi

if [ -z "$AGENT_RUN_FILE" ] || [ ! -f "$AGENT_RUN_FILE" ]; then
  echo "ERROR: agent run file does not exist: ${AGENT_RUN_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$AGENT_RUN_FILE")"
SUFFIX="${BASENAME#agent-run-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

if [ -z "$RELEASE_EVIDENCE_FILE" ]; then
  candidate="$REPORT_DIR/release-evidence-$SUFFIX"
  if [ -f "$candidate" ]; then
    RELEASE_EVIDENCE_FILE="$candidate"
  fi
fi

if [ -n "$RELEASE_EVIDENCE_FILE" ] && [ ! -f "$RELEASE_EVIDENCE_FILE" ]; then
  echo "WARN: release evidence file not found, continuing without it: $RELEASE_EVIDENCE_FILE" >&2
  RELEASE_EVIDENCE_FILE=""
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

OUTPUT_DIR="${PLAN_RUN_OUTPUT_DIR:-$(dirname "$AGENT_RUN_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="$OUTPUT_DIR/plan-run-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/plan-run-latest.json"
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

python3 - "$AGENT_RUN_FILE" "${RELEASE_EVIDENCE_FILE:-}" "${RELEASE_INTELLIGENCE_FILE:-}" "$MEMORY_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_PLAN_RUN'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

agent_run_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2]) if sys.argv[2] else None
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

def load_jsonl(path: Path | None) -> list[dict[str, Any]]:
    if not path or not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            item = json.loads(line)
            if isinstance(item, dict):
                rows.append(item)
        except Exception:
            pass
    return rows

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
        if value is not None:
            return value
    return None

def same_source(left: Any, right: Any) -> bool:
    if not left or not right:
        return False
    lp = Path(str(left))
    rp = Path(str(right))
    if str(lp) == str(rp):
        return True
    if lp.name == rp.name:
        return True
    try:
        if lp.exists() and rp.exists():
            return lp.resolve() == rp.resolve()
    except Exception:
        pass
    return False

def release_id_from_agent_path(path: Path) -> str:
    base = path.name
    if base.startswith("agent-run-") and base.endswith(".json"):
        return base[len("agent-run-"):-len(".json")]
    return path.stem

def score_record(record: dict[str, Any], query: dict[str, Any], current_evidence_path: Path | None) -> tuple[int, list[str]]:
    score = 0
    signals: list[str] = []

    query_metrics = set(query.get("failedMetrics") or [])
    record_metrics = set(record.get("failedMetrics") or [])

    overlap = sorted(query_metrics & record_metrics)
    if overlap:
        score += len(overlap) * 10
        signals.append("failedMetrics_overlap:" + ",".join(overlap))

    if query_metrics and record_metrics and query_metrics == record_metrics:
        score += 20
        signals.append("failedMetrics_exact_match")

    if record.get("releaseResult") == query.get("releaseResult"):
        score += 8
        signals.append("releaseResult_match")

    if record.get("policyDecision") == query.get("policyDecision"):
        score += 5
        signals.append("policyDecision_match")

    if record.get("finalAction") == query.get("recommendedAction"):
        score += 5
        signals.append("action_match")

    if record.get("service") and record.get("service") == query.get("service"):
        score += 3
        signals.append("service_match")

    if record.get("env") and record.get("env") == query.get("env"):
        score += 2
        signals.append("env_match")

    if current_evidence_path and same_source(record.get("sourceReleaseEvidence"), current_evidence_path):
        score = 0
        signals.append("current_evidence_skipped")

    return score, signals

def compact_record(record: dict[str, Any], score: int, signals: list[str]) -> dict[str, Any]:
    artifacts = as_dict(record.get("artifacts"))
    return {
        "kind": "release_memory_record",
        "releaseId": record.get("releaseId"),
        "generatedAt": record.get("generatedAt"),
        "service": record.get("service"),
        "env": record.get("env"),
        "appVersion": record.get("appVersion"),
        "releaseResult": record.get("releaseResult"),
        "policyDecision": record.get("policyDecision"),
        "finalAction": record.get("finalAction"),
        "requiresHumanApproval": record.get("requiresHumanApproval"),
        "failedMetrics": record.get("failedMetrics") or [],
        "riskLevel": record.get("riskLevel"),
        "riskScore": record.get("riskScore"),
        "sourceReleaseEvidence": record.get("sourceReleaseEvidence"),
        "artifacts": {
            "failureEvidence": artifacts.get("failureEvidence"),
            "actionPlan": artifacts.get("actionPlan"),
            "releaseIntelligence": artifacts.get("releaseIntelligence"),
            "agentRun": artifacts.get("agentRun"),
            "runbook": artifacts.get("runbook"),
            "rca": artifacts.get("rca"),
        },
        "similarity": {
            "score": score,
            "matchedSignals": signals,
        },
    }

def build_steps(release_result: str, failed_metrics: list[Any], retrieved_count: int) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = []

    if release_result == "PASS":
        return [
            {
                "stepId": "archive_release_record",
                "title": "Archive release record",
                "purpose": "Record the healthy release and continue passive observation.",
                "executionType": "read_only",
                "willExecute": False,
                "evidenceRefs": ["agentRun", "releaseEvidence"]
            },
            {
                "stepId": "continue_observing",
                "title": "Continue observing service health",
                "purpose": "Keep watching core SLO signals after the release passes.",
                "executionType": "read_only",
                "willExecute": False,
                "evidenceRefs": ["releaseEvidence"]
            }
        ]

    if release_result == "FAIL_BY_REQUEST_COUNT":
        return [
            {
                "stepId": "verify_canary_traffic",
                "title": "Verify canary traffic volume",
                "purpose": "Confirm whether the failure is caused by insufficient request samples.",
                "executionType": "read_only",
                "willExecute": False,
                "evidenceRefs": ["releaseEvidence", "agentRun"]
            },
            {
                "stepId": "collect_more_samples",
                "title": "Collect more request samples",
                "purpose": "Recommend generating more canary traffic before making a stronger quality judgment.",
                "executionType": "manual_review",
                "willExecute": False,
                "evidenceRefs": ["releaseEvidence"]
            }
        ]

    steps.extend([
        {
            "stepId": "review_policy_decision",
            "title": "Review policy decision and approval requirement",
            "purpose": "Confirm why the platform recommends stopping promotion and whether human approval is required.",
            "executionType": "read_only",
            "willExecute": False,
            "evidenceRefs": ["agentRun", "releaseEvidence"]
        },
        {
            "stepId": "compare_change_context",
            "title": "Compare change context",
            "purpose": "Identify changed image tag, env vars, commit, or rollout strategy values related to the failure.",
            "executionType": "read_only",
            "willExecute": False,
            "evidenceRefs": ["releaseEvidence"]
        },
        {
            "stepId": "inspect_canary_logs",
            "title": "Inspect canary logs",
            "purpose": "Check canary application logs around the failed AnalysisRun window.",
            "executionType": "read_only",
            "willExecute": False,
            "evidenceRefs": ["failureEvidence", "releaseEvidence"]
        }
    ])

    if "error-rate" in failed_metrics:
        steps.append({
            "stepId": "inspect_5xx_error_paths",
            "title": "Inspect 5xx error paths",
            "purpose": "Find request paths, handlers, or dependencies causing elevated error rate.",
            "executionType": "read_only",
            "willExecute": False,
            "evidenceRefs": ["failureEvidence", "releaseEvidence"]
        })

    if "p95-latency" in failed_metrics:
        steps.append({
            "stepId": "inspect_tail_latency_paths",
            "title": "Inspect tail latency paths",
            "purpose": "Find slow handlers, dependency waits, or resource contention causing p95 latency regression.",
            "executionType": "read_only",
            "willExecute": False,
            "evidenceRefs": ["failureEvidence", "releaseEvidence"]
        })

    if retrieved_count > 0:
        steps.append({
            "stepId": "review_similar_failure_evidence",
            "title": "Review similar historical failures",
            "purpose": "Use retrieved historical evidence to compare symptoms, final actions, and prior investigation paths.",
            "executionType": "read_only",
            "willExecute": False,
            "evidenceRefs": ["retrievedEvidence", "releaseMemory"]
        })

    return steps

def build_followups(release_result: str, recommended_action: str) -> list[dict[str, Any]]:
    if release_result == "PASS":
        return []

    followups = [
        {
            "action": recommended_action or "MANUAL_REVIEW",
            "reason": "Recommended by read-only agent planning stage.",
            "requiresStage32ExecutionRequest": True,
            "requiresHumanApproval": True,
            "willExecute": False
        }
    ]

    if str(release_result).startswith("FAIL"):
        followups.append({
            "action": "PREPARE_FIX_FORWARD_OR_ROLLBACK_DECISION",
            "reason": "Failure remediation must be converted into a policy-bound execution request before any change.",
            "requiresStage32ExecutionRequest": True,
            "requiresHumanApproval": True,
            "willExecute": False
        })

    return followups

agent = load_json(agent_run_path)
evidence = load_json(evidence_path)
intelligence_doc = load_json(intelligence_path)
memory_records = load_jsonl(memory_path)

agent_release = as_dict(agent.get("release"))
observation = as_dict(agent.get("observation"))
policy = as_dict(agent.get("policy"))
recommendation = as_dict(agent.get("recommendation"))
agent_inputs = as_dict(agent.get("inputs"))
agent_artifacts = as_dict(agent_inputs.get("artifacts"))
intelligence = as_dict(intelligence_doc.get("intelligence"))

release_id = first_not_none(
    agent_release.get("releaseId"),
    evidence.get("releaseId"),
    release_id_from_agent_path(agent_run_path)
)
release_result = str(first_not_none(
    agent_release.get("releaseResult"),
    observation.get("releaseResult"),
    evidence.get("releaseResult"),
    "UNKNOWN"
))
failed_metrics = [str(item) for item in as_list(first_not_none(
    observation.get("failedMetrics"),
    as_dict(evidence.get("summary")).get("failedMetrics"),
    []
))]
policy_decision = nullable_string(first_not_none(policy.get("policyDecision"), evidence.get("policyDecision")))
recommended_action = nullable_string(first_not_none(recommendation.get("recommendedAction"), evidence.get("finalAction")))

risk_pattern = nullable_string(first_not_none(
    intelligence.get("riskPattern"),
    as_dict(agent.get("reasoning")).get("riskPattern"),
))

query = {
    "releaseId": str(release_id),
    "service": agent_release.get("service"),
    "env": agent_release.get("env"),
    "releaseResult": release_result,
    "policyDecision": policy_decision,
    "recommendedAction": recommended_action,
    "failedMetrics": failed_metrics,
    "riskPattern": risk_pattern,
}

scored_records = []
query_metric_set = set(failed_metrics)

for record in memory_records:
    record_result = str(record.get("releaseResult") or "")
    record_metric_set = set(record.get("failedMetrics") or [])

    if release_result == "PASS" and record_result != "PASS":
        continue

    if str(release_result).startswith("FAIL"):
        if not record_result.startswith("FAIL"):
            continue
        if query_metric_set and not (query_metric_set & record_metric_set):
            continue

    score, signals = score_record(record, query, evidence_path)
    if score <= 0:
        continue
    scored_records.append(compact_record(record, score, signals))

scored_records = sorted(
    scored_records,
    key=lambda item: (as_dict(item.get("similarity")).get("score", 0), item.get("generatedAt") or ""),
    reverse=True,
)

retrieved = scored_records[:8]
steps = build_steps(release_result, failed_metrics, len(retrieved))

priority = nullable_string(recommendation.get("priority"))
if not priority:
    if release_result == "PASS":
        priority = "none"
    elif "error-rate" in failed_metrics and "p95-latency" in failed_metrics:
        priority = "critical"
    elif failed_metrics:
        priority = "high"
    else:
        priority = "medium"

if release_result == "PASS":
    plan_type = "archive_and_observe"
    summary = "Release passed. The plan is to archive the record and continue observation."
elif retrieved:
    plan_type = "rag_assisted_failure_investigation"
    summary = "Release failed and similar historical evidence was retrieved. The plan prioritizes comparing current symptoms with previous failures before requesting any action."
elif str(release_result).startswith("FAIL"):
    plan_type = "new_failure_investigation"
    summary = "Release failed but no similar historical evidence was retrieved. The plan treats this as a new or weakly matched failure pattern."
else:
    plan_type = "manual_review_planning"
    summary = "Release signal is incomplete. The plan recommends collecting more evidence and manual review."

plan_run_id = "pr-" + str(release_id)

plan_run = {
    "schemaVersion": "agent.plan.run/v1alpha1",
    "planRunId": plan_run_id,
    "sourceAgentRunId": str(agent.get("agentRunId") or ""),
    "generatedBy": "build-plan-run.sh",
    "generatedAt": now(),
    "mode": "read_only_planning",
    "release": {
        "releaseId": str(release_id),
        "service": agent_release.get("service"),
        "env": agent_release.get("env"),
        "namespace": agent_release.get("namespace"),
        "version": agent_release.get("version"),
        "commit": agent_release.get("commit"),
        "imageDigest": agent_release.get("imageDigest"),
        "releaseResult": release_result,
        "policyDecision": policy_decision,
        "recommendedAction": recommended_action,
        "failedMetrics": failed_metrics,
        "riskLevel": observation.get("riskLevel"),
        "riskScore": observation.get("riskScore"),
    },
    "inputs": {
        "agentRun": str(agent_run_path),
        "releaseEvidence": str(evidence_path) if evidence_path else agent_inputs.get("releaseEvidence"),
        "releaseIntelligence": str(intelligence_path) if intelligence_path else agent_inputs.get("releaseIntelligence"),
        "releaseMemory": str(memory_path) if memory_path and memory_path.exists() else None,
        "artifacts": agent_artifacts,
    },
    "retrieval": {
        "strategy": "lightweight_rule_based_rag_v1",
        "query": query,
        "retrievedEvidence": retrieved,
        "summary": {
            "memoryRecordCount": len(memory_records),
            "retrievedEvidenceCount": len(retrieved),
            "topScore": as_dict(retrieved[0].get("similarity")).get("score") if retrieved else 0,
            "riskPattern": risk_pattern,
        },
    },
    "plan": {
        "planType": plan_type,
        "priority": priority,
        "summary": summary,
        "investigationSteps": steps,
        "candidateFollowUpActions": build_followups(release_result, recommended_action or "MANUAL_REVIEW"),
        "willExecute": False,
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
output_json.write_text(json.dumps(plan_run, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Plan run generated: {output_json}")
print(f"Latest plan run: {latest_json}")
print(json.dumps({
    "planRunId": plan_run["planRunId"],
    "sourceAgentRunId": plan_run["sourceAgentRunId"],
    "releaseId": plan_run["release"]["releaseId"],
    "releaseResult": plan_run["release"]["releaseResult"],
    "planType": plan_run["plan"]["planType"],
    "retrievedEvidenceCount": plan_run["retrieval"]["summary"]["retrievedEvidenceCount"],
    "mode": plan_run["mode"],
    "willExecute": plan_run["guardrails"]["willExecute"],
}, ensure_ascii=False, indent=2))
PY_PLAN_RUN

validate_generated_release_contract "$OUTPUT_JSON"

if [ -n "${RELEASE_EVIDENCE_FILE:-}" ] && [ -f "$RELEASE_EVIDENCE_FILE" ]; then
  python3 - "$RELEASE_EVIDENCE_FILE" "$OUTPUT_JSON" <<'PY_PLAN_LINK'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
plan_run_path = Path(sys.argv[2])

evidence = json.loads(evidence_path.read_text(encoding="utf-8-sig"))
plan_run = json.loads(plan_run_path.read_text(encoding="utf-8-sig"))

plan = plan_run.get("plan") or {}
retrieval = plan_run.get("retrieval") or {}
retrieval_summary = retrieval.get("summary") or {}

artifacts = evidence.setdefault("artifacts", {})
artifacts["planRun"] = str(plan_run_path)

evidence["planRunId"] = plan_run.get("planRunId")

decision_refs = evidence.setdefault("decisionRefs", {})
decision_refs["planRun"] = {
    "planRunId": plan_run.get("planRunId"),
    "sourceAgentRunId": plan_run.get("sourceAgentRunId"),
    "mode": plan_run.get("mode"),
    "planType": plan.get("planType"),
    "priority": plan.get("priority"),
    "retrievedEvidenceCount": retrieval_summary.get("retrievedEvidenceCount"),
    "willExecute": plan.get("willExecute"),
    "guardrails": plan_run.get("guardrails") or {},
}

evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Plan run linked into release evidence: {evidence_path}")
PY_PLAN_LINK

  validate_generated_release_contract "$RELEASE_EVIDENCE_FILE"
else
  echo "WARN: release evidence not found, skip linking plan run: ${RELEASE_EVIDENCE_FILE:-not provided}" >&2
fi

cat "$OUTPUT_JSON"
