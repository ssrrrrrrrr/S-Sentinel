#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
Usage:
  scripts/build-release-memory.sh

Environment:
  RELEASE_REPORT_DIR    Optional. Defaults to /data/nfs/slo-rollout-watcher/reports if it exists, otherwise docs/release-reports.
  RELEASE_MEMORY_FILE   Optional. Defaults to $RELEASE_REPORT_DIR/release-memory.jsonl.

Behavior:
  - Scans release-evidence-*.json.
  - Builds release-memory.jsonl and release-memory-latest.json.
  - This script only reads evidence and writes memory files. It does not modify Kubernetes, GitOps, or execute actions.
USAGE
  exit 0
fi

if [ -n "${RELEASE_REPORT_DIR:-}" ]; then
  REPORT_DIR="$RELEASE_REPORT_DIR"
elif [ -d "/data/nfs/slo-rollout-watcher/reports" ]; then
  REPORT_DIR="/data/nfs/slo-rollout-watcher/reports"
else
  REPORT_DIR="docs/release-reports"
fi

MEMORY_FILE="${RELEASE_MEMORY_FILE:-$REPORT_DIR/release-memory.jsonl}"
LATEST_JSON="$REPORT_DIR/release-memory-latest.json"

mkdir -p "$REPORT_DIR"

python3 - "$REPORT_DIR" "$MEMORY_FILE" "$LATEST_JSON" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

report_dir = Path(sys.argv[1])
memory_file = Path(sys.argv[2])
latest_json = Path(sys.argv[3])

def utc_now():
    return datetime.now(timezone.utc).isoformat()

def file_time(path: Path):
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()

def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None

def resolve_artifact(ref):
    if not ref:
        return None
    p = Path(str(ref))
    candidates = []
    if p.is_absolute():
        candidates.append(p)
    candidates.append(report_dir / p.name)
    candidates.append(p)
    for c in candidates:
        if c.exists() and c.is_file():
            return c
    return None

def first_value(*values):
    for value in values:
        if value is not None and value != "":
            return value
    return None

records = []
skipped = []

for evidence_path in sorted(report_dir.glob("release-evidence-*.json"), key=lambda p: p.stat().st_mtime):
    evidence = read_json(evidence_path)
    if not isinstance(evidence, dict):
        skipped.append(str(evidence_path))
        continue

    artifacts = evidence.get("artifacts") or {}
    summary = evidence.get("summary") or {}

    release_context_path = resolve_artifact(artifacts.get("releaseContext"))
    release_context = read_json(release_context_path) if release_context_path else {}
    if not isinstance(release_context, dict):
        release_context = {}

    action_plan_path = resolve_artifact(artifacts.get("actionPlan"))
    action_plan = read_json(action_plan_path) if action_plan_path else {}
    if not isinstance(action_plan, dict):
        action_plan = {}

    failure_evidence_path = resolve_artifact(artifacts.get("failureEvidence"))
    failure_evidence = read_json(failure_evidence_path) if failure_evidence_path else {}
    if not isinstance(failure_evidence, dict):
        failure_evidence = {}

    failed_metrics = summary.get("failedMetrics") or []
    release_result = evidence.get("releaseResult", "UNKNOWN")

    action_plan_body = action_plan.get("actionPlan") or {}
    candidate_commands = action_plan_body.get("candidateCommands") or []

    record = {
        "schemaVersion": "release.memory.record/v1alpha1",
        "generatedAt": file_time(evidence_path),
        "sourceReleaseEvidence": str(evidence_path),
        "releaseId": first_value(
            release_context.get("releaseId"),
            release_context.get("release_id"),
            evidence_path.stem.replace("release-evidence-", ""),
        ),
        "app": first_value(
            release_context.get("app"),
            release_context.get("appName"),
            "demo-app",
        ),
        "namespace": first_value(
            release_context.get("namespace"),
            action_plan.get("target", {}).get("namespace") if action_plan else None,
            "unknown",
        ),
        "rollout": first_value(
            release_context.get("rollout"),
            release_context.get("rolloutName"),
            action_plan.get("target", {}).get("rollout") if action_plan else None,
            "unknown",
        ),
        "appVersion": first_value(
            release_context.get("appVersion"),
            release_context.get("version"),
            release_context.get("currentDesiredVersion"),
            release_context.get("imageTag"),
        ),
        "image": first_value(
            release_context.get("image"),
            release_context.get("currentImage"),
            release_context.get("targetImage"),
        ),
        "releaseResult": release_result,
        "policyDecision": evidence.get("policyDecision", "UNKNOWN"),
        "finalAction": evidence.get("finalAction", "UNKNOWN"),
        "executionMode": evidence.get("executionMode", "unknown"),
        "requiresHumanApproval": bool(evidence.get("requiresHumanApproval", False)),
        "safeToRetry": bool(evidence.get("safeToRetry", False)),
        "failedMetrics": failed_metrics,
        "riskLevel": summary.get("riskLevel"),
        "riskScore": summary.get("riskScore"),
        "rolloutPhase": summary.get("rolloutPhase"),
        "rolloutAbort": summary.get("rolloutAbort"),
        "analysisRunPhase": summary.get("analysisRunPhase"),
        "artifacts": {
            "releaseContext": str(release_context_path) if release_context_path else artifacts.get("releaseContext"),
            "releaseReport": artifacts.get("releaseReport"),
            "aiAdvice": artifacts.get("aiAdvice"),
            "aiDecision": artifacts.get("aiDecision"),
            "policyDecision": artifacts.get("policyDecision"),
            "releaseSummary": artifacts.get("releaseSummary"),
            "failureEvidence": str(failure_evidence_path) if failure_evidence_path else artifacts.get("failureEvidence"),
            "failureEvidenceReport": artifacts.get("failureEvidenceReport"),
            "actionPlan": str(action_plan_path) if action_plan_path else artifacts.get("actionPlan"),
            "actionPlanReport": artifacts.get("actionPlanReport"),
        },
        "failureEvidence": {
            "generated": bool(failure_evidence_path),
            "isFailure": failure_evidence.get("isFailure") if failure_evidence else None,
            "severity": failure_evidence.get("severity") if failure_evidence else None,
            "failedMetrics": (failure_evidence.get("release") or {}).get("failedMetrics") if failure_evidence else None,
        },
        "actionPlan": {
            "generated": bool(action_plan_path),
            "executionMode": action_plan.get("executionMode") if action_plan else None,
            "willExecute": action_plan.get("willExecute") if action_plan else None,
            "blocked": action_plan_body.get("blocked") if action_plan_body else None,
            "candidateCommandCount": len(candidate_commands),
        },
    }

    records.append(record)

memory_file.write_text(
    "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records),
    encoding="utf-8",
)

failures = [r for r in records if str(r.get("releaseResult", "")).startswith("FAIL")]
passes = [r for r in records if r.get("releaseResult") == "PASS"]

summary = {
    "schemaVersion": "release.memory/v1alpha1",
    "generatedBy": "build-release-memory.sh",
    "generatedAt": utc_now(),
    "sourceReportDir": str(report_dir),
    "memoryFile": str(memory_file),
    "recordCount": len(records),
    "passCount": len(passes),
    "failureCount": len(failures),
    "skippedCount": len(skipped),
    "latestRelease": records[-1] if records else None,
    "latestFailure": failures[-1] if failures else None,
    "recentRecords": records[-10:],
}

latest_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Release memory generated: {memory_file}")
print(f"Latest release memory summary: {latest_json}")
print(json.dumps({
    "recordCount": len(records),
    "passCount": len(passes),
    "failureCount": len(failures),
    "latestReleaseResult": records[-1]["releaseResult"] if records else None,
    "latestFailureResult": failures[-1]["releaseResult"] if failures else None,
}, ensure_ascii=False, indent=2))
PY
