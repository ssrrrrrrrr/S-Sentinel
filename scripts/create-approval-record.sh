#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-}"
ACTION_PLAN_FILE="${1:-latest}"
APPROVAL_DECISION="${2:-}"
APPROVAL_REASON="${3:-}"
APPROVER="${APPROVER:-manual}"

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
  scripts/create-approval-record.sh [latest|ACTION_PLAN_JSON] <APPROVAL_DECISION> [REASON]

Approval decisions:
  APPROVED
  REJECTED
  DEFERRED
  NEEDS_MORE_EVIDENCE

Examples:
  scripts/create-approval-record.sh latest APPROVED "确认停止继续放量"
  scripts/create-approval-record.sh latest REJECTED "认为本次是样本不足"
  scripts/create-approval-record.sh latest DEFERRED "继续观察 10 分钟"
  scripts/create-approval-record.sh latest NEEDS_MORE_EVIDENCE "需要补充 Pod 日志和事件"

Environment:
  RELEASE_REPORT_DIR       Optional report directory.
  APPROVER                 Optional approver name. Defaults to manual.
  APPROVAL_OUTPUT_DIR      Optional output directory. Defaults to action plan directory.

Behavior:
  - Generates approval-record-*.json and approval-record-*.md.
  - Records human decision for an existing dry-run Action Plan.
  - Links approval record back into source release evidence when available.
  - Does not execute kubectl, rollback, promote, patch, delete, GitOps changes, image builds, commits, or pushes.
USAGE
}

if [ "$ACTION_PLAN_FILE" = "-h" ] || [ "$ACTION_PLAN_FILE" = "--help" ]; then
  usage
  exit 0
fi

if [ -z "$APPROVAL_DECISION" ]; then
  echo "ERROR: approval decision is required" >&2
  usage >&2
  exit 1
fi

case "$APPROVAL_DECISION" in
  APPROVED|REJECTED|DEFERRED|NEEDS_MORE_EVIDENCE)
    ;;
  *)
    echo "ERROR: unsupported approval decision: $APPROVAL_DECISION" >&2
    echo "Supported: APPROVED, REJECTED, DEFERRED, NEEDS_MORE_EVIDENCE" >&2
    exit 1
    ;;
esac

if [ "$ACTION_PLAN_FILE" = "latest" ] || [ -z "$ACTION_PLAN_FILE" ]; then
  ACTION_PLAN_FILE="$(ls -t "$REPORT_DIR"/action-plan-*.json 2>/dev/null | grep -v 'action-plan-latest.json' | head -1 || true)"
fi

if [ -z "$ACTION_PLAN_FILE" ] || [ ! -f "$ACTION_PLAN_FILE" ]; then
  echo "ERROR: action plan file does not exist: ${ACTION_PLAN_FILE:-not provided}" >&2
  exit 1
fi

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

OUTPUT_DIR="${APPROVAL_OUTPUT_DIR:-$(dirname "$ACTION_PLAN_FILE")}"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$ACTION_PLAN_FILE")"
SUFFIX="${BASENAME#action-plan-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_JSON="$OUTPUT_DIR/approval-record-$SUFFIX"
OUTPUT_MD="$OUTPUT_DIR/approval-record-${SUFFIX%.json}.md"
LATEST_JSON="$OUTPUT_DIR/approval-record-latest.json"
LATEST_MD="$OUTPUT_DIR/approval-record-latest.md"

"$PYTHON_BIN" - "$ACTION_PLAN_FILE" "$OUTPUT_JSON" "$OUTPUT_MD" "$LATEST_JSON" "$LATEST_MD" "$APPROVAL_DECISION" "$APPROVAL_REASON" "$APPROVER" <<'CREATE_APPROVAL_RECORD_PY'
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

action_plan_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
output_md = Path(sys.argv[3])
latest_json = Path(sys.argv[4])
latest_md = Path(sys.argv[5])
approval_decision = sys.argv[6]
approval_reason = sys.argv[7] or "not provided"
approver = sys.argv[8] or "manual"

action_plan = json.loads(action_plan_path.read_text(encoding="utf-8"))

action_plan_body = action_plan.get("actionPlan") or {}
candidate_commands = action_plan_body.get("candidateCommands") or []
final_action = action_plan.get("finalAction", "UNKNOWN")

approved_action = final_action if approval_decision == "APPROVED" else "NONE"

approval_status_map = {
    "APPROVED": "APPROVED",
    "REJECTED": "REJECTED",
    "DEFERRED": "DEFERRED",
    "NEEDS_MORE_EVIDENCE": "NEEDS_MORE_EVIDENCE",
}

lifecycle_stage_map = {
    "APPROVED": "READY_TO_EXECUTE",
    "REJECTED": "REJECTED",
    "DEFERRED": "DEFERRED",
    "NEEDS_MORE_EVIDENCE": "NEEDS_MORE_EVIDENCE",
}

record = {
    "schemaVersion": "release.approval/v1alpha1",
    "generatedBy": "create-approval-record.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "sourceActionPlan": str(action_plan_path),
    "sourceReleaseEvidence": action_plan.get("sourceReleaseEvidence"),
    "approvalDecision": approval_decision,
    "approvedAction": approved_action,
    "executionMode": "approval_record_only",
    "willExecute": False,
    "approver": approver,
    "reason": approval_reason,
    "release": {
        "releaseResult": action_plan.get("releaseResult", "UNKNOWN"),
        "policyDecision": action_plan.get("policyDecision", "UNKNOWN"),
        "finalAction": final_action,
        "requiresHumanApproval": bool(action_plan.get("requiresHumanApproval", False)),
        "sourceExecutionMode": action_plan.get("sourceExecutionMode", "unknown"),
    },
    "target": action_plan.get("target") or {},
    "actionPlan": {
        "action": action_plan_body.get("action", final_action),
        "blocked": bool(action_plan_body.get("blocked", False)),
        "blockReason": action_plan_body.get("blockReason", ""),
        "candidateCommandCount": len(candidate_commands),
        "candidateCommands": candidate_commands,
    },
    "approvalSemantics": {
        "approvedMeans": "human agrees with the recommended action, but the platform still does not execute it",
        "rejectedMeans": "human rejects the recommended action",
        "deferredMeans": "human postpones the decision and continues observation",
        "needsMoreEvidenceMeans": "human requires more logs, events, metrics, or change evidence before deciding",
    },
    "guardrails": {
        "approvalRecordOnly": True,
        "advisoryOnly": True,
        "doesNotModifyGitOps": True,
        "doesNotModifyKubernetes": True,
        "doesNotRollback": True,
        "doesNotPromote": True,
        "doesNotPatchResources": True,
        "doesNotDeleteResources": True,
        "doesNotBuildImages": True,
        "doesNotCommitOrPush": True,
        "willExecute": False,
    },
}

output_json.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

commands_md = ""
for cmd in candidate_commands:
    commands_md += (
        f"- `{cmd.get('command', '')}`\n"
        f"  - 类型：`{cmd.get('type', 'unknown')}`\n"
        f"  - 是否执行：`false`\n"
    )

if not commands_md:
    commands_md = "无候选命令。\n"

md = f"""<!--
Generated by create-approval-record.sh
Source action plan: {action_plan_path}
-->

# Human Approval Record

## 1. 审批结论

- Approval Decision：`{approval_decision}`
- Approved Action：`{approved_action}`
- Execution Mode：`approval_record_only`
- Will Execute：`false`
- Approver：`{approver}`
- Reason：{approval_reason}

## 2. 关联发布

- Release Result：`{record["release"]["releaseResult"]}`
- Policy Decision：`{record["release"]["policyDecision"]}`
- Final Action：`{record["release"]["finalAction"]}`
- Requires Human Approval：`{str(record["release"]["requiresHumanApproval"]).lower()}`
- Source Action Plan：`{action_plan_path}`
- Source Release Evidence：`{record["sourceReleaseEvidence"]}`

## 3. 目标对象

- Namespace：`{record["target"].get("namespace", "unknown")}`
- Rollout：`{record["target"].get("rollout", "unknown")}`
- AnalysisRun：`{record["target"].get("analysisRun", "unknown")}`

## 4. 候选命令

{commands_md}

## 5. 审批语义

- `APPROVED`：人工认可建议动作，但平台仍然不会自动执行。
- `REJECTED`：人工拒绝建议动作。
- `DEFERRED`：人工暂不决策，继续观察。
- `NEEDS_MORE_EVIDENCE`：人工认为证据不足，需要补充日志、事件、指标或变更证据。

## 6. 安全边界

本审批记录只用于审计留痕，不会自动执行 Rollback、Promote、Patch、Delete、GitOps 变更、镜像构建、Commit 或 Push。
"""

output_md.write_text(md, encoding="utf-8")
shutil.copyfile(output_md, latest_md)

def resolve_release_evidence(ref):
    if not ref:
        return None

    p = Path(str(ref))
    candidates = []

    if p.is_absolute():
        candidates.append(p)

    candidates.append(action_plan_path.parent / p.name)
    candidates.append(output_json.parent / p.name)
    candidates.append(p)

    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate

    return None

release_evidence_path = resolve_release_evidence(record.get("sourceReleaseEvidence"))

def resolve_execution_request(release_evidence_path, release_evidence):
    if not release_evidence_path or not isinstance(release_evidence, dict):
        return None

    artifacts = release_evidence.get("artifacts") or {}
    execution_request_ref = artifacts.get("executionRequest")
    if not execution_request_ref:
        return None

    p = Path(str(execution_request_ref))
    candidates = []

    if p.is_absolute():
        candidates.append(p)

    candidates.append(release_evidence_path.parent / p.name)
    candidates.append(output_json.parent / p.name)
    candidates.append(p)

    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate

    return None

def resolve_artifact_from_evidence(ref, evidence_path):
    if not ref:
        return None

    p = Path(str(ref))
    candidates = []

    if p.is_absolute():
        candidates.append(p)

    candidates.append(evidence_path.parent / p.name)
    candidates.append(p)

    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate

    return None

def find_summary_builder():
    for candidate in [Path("./scripts/build-release-summary.sh"), Path("/app/scripts/build-release-summary.sh")]:
        if candidate.exists() and os.access(candidate, os.X_OK):
            return candidate
    return None

def find_bash():
    candidates = [
        os.environ.get("S_SENTINEL_BASH_BIN"),
        r"D:\Git\bin\bash.exe",
        r"D:\Git\usr\bin\bash.exe",
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    return None

def rebuild_release_summary(evidence_path):
    builder = find_summary_builder()
    if not builder:
        print("WARN: release summary builder not found, skip approval summary update", file=sys.stderr)
        return

    env = os.environ.copy()
    env["RELEASE_REPORT_DIR"] = str(evidence_path.parent)

    command = [str(builder), str(evidence_path)]
    if os.name == "nt" and builder.suffix == ".sh":
        bash = find_bash()
        if bash:
            command = [bash, str(builder), str(evidence_path)]

    result = subprocess.run(command, env=env, text=True, capture_output=True, errors="replace")

    if result.returncode == 0:
        print(f"Release summary rebuilt with approval record: {evidence_path}")
    else:
        print(f"WARN: failed to rebuild release summary with approval record: {result.stderr}", file=sys.stderr)

def append_approval_to_ai_advice(evidence_path, release_evidence):
    artifacts = release_evidence.get("artifacts") or {}
    advice_path = resolve_artifact_from_evidence(artifacts.get("aiAdvice"), evidence_path)

    if not advice_path:
        print("WARN: AI advice file not found, skip approval summary in AI advice", file=sys.stderr)
        return

    current_text = advice_path.read_text(encoding="utf-8") if advice_path.exists() else ""
    if "## 10. Human Approval Record" in current_text:
        print(f"Human approval record already exists in AI advice: {advice_path}")
        return

    approval_report = artifacts.get("approvalRecordReport") or str(output_md)

    section = f"""

## 10. Human Approval Record

- Approval Decision: `{approval_decision}`
- Approved Action: `{approved_action}`
- Execution Mode: `approval_record_only`
- Will Execute: `false`
- Approver: `{approver}`
- Reason: {approval_reason}

### Approval Artifacts

- Approval Record JSON: `{output_json}`
- Approval Record Report: `{approval_report}`

### Safety Boundary

This approval record is audit-only. It does not execute Rollback, Promote, Patch, Delete, GitOps changes, image builds, commits, or pushes.
"""

    with advice_path.open("a", encoding="utf-8") as f:
        f.write(section)

    print(f"Human approval record appended to AI advice: {advice_path}")

if release_evidence_path:
    try:
        release_evidence = json.loads(release_evidence_path.read_text(encoding="utf-8"))
        execution_request_path = resolve_execution_request(release_evidence_path, release_evidence)
        execution_request = {}

        if execution_request_path:
            execution_request = json.loads(execution_request_path.read_text(encoding="utf-8"))
            request_body = execution_request.setdefault("request", {})
            approval_body = execution_request.setdefault("approval", {})
            evidence_body = execution_request.setdefault("evidence", {})
            evidence_artifacts = evidence_body.setdefault("artifacts", {})

            approval_status = approval_status_map.get(approval_decision, "NOT_APPROVED")
            lifecycle_stage = lifecycle_stage_map.get(approval_decision, request_body.get("lifecycleStage"))
            ready_to_execute = approval_decision == "APPROVED"

            request_body["lifecycleStage"] = lifecycle_stage

            approval_body["required"] = bool(approval_body.get("required", True))
            approval_body["status"] = approval_status
            approval_body["approved"] = ready_to_execute
            approval_body["approvalDecision"] = approval_decision
            approval_body["approver"] = approver
            approval_body["reason"] = approval_reason
            approval_body["updatedAt"] = datetime.now(timezone.utc).isoformat()
            approval_body["readyToExecute"] = ready_to_execute
            approval_body["willExecuteAfterApproval"] = False

            evidence_body["approvalRecord"] = str(output_json)
            evidence_body["approvalRecordReport"] = str(output_md)
            evidence_artifacts["approvalRecord"] = str(output_json)
            evidence_artifacts["approvalRecordReport"] = str(output_md)

            execution_request_path.write_text(json.dumps(execution_request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(f"Execution request updated with approval outcome: {execution_request_path}")

            record["sourceExecutionRequest"] = str(execution_request_path)
            record["executionRequestId"] = execution_request.get("executionRequestId")

        artifacts = release_evidence.setdefault("artifacts", {})
        artifacts["approvalRecord"] = str(output_json)
        artifacts["approvalRecordReport"] = str(output_md)

        release_evidence["approvalRef"] = {
            "generated": True,
            "decision": approval_decision,
            "approvedAction": approved_action,
            "executionMode": "approval_record_only",
            "willExecute": False,
            "approver": approver,
            "executionRequestId": record.get("executionRequestId"),
            "sourceExecutionRequest": record.get("sourceExecutionRequest"),
            "readyToExecute": approval_decision == "APPROVED",
            "json": str(output_json),
            "markdown": str(output_md),
        }

        if execution_request:
            request_body = execution_request.get("request") or {}
            approval_body = execution_request.get("approval") or {}
            policy_binding = execution_request.get("policyBinding") or {}

            release_evidence["executionRequestId"] = execution_request.get("executionRequestId")
            decision_refs = release_evidence.setdefault("decisionRefs", {})
            decision_refs["executionRequest"] = {
                "executionRequestId": execution_request.get("executionRequestId"),
                "sourcePlanRunId": execution_request.get("sourcePlanRunId"),
                "mode": execution_request.get("mode"),
                "requestedAction": request_body.get("requestedAction"),
                "requestStatus": request_body.get("requestStatus"),
                "lifecycleStage": request_body.get("lifecycleStage"),
                "policyDecision": policy_binding.get("policyDecision"),
                "requiresHumanApproval": policy_binding.get("requiresHumanApproval"),
                "approvalStatus": approval_body.get("status"),
                "approved": approval_body.get("approved"),
                "approvalDecision": approval_body.get("approvalDecision"),
                "approvalReason": approval_body.get("reason"),
                "approver": approval_body.get("approver"),
                "readyToExecute": approval_body.get("readyToExecute"),
                "approvalRecord": str(output_json),
                "approvalRecordReport": str(output_md),
                "willExecute": execution_request.get("guardrails", {}).get("willExecute"),
                "guardrails": execution_request.get("guardrails") or {},
            }

        release_evidence_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Approval record linked into release evidence: {release_evidence_path}")

        rebuild_release_summary(release_evidence_path)
        append_approval_to_ai_advice(release_evidence_path, release_evidence)
    except Exception as exc:
        print(f"WARN: failed to link approval record into release evidence: {release_evidence_path}: {exc}", file=sys.stderr)
else:
    print(f"WARN: source release evidence not found, skip linking approval record: {record.get('sourceReleaseEvidence')}", file=sys.stderr)

output_json.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Approval record JSON generated: {output_json}")
print(f"Approval record Markdown generated: {output_md}")
print(f"Latest approval record JSON: {latest_json}")
print(f"Latest approval record Markdown: {latest_md}")
print(json.dumps({
    "approvalDecision": approval_decision,
    "approvedAction": approved_action,
    "executionMode": "approval_record_only",
    "willExecute": False,
    "releaseResult": record["release"]["releaseResult"],
    "finalAction": final_action,
    "candidateCommandCount": len(candidate_commands),
}, ensure_ascii=False, indent=2))
CREATE_APPROVAL_RECORD_PY
