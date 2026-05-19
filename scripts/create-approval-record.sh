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

python3 - "$ACTION_PLAN_FILE" "$OUTPUT_JSON" "$OUTPUT_MD" "$LATEST_JSON" "$LATEST_MD" "$APPROVAL_DECISION" "$APPROVAL_REASON" "$APPROVER" <<'CREATE_APPROVAL_RECORD_PY'
import json
import shutil
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
