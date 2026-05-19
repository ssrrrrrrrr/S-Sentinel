#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-}"
RELEASE_EVIDENCE_FILE="${1:-latest}"

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
  scripts/build-release-intelligence.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                 Optional report directory.
  RELEASE_MEMORY_FILE                Optional memory file. Defaults to $RELEASE_REPORT_DIR/release-memory.jsonl.
  RELEASE_INTELLIGENCE_OUTPUT_DIR    Optional output directory. Defaults to release evidence directory.

Behavior:
  - Reads release evidence and release memory.
  - Generates release-intelligence-*.json and release-intelligence-*.md.
  - Does not modify Kubernetes, GitOps, Rollouts, Deployments, images, commits, or pushes.
USAGE
}

if [ "$RELEASE_EVIDENCE_FILE" = "-h" ] || [ "$RELEASE_EVIDENCE_FILE" = "--help" ]; then
  usage
  exit 0
fi

if [ "$RELEASE_EVIDENCE_FILE" = "latest" ] || [ -z "$RELEASE_EVIDENCE_FILE" ]; then
  RELEASE_EVIDENCE_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | head -1 || true)"
fi

if [ -z "$RELEASE_EVIDENCE_FILE" ] || [ ! -f "$RELEASE_EVIDENCE_FILE" ]; then
  echo "ERROR: release evidence file does not exist: ${RELEASE_EVIDENCE_FILE:-not provided}" >&2
  exit 1
fi

MEMORY_FILE="${RELEASE_MEMORY_FILE:-$REPORT_DIR/release-memory.jsonl}"

if [ ! -f "$MEMORY_FILE" ]; then
  MEMORY_BUILDER=""

  if [ -x "./scripts/build-release-memory.sh" ]; then
    MEMORY_BUILDER="./scripts/build-release-memory.sh"
  elif [ -x "/app/scripts/build-release-memory.sh" ]; then
    MEMORY_BUILDER="/app/scripts/build-release-memory.sh"
  fi

  if [ -z "$MEMORY_BUILDER" ]; then
    echo "ERROR: release memory file missing and build-release-memory.sh not found: $MEMORY_FILE" >&2
    exit 1
  fi

  RELEASE_REPORT_DIR="$REPORT_DIR" \
  RELEASE_MEMORY_FILE="$MEMORY_FILE" \
    "$MEMORY_BUILDER"
fi

OUTPUT_DIR="${RELEASE_INTELLIGENCE_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$RELEASE_EVIDENCE_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_JSON="$OUTPUT_DIR/release-intelligence-$SUFFIX"
OUTPUT_MD="$OUTPUT_DIR/release-intelligence-${SUFFIX%.json}.md"
LATEST_JSON="$OUTPUT_DIR/release-intelligence-latest.json"
LATEST_MD="$OUTPUT_DIR/release-intelligence-latest.md"

python3 - "$RELEASE_EVIDENCE_FILE" "$MEMORY_FILE" "$OUTPUT_JSON" "$OUTPUT_MD" "$LATEST_JSON" "$LATEST_MD" <<'PY'
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

evidence_path = Path(sys.argv[1])
memory_path = Path(sys.argv[2])
output_json = Path(sys.argv[3])
output_md = Path(sys.argv[4])
latest_json = Path(sys.argv[5])
latest_md = Path(sys.argv[6])

def now():
    return datetime.now(timezone.utc).isoformat()

def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def safe_list(value):
    return value if isinstance(value, list) else []

def same_source(record_source, current_path):
    if not record_source:
        return False

    record_path = Path(str(record_source))
    current_path = Path(str(current_path))

    if str(record_path) == str(current_path):
        return True

    if record_path.name == current_path.name:
        return True

    try:
        if record_path.exists() and current_path.exists():
            return record_path.resolve() == current_path.resolve()
    except Exception:
        pass

    return False

def compact_record(record):
    return {
        "releaseId": record.get("releaseId"),
        "generatedAt": record.get("generatedAt"),
        "appVersion": record.get("appVersion"),
        "releaseResult": record.get("releaseResult"),
        "policyDecision": record.get("policyDecision"),
        "finalAction": record.get("finalAction"),
        "requiresHumanApproval": record.get("requiresHumanApproval"),
        "failedMetrics": record.get("failedMetrics") or [],
        "riskLevel": record.get("riskLevel"),
        "riskScore": record.get("riskScore"),
        "rolloutPhase": record.get("rolloutPhase"),
        "analysisRunPhase": record.get("analysisRunPhase"),
        "sourceReleaseEvidence": record.get("sourceReleaseEvidence"),
        "failureEvidence": record.get("artifacts", {}).get("failureEvidence"),
        "actionPlan": record.get("artifacts", {}).get("actionPlan"),
        "actionPlanCandidateCommandCount": record.get("actionPlan", {}).get("candidateCommandCount"),
    }

evidence = read_json(evidence_path)
summary = evidence.get("summary") or {}
artifacts = evidence.get("artifacts") or {}

records = []
if memory_path.exists():
    for line in memory_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            try:
                records.append(json.loads(line))
            except Exception:
                pass

release_result = evidence.get("releaseResult", "UNKNOWN")
policy_decision = evidence.get("policyDecision", "UNKNOWN")
final_action = evidence.get("finalAction", "UNKNOWN")
requires_human_approval = bool(evidence.get("requiresHumanApproval", False))
failed_metrics = safe_list(summary.get("failedMetrics"))
failed_metric_set = set(failed_metrics)

current_memory_record = None
for record in records:
    if same_source(record.get("sourceReleaseEvidence"), evidence_path):
        current_memory_record = record
        break

failures = [r for r in records if str(r.get("releaseResult", "")).startswith("FAIL")]
passes = [r for r in records if r.get("releaseResult") == "PASS"]

similar_failures = []
similar_failures_including_current = []

if failed_metric_set:
    for record in failures:
        metrics = set(record.get("failedMetrics") or [])
        overlap = sorted(failed_metric_set & metrics)

        if not overlap:
            continue

        item = compact_record(record)
        item["similarity"] = {
            "queryMetrics": sorted(failed_metric_set),
            "matchedMetrics": overlap,
            "score": len(overlap),
            "exactMetricSetMatch": metrics == failed_metric_set,
            "isCurrentEvidence": same_source(record.get("sourceReleaseEvidence"), evidence_path),
        }

        similar_failures_including_current.append(item)

        if not item["similarity"]["isCurrentEvidence"]:
            similar_failures.append(item)

similar_failures = sorted(
    similar_failures,
    key=lambda r: (r.get("similarity", {}).get("score", 0), r.get("generatedAt") or ""),
    reverse=True,
)

similar_failures_including_current = sorted(
    similar_failures_including_current,
    key=lambda r: (r.get("similarity", {}).get("score", 0), r.get("generatedAt") or ""),
    reverse=True,
)

exact_historical_matches = [
    r for r in similar_failures
    if r.get("similarity", {}).get("exactMetricSetMatch")
]

recent_failures = [compact_record(r) for r in list(reversed(failures))[:5]]
recent_releases = [compact_record(r) for r in list(reversed(records))[:5]]

if release_result == "PASS":
    risk_pattern = "healthy_release"
    repeated_risk_pattern = False
    recommended_next_action = "archive_release_record"
    conclusion = "本次发布通过 SLO 门禁，当前没有失败指标。建议归档发布记录并继续观察。"
elif failed_metric_set and exact_historical_matches:
    risk_pattern = "repeated_slo_failure_pattern"
    repeated_risk_pattern = True
    recommended_next_action = final_action or "STOP_PROMOTION"
    conclusion = "本次发布失败指标与历史失败记录完全匹配，属于重复风险模式。建议停止继续放量并人工排查。"
elif failed_metric_set and similar_failures:
    risk_pattern = "similar_slo_failure_pattern"
    repeated_risk_pattern = True
    recommended_next_action = final_action or "STOP_PROMOTION"
    conclusion = "本次发布失败指标与历史失败记录存在重叠，建议结合历史证据排查相似问题。"
elif failed_metric_set:
    risk_pattern = "new_slo_failure_pattern"
    repeated_risk_pattern = False
    recommended_next_action = final_action or "STOP_PROMOTION"
    conclusion = "本次发布出现 SLO 失败，但没有找到历史相似失败记录。建议作为新故障模式进行人工排查。"
else:
    risk_pattern = "unknown_or_incomplete_signal"
    repeated_risk_pattern = False
    recommended_next_action = final_action or "manual_review"
    conclusion = "当前证据未提供明确失败指标，建议人工复核 Release Evidence。"

intelligence = {
    "schemaVersion": "release.intelligence/v1alpha1",
    "generatedBy": "build-release-intelligence.sh",
    "generatedAt": now(),
    "sourceReleaseEvidence": str(evidence_path),
    "sourceReleaseMemory": str(memory_path),
    "release": {
        "releaseResult": release_result,
        "policyDecision": policy_decision,
        "finalAction": final_action,
        "executionMode": evidence.get("executionMode", "unknown"),
        "requiresHumanApproval": requires_human_approval,
        "safeToRetry": evidence.get("safeToRetry"),
        "failedMetrics": failed_metrics,
        "riskLevel": summary.get("riskLevel"),
        "riskScore": summary.get("riskScore"),
        "rolloutPhase": summary.get("rolloutPhase"),
        "rolloutAbort": summary.get("rolloutAbort"),
        "analysisRunPhase": summary.get("analysisRunPhase"),
        "currentMemoryRecordFound": current_memory_record is not None,
    },
    "history": {
        "recordCount": len(records),
        "passCount": len(passes),
        "failureCount": len(failures),
        "recentReleases": recent_releases,
        "recentFailures": recent_failures,
        "similarFailureCount": len(similar_failures),
        "similarFailureIncludingCurrentCount": len(similar_failures_including_current),
        "exactHistoricalMetricSetMatchCount": len(exact_historical_matches),
        "similarFailures": similar_failures[:10],
        "similarFailuresIncludingCurrent": similar_failures_including_current[:10],
    },
    "intelligence": {
        "riskPattern": risk_pattern,
        "repeatedRiskPattern": repeated_risk_pattern,
        "recommendedNextAction": recommended_next_action,
        "conclusion": conclusion,
        "humanSummary": conclusion,
    },
    "artifacts": {
        "releaseContext": artifacts.get("releaseContext"),
        "releaseReport": artifacts.get("releaseReport"),
        "releaseEvidence": str(evidence_path),
        "releaseMemory": str(memory_path),
        "failureEvidence": artifacts.get("failureEvidence"),
        "actionPlan": artifacts.get("actionPlan"),
    },
    "guardrails": {
        "advisoryOnly": True,
        "readOnlyAnalysis": True,
        "doesNotModifyGitOps": True,
        "doesNotModifyKubernetes": True,
        "doesNotRollback": True,
        "doesNotPromote": True,
        "doesNotPatchResources": True,
        "doesNotDeleteResources": True,
        "doesNotBuildImages": True,
        "doesNotCommitOrPush": True,
    },
}

output_json.write_text(json.dumps(intelligence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

similar_lines = ""
if similar_failures:
    for item in similar_failures[:5]:
        similarity = item.get("similarity", {})
        similar_lines += (
            f"- ReleaseId: `{item.get('releaseId')}`\n"
            f"  - AppVersion: `{item.get('appVersion')}`\n"
            f"  - Result: `{item.get('releaseResult')}`\n"
            f"  - Metrics: `{', '.join(item.get('failedMetrics') or [])}`\n"
            f"  - FinalAction: `{item.get('finalAction')}`\n"
            f"  - SimilarityScore: `{similarity.get('score')}`\n"
            f"  - ExactMetricSetMatch: `{str(similarity.get('exactMetricSetMatch')).lower()}`\n"
        )
else:
    similar_lines = "未发现历史相似失败记录。\n"

recent_failure_lines = ""
if recent_failures:
    for item in recent_failures[:5]:
        recent_failure_lines += (
            f"- `{item.get('releaseId')}` / `{item.get('appVersion')}` / "
            f"`{item.get('releaseResult')}` / `{', '.join(item.get('failedMetrics') or [])}`\n"
        )
else:
    recent_failure_lines = "暂无历史失败记录。\n"

md = f"""<!--
Generated by build-release-intelligence.sh
Source release evidence: {evidence_path}
Source release memory: {memory_path}
-->

# Release Intelligence Summary

## 1. 当前发布结论

- Release Result：`{release_result}`
- Policy Decision：`{policy_decision}`
- Final Action：`{final_action}`
- Requires Human Approval：`{str(requires_human_approval).lower()}`
- Failed Metrics：`{", ".join(failed_metrics) if failed_metrics else "none"}`
- Risk Level：`{summary.get("riskLevel")}`
- Risk Score：`{summary.get("riskScore")}`

## 2. 历史记忆统计

- Memory Records：`{len(records)}`
- PASS Count：`{len(passes)}`
- Failure Count：`{len(failures)}`
- Similar Historical Failure Count：`{len(similar_failures)}`
- Exact Historical Metric Set Match Count：`{len(exact_historical_matches)}`

## 3. 智能判断

- Risk Pattern：`{risk_pattern}`
- Repeated Risk Pattern：`{str(repeated_risk_pattern).lower()}`
- Recommended Next Action：`{recommended_next_action}`

{conclusion}

## 4. 历史相似失败

{similar_lines}

## 5. 最近失败记录

{recent_failure_lines}

## 6. 安全边界

本报告只进行只读历史分析，不会自动执行 Rollback、Promote、Patch、Delete、GitOps 变更、镜像构建、Commit 或 Push。
"""

output_md.write_text(md, encoding="utf-8")
shutil.copyfile(output_md, latest_md)

print(f"Release intelligence JSON generated: {output_json}")
print(f"Release intelligence Markdown generated: {output_md}")
print(f"Latest release intelligence JSON: {latest_json}")
print(f"Latest release intelligence Markdown: {latest_md}")
print(json.dumps({
    "releaseResult": release_result,
    "riskPattern": risk_pattern,
    "repeatedRiskPattern": repeated_risk_pattern,
    "similarFailureCount": len(similar_failures),
    "similarFailureIncludingCurrentCount": len(similar_failures_including_current),
    "recommendedNextAction": recommended_next_action,
}, ensure_ascii=False, indent=2))
PY
