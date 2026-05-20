#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
RELEASE_EVIDENCE_FILE="${1:-latest}"

if [ "$RELEASE_EVIDENCE_FILE" = "-h" ] || [ "$RELEASE_EVIDENCE_FILE" = "--help" ]; then
  cat <<'USAGE'
Usage:
  scripts/build-release-rca.sh [latest|RELEASE_EVIDENCE_JSON]

Behavior:
  - Builds a Markdown RCA from release evidence.
  - Reads AI decision, policy decision, action-plan, failure evidence, and intelligence artifacts when available.
  - Does not execute kubectl, GitOps, rollback, promote, patch, delete, image build, commit, or push.
USAGE
  exit 0
fi

if [ "$RELEASE_EVIDENCE_FILE" = "latest" ] || [ -z "$RELEASE_EVIDENCE_FILE" ]; then
  RELEASE_EVIDENCE_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | head -1 || true)"
fi

if [ -z "$RELEASE_EVIDENCE_FILE" ] || [ ! -f "$RELEASE_EVIDENCE_FILE" ]; then
  echo "ERROR: release evidence file does not exist: ${RELEASE_EVIDENCE_FILE:-not provided}" >&2
  exit 1
fi

OUTPUT_DIR="${RCA_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$RELEASE_EVIDENCE_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_MD="$OUTPUT_DIR/rca-${SUFFIX%.json}.md"
LATEST_MD="$OUTPUT_DIR/rca-latest.md"

python3 - "$RELEASE_EVIDENCE_FILE" "$OUTPUT_MD" "$LATEST_MD" <<'PY'
from __future__ import annotations

import html
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

evidence_path = Path(sys.argv[1])
output_md = Path(sys.argv[2])
latest_md = Path(sys.argv[3])

def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))

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
            Path("/data/nfs/slo-rollout-watcher/reports") / ref_path.name,
            Path("/app/docs/release-reports") / ref_path.name,
        ])

    seen = set()
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

def load_ref(ref: Any, source_path: Path) -> tuple[dict[str, Any], str]:
    resolved = resolve_ref(ref, source_path)
    if not resolved:
        return {}, ""
    try:
        return load_json(resolved), str(resolved)
    except Exception:
        return {}, str(resolved)

def scalar(value: Any) -> str:
    if value is None:
        return "unknown"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return ", ".join(scalar(item) for item in value) if value else "none"
    return str(value)

def md_cell(value: Any) -> str:
    text = scalar(value)
    return text.replace("|", "\\|").replace("\n", "<br>")

def bullet_list(items: Any, empty_text: str = "none") -> list[str]:
    if not items:
        return [f"- {empty_text}"]
    if not isinstance(items, list):
        return [f"- {md_cell(items)}"]
    return [f"- {md_cell(item)}" for item in items]

def code_cell(command: Any) -> str:
    return f"<code>{html.escape(scalar(command))}</code>"

def infer_root_cause(summary: dict[str, Any], ai_decision: dict[str, Any], release_result: str) -> list[str]:
    failed_metrics = summary.get("failedMetrics") or ai_decision.get("failedMetrics") or []
    risk_reasons = ai_decision.get("riskReasons") or (ai_decision.get("evidence") or {}).get("riskReasons") or []

    if release_result == "PASS":
        return [
            "No incident root cause is inferred because the release passed all observed SLO gates.",
            "Continue monitoring the release and archive the release record.",
        ]

    hypotheses = []

    if "error-rate" in failed_metrics and "p95-latency" in failed_metrics:
        hypotheses.append("The canary version likely introduced a combined reliability regression: elevated error rate and elevated P95 latency.")
    elif "error-rate" in failed_metrics:
        hypotheses.append("The canary version likely introduced an application error regression.")
    elif "p95-latency" in failed_metrics:
        hypotheses.append("The canary version likely introduced a latency regression.")

    if summary.get("rolloutAbort") is True:
        hypotheses.append("Argo Rollouts aborted or degraded the rollout after AnalysisRun SLO gates failed.")

    if risk_reasons:
        hypotheses.extend(risk_reasons)

    if not hypotheses:
        hypotheses.append("The release failed SLO or rollout checks, but the exact root cause requires operator investigation.")

    return hypotheses

def follow_up_actions(release_result: str, final_action: str, failed_metrics: list[Any], requires_approval: bool) -> list[str]:
    if release_result == "PASS":
        return [
            "Archive the release evidence and summary.",
            "Continue observing error rate, latency, and request volume after promotion.",
        ]

    actions = [
        "Inspect canary logs and Kubernetes events around the failed AnalysisRun window.",
        "Compare the failed canary version with the previous stable version and recent change context.",
        "Publish a fixed version with a new immutable image tag after the suspected regression is corrected.",
        "Keep the failed release evidence, policy decision, AI decision, action plan, and RCA for later review.",
    ]

    if "error-rate" in failed_metrics:
        actions.append("Add or strengthen pre-release checks for 5xx/error-rate regressions.")

    if "p95-latency" in failed_metrics:
        actions.append("Add or strengthen latency and load checks before canary promotion.")

    if final_action in {"STOP_PROMOTION", "ABORT_ROLLOUT"}:
        actions.append("Do not resume promotion until the failed metrics are understood and validated.")

    if requires_approval:
        actions.append("Require human approval before any write action such as abort, rollback, or GitOps change.")

    return actions

evidence = load_json(evidence_path)
artifacts = evidence.get("artifacts") or {}

ai_decision, ai_decision_path = load_ref(artifacts.get("aiDecision"), evidence_path)
policy_decision_doc, policy_decision_path = load_ref(artifacts.get("policyDecision"), evidence_path)
action_plan, action_plan_path = load_ref(
    artifacts.get("actionPlan") or (evidence.get("actionPlanRef") or {}).get("json"),
    evidence_path,
)
failure_evidence, failure_evidence_path = load_ref(
    artifacts.get("failureEvidence") or (evidence.get("failureEvidenceRef") or {}).get("json"),
    evidence_path,
)
intelligence, intelligence_path = load_ref(
    artifacts.get("releaseIntelligence") or (evidence.get("releaseIntelligenceRef") or {}).get("json"),
    evidence_path,
)

release_id = output_md.stem.replace("rca-", "")
generated_at = datetime.now(timezone.utc).isoformat()

release_result = evidence.get("releaseResult", "UNKNOWN")
policy_decision = evidence.get("policyDecision", "UNKNOWN")
final_action = evidence.get("finalAction", "UNKNOWN")
execution_mode = evidence.get("executionMode", "unknown")
requires_human_approval = bool(evidence.get("requiresHumanApproval", False))
safe_to_retry = evidence.get("safeToRetry", "unknown")

summary = evidence.get("summary") or {}
failed_metrics = summary.get("failedMetrics") or []
matched_policy_rules = summary.get("matchedPolicyRules") or []

action_body = action_plan.get("actionPlan") or {}
target = action_plan.get("target") or {}
candidate_commands = action_body.get("candidateCommands") or []

namespace = target.get("namespace") or (ai_decision.get("rollout") or {}).get("namespace") or "unknown"
rollout = target.get("rollout") or (ai_decision.get("rollout") or {}).get("name") or "unknown"
analysis_run = target.get("analysisRun") or (ai_decision.get("analysisRun") or {}).get("name") or "unknown"

history = intelligence.get("history") or {}
intel = intelligence.get("intelligence") or {}

root_cause_hypotheses = infer_root_cause(summary, ai_decision, release_result)
follow_ups = follow_up_actions(release_result, final_action, list(failed_metrics), requires_human_approval)

analysis_metrics = (ai_decision.get("analysisRun") or {}).get("metrics") or []

lines: list[str] = []

lines.extend([
    f"# Release RCA: {release_id}",
    "",
    "> This RCA is generated from release evidence. It summarizes the incident, evidence, likely cause, impact, mitigation, and follow-up actions.",
    "",
    "## 1. Incident Summary",
    "",
    "| Field | Value |",
    "| --- | --- |",
    f"| Release ID | {md_cell(release_id)} |",
    f"| Release Result | {md_cell(release_result)} |",
    f"| Policy Decision | {md_cell(policy_decision)} |",
    f"| Final Action | {md_cell(final_action)} |",
    f"| Execution Mode | {md_cell(execution_mode)} |",
    f"| Requires Human Approval | {md_cell(requires_human_approval)} |",
    f"| Safe To Retry | {md_cell(safe_to_retry)} |",
    f"| Generated At | {md_cell(generated_at)} |",
    "",
    "## 2. Release Context",
    "",
    "| Field | Value |",
    "| --- | --- |",
    f"| Namespace | {md_cell(namespace)} |",
    f"| Rollout | {md_cell(rollout)} |",
    f"| AnalysisRun | {md_cell(analysis_run)} |",
    f"| Rollout Phase | {md_cell(summary.get('rolloutPhase'))} |",
    f"| Rollout Abort | {md_cell(summary.get('rolloutAbort'))} |",
    f"| AnalysisRun Phase | {md_cell(summary.get('analysisRunPhase'))} |",
    "",
    "## 3. SLO Evidence",
    "",
    "| Field | Value |",
    "| --- | --- |",
    f"| Failed Metrics | {md_cell(failed_metrics)} |",
    f"| Risk Level | {md_cell(summary.get('riskLevel'))} |",
    f"| Risk Score | {md_cell(summary.get('riskScore'))} |",
    f"| Change Risk Level | {md_cell(summary.get('changeRiskLevel'))} |",
    f"| Change Risk Score | {md_cell(summary.get('changeRiskScore'))} |",
    f"| Matched Policy Rules | {md_cell(matched_policy_rules)} |",
    "",
])

if analysis_metrics:
    lines.extend([
        "### AnalysisRun Metrics",
        "",
        "| Metric | Phase | Value | Successful | Failed | Error |",
        "| --- | --- | --- | --- | --- | --- |",
    ])
    for metric in analysis_metrics:
        lines.append(
            f"| {md_cell(metric.get('name'))} | "
            f"{md_cell(metric.get('phase'))} | "
            f"{md_cell(metric.get('value'))} | "
            f"{md_cell(metric.get('successful'))} | "
            f"{md_cell(metric.get('failed'))} | "
            f"{md_cell(metric.get('error'))} |"
        )
    lines.append("")

lines.extend([
    "## 4. Root Cause Hypothesis",
    "",
])

lines.extend(bullet_list(root_cause_hypotheses, "No root cause hypothesis available."))

lines.extend([
    "",
    "## 5. Impact Scope",
    "",
    f"- Impacted workload: **{md_cell(namespace)}/{md_cell(rollout)}**",
    f"- Impacted release path: canary rollout / AnalysisRun gate",
    f"- User impact inference: {md_cell('limited to canary traffic or stopped promotion' if release_result != 'PASS' else 'no incident impact detected')}",
    f"- Rollout protection: {md_cell('promotion stopped or guarded by policy' if final_action != 'NOOP' else 'no mitigation required')}",
    "",
    "## 6. Mitigation / Operator Action",
    "",
    f"- Recommended action: **{md_cell(final_action)}**",
    f"- Policy reason: {md_cell((evidence.get('decisionRefs') or {}).get('policyDecision', {}).get('reason') or policy_decision_doc.get('reason'))}",
    f"- AI conclusion: {md_cell(ai_decision.get('conclusion') or ai_decision.get('summary'))}",
    f"- Intelligence conclusion: {md_cell(intel.get('conclusion') or intel.get('humanSummary'))}",
    "",
    "### Candidate Commands",
    "",
    "| Name | Type | Will Execute | Command |",
    "| --- | --- | --- | --- |",
])

if candidate_commands:
    for command in candidate_commands:
        lines.append(
            f"| {md_cell(command.get('name'))} | "
            f"{md_cell(command.get('type'))} | "
            f"{md_cell(command.get('willExecute', False))} | "
            f"{code_cell(command.get('command'))} |"
        )
else:
    lines.append("| none | none | false | none |")

lines.extend([
    "",
    "## 7. Contributing Factors",
    "",
    f"- Repeated risk pattern: {md_cell(intel.get('repeatedRiskPattern'))}",
    f"- Historical record count: {md_cell(history.get('recordCount'))}",
    f"- Historical failure count: {md_cell(history.get('failureCount'))}",
    f"- Similar failure count: {md_cell(history.get('similarFailureCount'))}",
    f"- Similar failure including current count: {md_cell(history.get('similarFailureIncludingCurrentCount'))}",
    f"- Exact historical metric set match count: {md_cell(history.get('exactHistoricalMetricSetMatchCount'))}",
    "",
    "## 8. Follow-up Actions",
    "",
])

lines.extend(bullet_list(follow_ups, "No follow-up action available."))

lines.extend([
    "",
    "## 9. Evidence Links",
    "",
    "| Artifact | Path |",
    "| --- | --- |",
    f"| Source Evidence | {md_cell(str(evidence_path))} |",
    f"| AI Decision | {md_cell(ai_decision_path or artifacts.get('aiDecision'))} |",
    f"| Policy Decision | {md_cell(policy_decision_path or artifacts.get('policyDecision'))} |",
    f"| Action Plan | {md_cell(action_plan_path or artifacts.get('actionPlan'))} |",
    f"| Failure Evidence | {md_cell(failure_evidence_path or artifacts.get('failureEvidence'))} |",
    f"| Release Intelligence | {md_cell(intelligence_path or artifacts.get('releaseIntelligence'))} |",
])

for name, path in sorted(artifacts.items()):
    lines.append(f"| {md_cell(name)} | {md_cell(path)} |")

lines.extend([
    "",
    "## 10. Safety Notes",
    "",
    "- This RCA is generated for operator review and post-incident analysis.",
    "- It does not execute any command.",
    "- Any write action must be reviewed by a human operator.",
    "- Evidence is treated as the source of truth when linked artifacts disagree.",
    "",
])

output_md.write_text("\n".join(lines), encoding="utf-8")
shutil.copyfile(output_md, latest_md)
PY

echo "Generated release RCA markdown: $OUTPUT_MD"
echo "Updated latest release RCA markdown: $LATEST_MD"
