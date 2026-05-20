#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
RELEASE_EVIDENCE_FILE="${1:-latest}"

if [ "$RELEASE_EVIDENCE_FILE" = "-h" ] || [ "$RELEASE_EVIDENCE_FILE" = "--help" ]; then
  cat <<'USAGE'
Usage:
  scripts/build-release-runbook.sh [latest|RELEASE_EVIDENCE_JSON]

Behavior:
  - Builds an operator-facing Markdown runbook from release evidence.
  - Reads action-plan and intelligence artifacts when they are available.
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

OUTPUT_DIR="${RUNBOOK_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$RELEASE_EVIDENCE_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_MD="$OUTPUT_DIR/runbook-${SUFFIX%.json}.md"
LATEST_MD="$OUTPUT_DIR/runbook-latest.md"

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
    command_text = html.escape(scalar(command))
    return f"<code>{command_text}</code>"

def default_human_steps(release_result: str, final_action: str, requires_approval: bool) -> list[str]:
    steps = [
        "?? stable ????????????????",
        "?? canary ????????AnalysisRun ??????????",
        "????????? SLO ??????????????",
    ]

    if final_action in {"STOP_PROMOTION", "ABORT_ROLLOUT"}:
        steps.append("?????? canary ????????????????")

    if requires_approval:
        steps.append("???????????????????")

    if release_result == "PASS":
        return ["???????????????????????"]

    return steps

def default_commands(namespace: str, rollout: str, analysis_run: str, final_action: str) -> list[dict[str, Any]]:
    ns = namespace if namespace and namespace != "unknown" else "<namespace>"
    ro = rollout if rollout and rollout != "unknown" else "<rollout>"

    commands = [
        {
            "name": "inspect_rollout",
            "type": "read_only",
            "willExecute": False,
            "command": f"kubectl argo rollouts get rollout {ro} -n {ns}",
        },
        {
            "name": "inspect_rollout_events",
            "type": "read_only",
            "willExecute": False,
            "command": f"kubectl describe rollout {ro} -n {ns}",
        },
    ]

    if analysis_run and analysis_run != "unknown":
        commands.append({
            "name": "inspect_analysis_run",
            "type": "read_only",
            "willExecute": False,
            "command": f"kubectl get analysisrun {analysis_run} -n {ns} -o yaml",
        })

    if final_action in {"STOP_PROMOTION", "ABORT_ROLLOUT"}:
        commands.append({
            "name": "candidate_abort_rollout",
            "type": "write_candidate_requires_human_approval",
            "willExecute": False,
            "command": f"kubectl argo rollouts abort {ro} -n {ns}",
        })

    return commands

evidence = load_json(evidence_path)
artifacts = evidence.get("artifacts") or {}

action_plan, action_plan_path = load_ref(
    artifacts.get("actionPlan") or (evidence.get("actionPlanRef") or {}).get("json"),
    evidence_path,
)
intelligence, intelligence_path = load_ref(
    artifacts.get("releaseIntelligence") or (evidence.get("releaseIntelligenceRef") or {}).get("json"),
    evidence_path,
)
failure_evidence, failure_evidence_path = load_ref(
    artifacts.get("failureEvidence") or (evidence.get("failureEvidenceRef") or {}).get("json"),
    evidence_path,
)

release_id = output_md.stem.replace("runbook-", "")
generated_at = datetime.now(timezone.utc).isoformat()

release_result = evidence.get("releaseResult", "UNKNOWN")
policy_decision = evidence.get("policyDecision", "UNKNOWN")
final_action = evidence.get("finalAction", "UNKNOWN")
execution_mode = evidence.get("executionMode", "unknown")
requires_human_approval = bool(evidence.get("requiresHumanApproval", False))
safe_to_retry = evidence.get("safeToRetry", "unknown")

summary = evidence.get("summary") or {}
decision_refs = evidence.get("decisionRefs") or {}
ai_decision_ref = decision_refs.get("aiDecision") or {}
policy_decision_ref = decision_refs.get("policyDecision") or {}

action_plan_body = action_plan.get("actionPlan") or {}
target = action_plan.get("target") or {}

namespace = target.get("namespace") or "unknown"
rollout = target.get("rollout") or "unknown"
analysis_run = target.get("analysisRun") or "unknown"

candidate_commands = action_plan_body.get("candidateCommands") or []
human_steps = action_plan_body.get("humanSteps") or default_human_steps(
    release_result,
    final_action,
    requires_human_approval,
)

if not candidate_commands:
    candidate_commands = default_commands(namespace, rollout, analysis_run, final_action)

guardrails = action_plan.get("guardrails") or {
    "advisoryOnly": True,
    "dryRunOnly": True,
    "doesNotModifyGitOps": True,
    "doesNotModifyKubernetes": True,
    "doesNotRollback": True,
    "doesNotPromote": True,
    "doesNotPatchResources": True,
    "doesNotDeleteResources": True,
    "doesNotBuildImages": True,
    "doesNotCommitOrPush": True,
}

history = intelligence.get("history") or {}
intel = intelligence.get("intelligence") or {}

lines: list[str] = []

lines.extend([
    f"# Release Runbook: {release_id}",
    "",
    "> This runbook is generated from release evidence. It is advisory by default and does not execute any command.",
    "",
    "## 1. Release Status",
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
    "## 2. Target",
    "",
    "| Field | Value |",
    "| --- | --- |",
    f"| Namespace | {md_cell(namespace)} |",
    f"| Rollout | {md_cell(rollout)} |",
    f"| AnalysisRun | {md_cell(analysis_run)} |",
    "",
    "## 3. Triage Summary",
    "",
    "| Field | Value |",
    "| --- | --- |",
    f"| Rollout Phase | {md_cell(summary.get('rolloutPhase'))} |",
    f"| Rollout Abort | {md_cell(summary.get('rolloutAbort'))} |",
    f"| AnalysisRun Phase | {md_cell(summary.get('analysisRunPhase'))} |",
    f"| Risk Level | {md_cell(summary.get('riskLevel'))} |",
    f"| Risk Score | {md_cell(summary.get('riskScore'))} |",
    f"| Change Risk Level | {md_cell(summary.get('changeRiskLevel'))} |",
    f"| Change Risk Score | {md_cell(summary.get('changeRiskScore'))} |",
    f"| Failed Metrics | {md_cell(summary.get('failedMetrics') or [])} |",
    f"| Matched Policy Rules | {md_cell(summary.get('matchedPolicyRules') or [])} |",
    "",
    "## 4. Recommended Operator Action",
    "",
    f"- Recommended action: **{md_cell(final_action)}**",
    f"- Policy decision: **{md_cell(policy_decision)}**",
    f"- Execution mode: **{md_cell(execution_mode)}**",
    f"- Human approval required: **{md_cell(requires_human_approval)}**",
    f"- AI decision source: **{md_cell(ai_decision_ref.get('decisionSource'))}**",
    f"- AI confidence: **{md_cell(ai_decision_ref.get('confidence'))}**",
    f"- Policy reason: {md_cell(policy_decision_ref.get('reason'))}",
    "",
    "## 5. Human Checklist",
    "",
])

lines.extend(bullet_list(human_steps, "No manual step provided."))

lines.extend([
    "",
    "## 6. Command Reference",
    "",
    "| Name | Type | Will Execute | Command |",
    "| --- | --- | --- | --- |",
])

for command in candidate_commands:
    lines.append(
        f"| {md_cell(command.get('name'))} | "
        f"{md_cell(command.get('type'))} | "
        f"{md_cell(command.get('willExecute', False))} | "
        f"{code_cell(command.get('command'))} |"
    )

lines.extend([
    "",
    "## 7. Guardrails",
    "",
    "| Guardrail | Value |",
    "| --- | --- |",
])

for key in sorted(guardrails.keys()):
    lines.append(f"| {md_cell(key)} | {md_cell(guardrails.get(key))} |")

lines.extend([
    "",
    "## 8. Evidence Links",
    "",
    "| Artifact | Path |",
    "| --- | --- |",
    f"| Source Evidence | {md_cell(str(evidence_path))} |",
    f"| Action Plan | {md_cell(action_plan_path or artifacts.get('actionPlan'))} |",
    f"| Release Intelligence | {md_cell(intelligence_path or artifacts.get('releaseIntelligence'))} |",
    f"| Failure Evidence | {md_cell(failure_evidence_path or artifacts.get('failureEvidence'))} |",
])

for name, path in sorted(artifacts.items()):
    lines.append(f"| {md_cell(name)} | {md_cell(path)} |")

lines.extend([
    "",
    "## 9. RCA Input Notes",
    "",
    f"- Historical similar releases: {md_cell(history.get('similarReleaseCount'))}",
    f"- Historical failed release count: {md_cell(history.get('failedReleaseCount'))}",
    f"- Intelligence risk level: {md_cell(intel.get('riskLevel'))}",
    f"- Intelligence summary: {md_cell(intel.get('summary'))}",
    "",
    "## 10. Safety Statement",
    "",
    "- This runbook is generated for operator review.",
    "- It does not execute remediation automatically.",
    "- Any write command must be reviewed by a human operator before execution.",
    "",
])

output_md.write_text("\n".join(lines), encoding="utf-8")
shutil.copyfile(output_md, latest_md)
PY

echo "Generated release runbook markdown: $OUTPUT_MD"
echo "Updated latest release runbook markdown: $LATEST_MD"
