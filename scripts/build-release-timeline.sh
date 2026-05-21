#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
RELEASE_EVIDENCE_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-release-timeline.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR              Optional report directory.
  RELEASE_TIMELINE_OUTPUT_DIR     Optional output directory. Defaults to release evidence directory.

Behavior:
  - Reads release evidence.
  - Generates release-timeline-<releaseId>.json and release-timeline-latest.json.
  - Does not modify Kubernetes, GitOps, Rollouts, Deployments, images, commits, or pushes.
USAGE
}

if [ "$RELEASE_EVIDENCE_FILE" = "-h" ] || [ "$RELEASE_EVIDENCE_FILE" = "--help" ]; then
  usage
  exit 0
fi

if [ "$RELEASE_EVIDENCE_FILE" = "latest" ] || [ -z "$RELEASE_EVIDENCE_FILE" ]; then
  RELEASE_EVIDENCE_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | grep -v 'release-evidence-latest.json' | head -1 || true)"
fi

if [ -z "$RELEASE_EVIDENCE_FILE" ] || [ ! -f "$RELEASE_EVIDENCE_FILE" ]; then
  echo "ERROR: release evidence file does not exist: ${RELEASE_EVIDENCE_FILE:-not provided}" >&2
  exit 1
fi

OUTPUT_DIR="${RELEASE_TIMELINE_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$RELEASE_EVIDENCE_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_JSON="$OUTPUT_DIR/release-timeline-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/release-timeline-latest.json"

python3 - "$RELEASE_EVIDENCE_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

evidence_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
latest_json = Path(sys.argv[3])

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))

def scalar(value: Any, fallback: str = "unknown") -> str:
    if value is None:
        return fallback
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return ", ".join(scalar(item) for item in value) if value else "none"
    return str(value)

def release_id_from_evidence(path: Path) -> str:
    base = path.name
    if base.startswith("release-evidence-") and base.endswith(".json"):
        return base[len("release-evidence-"):-len(".json")]
    return path.stem

def resolve_ref(ref: Any, source_path: Path) -> Path | None:
    if not ref:
        return None

    ref_path = Path(str(ref))
    candidates = [ref_path]

    if not ref_path.is_absolute():
        candidates.extend([
            Path.cwd() / ref_path,
            source_path.parent / ref_path.name,
            source_path.parent / ref_path,
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

def find_by_globs(source_path: Path, patterns: list[str]) -> Path | None:
    for pattern in patterns:
        matches = sorted(source_path.parent.glob(pattern), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
        for match in matches:
            if match.is_file() and "-latest." not in match.name:
                return match
    return None

def file_modified_at(path: Path | None) -> str | None:
    if not path:
        return None
    try:
        return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()
    except OSError:
        return None

def file_size(path: Path | None) -> int | None:
    if not path:
        return None
    try:
        return path.stat().st_size
    except OSError:
        return None

def build_event(
    sequence: int,
    stage: str,
    title: str,
    description: str,
    artifact_kind: str,
    ref: Any,
    source_path: Path,
    fallback_patterns: list[str] | None = None,
) -> dict[str, Any]:
    resolved = resolve_ref(ref, source_path)

    if not resolved and fallback_patterns:
        resolved = find_by_globs(source_path, fallback_patterns)

    collected = resolved is not None

    return {
        "sequence": sequence,
        "stage": stage,
        "title": title,
        "description": description,
        "status": "COLLECTED" if collected else "MISSING",
        "artifactKind": artifact_kind,
        "artifact": {
            "path": str(resolved) if resolved else scalar(ref, ""),
            "baseName": resolved.name if resolved else "",
            "exists": collected,
            "sizeBytes": file_size(resolved),
            "modifiedAt": file_modified_at(resolved),
        },
    }

evidence = load_json(evidence_path)
release_id = release_id_from_evidence(evidence_path)
artifacts = evidence.get("artifacts", {}) if isinstance(evidence.get("artifacts"), dict) else {}
summary = evidence.get("summary", {}) if isinstance(evidence.get("summary"), dict) else {}

stage_defs = [
    ("release_context_collected", "Release Context", "发布上下文与目标对象被采集。", "releaseContext", artifacts.get("releaseContext"), []),
    ("release_report_collected", "Release Report", "Rollout 与 AnalysisRun 结果被写入发布报告。", "releaseReport", artifacts.get("releaseReport"), []),
    ("ai_advice_generated", "AI Advice", "Advisor 生成面向人工阅读的建议报告。", "aiAdvice", artifacts.get("aiAdvice"), [f"ai-advice-{release_id}.md"]),
    ("ai_decision_generated", "AI Decision", "Advisor 生成结构化发布判断。", "aiDecision", artifacts.get("aiDecision"), [f"ai-decision-{release_id}.json"]),
    ("policy_decision_evaluated", "Policy Decision", "策略层完成安全裁决。", "policyDecision", artifacts.get("policyDecision"), [f"policy-decision-{release_id}.json"]),
    ("release_evidence_built", "Release Evidence", "发布证据包完成生成。", "releaseEvidence", str(evidence_path), [f"release-evidence-{release_id}.json"]),
    ("release_summary_generated", "Release Summary", "面向人工阅读的发布摘要生成。", "releaseSummary", artifacts.get("releaseSummary"), [f"release-summary-{release_id}.md"]),
    ("failure_evidence_collected", "Failure Evidence", "失败场景的补充证据被采集。", "failureEvidence", artifacts.get("failureEvidence"), [f"failure-evidence-{release_id}.json"]),
    ("action_plan_generated", "Action Plan", "只读安全动作计划生成。", "actionPlan", artifacts.get("actionPlan"), [f"action-plan-{release_id}.json"]),
    ("release_intelligence_generated", "Release Intelligence", "历史风险模式分析生成。", "releaseIntelligence", artifacts.get("releaseIntelligence"), [f"release-intelligence-{release_id}.json"]),
    ("runbook_generated", "Runbook", "面向 SRE 操作的运行手册生成。", "runbook", artifacts.get("runbook"), [f"runbook-{release_id}.md"]),
    ("rca_generated", "RCA", "面向复盘的 RCA 报告生成。", "rca", artifacts.get("rca"), [f"rca-{release_id}.md"]),
]

events = [
    build_event(index + 1, stage, title, description, kind, ref, evidence_path, patterns)
    for index, (stage, title, description, kind, ref, patterns) in enumerate(stage_defs)
]

collected = sum(1 for event in events if event["status"] == "COLLECTED")
missing = [event["stage"] for event in events if event["status"] != "COLLECTED"]

timeline = {
    "schemaVersion": "release.timeline/v1alpha1",
    "generatedBy": "build-release-timeline.sh",
    "generatedAt": now(),
    "releaseId": release_id,
    "sourceEvidence": str(evidence_path),
    "releaseResult": scalar(evidence.get("releaseResult")),
    "policyDecision": scalar(evidence.get("policyDecision")),
    "finalAction": scalar(evidence.get("finalAction")),
    "executionMode": scalar(evidence.get("executionMode")),
    "requiresHumanApproval": bool(evidence.get("requiresHumanApproval", False)),
    "summary": {
        "rolloutPhase": scalar(summary.get("rolloutPhase")),
        "rolloutAbort": bool(summary.get("rolloutAbort", False)),
        "analysisRunPhase": scalar(summary.get("analysisRunPhase")),
        "riskLevel": scalar(summary.get("riskLevel")),
        "riskScore": summary.get("riskScore", 0),
        "failedMetrics": summary.get("failedMetrics", []),
    },
    "coverage": {
        "collected": collected,
        "total": len(events),
        "missingStages": missing,
    },
    "events": events,
    "safety": {
        "readOnly": True,
        "willExecute": False,
        "supportsRollback": False,
        "supportsPromote": False,
        "supportsPatch": False,
        "supportsDelete": False,
    },
}

output_json.write_text(json.dumps(timeline, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Release timeline JSON generated: {output_json}")
print(f"Latest release timeline JSON: {latest_json}")
print(json.dumps({
    "releaseId": release_id,
    "releaseResult": timeline["releaseResult"],
    "policyDecision": timeline["policyDecision"],
    "eventCount": len(events),
    "collected": collected,
    "missingStages": missing,
}, indent=2, ensure_ascii=False))
PY
