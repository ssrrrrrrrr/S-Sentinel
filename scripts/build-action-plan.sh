#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
RELEASE_EVIDENCE_FILE="${1:-latest}"

if [ "$RELEASE_EVIDENCE_FILE" = "-h" ] || [ "$RELEASE_EVIDENCE_FILE" = "--help" ]; then
  cat <<'USAGE'
Usage:
  scripts/build-action-plan.sh [latest|RELEASE_EVIDENCE_JSON]

Behavior:
  - Builds dry-run action-plan JSON/Markdown from release evidence.
  - Never executes rollback, promote, patch, delete, kubectl, GitOps, image build, commit, or push.
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

OUTPUT_DIR="${ACTION_PLAN_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$RELEASE_EVIDENCE_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_JSON="$OUTPUT_DIR/action-plan-$SUFFIX"
OUTPUT_MD="$OUTPUT_DIR/action-plan-${SUFFIX%.json}.md"
LATEST_JSON="$OUTPUT_DIR/action-plan-latest.json"
LATEST_MD="$OUTPUT_DIR/action-plan-latest.md"

python3 - "$RELEASE_EVIDENCE_FILE" "$OUTPUT_JSON" "$OUTPUT_MD" "$LATEST_JSON" "$LATEST_MD" <<'PY'
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

evidence_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
output_md = Path(sys.argv[3])
latest_json = Path(sys.argv[4])
latest_md = Path(sys.argv[5])

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))

artifacts = evidence.get("artifacts") or {}
release_context_path = artifacts.get("releaseContext")
release_context = {}

if release_context_path and Path(release_context_path).exists():
    try:
        release_context = json.loads(Path(release_context_path).read_text(encoding="utf-8"))
    except Exception:
        release_context = {}

release_result = evidence.get("releaseResult", "UNKNOWN")
policy_decision = evidence.get("policyDecision", "UNKNOWN")
final_action = evidence.get("finalAction", "UNKNOWN")
source_execution_mode = evidence.get("executionMode", "unknown")
requires_human_approval = bool(evidence.get("requiresHumanApproval", False))

namespace = release_context.get("namespace") or "unknown"
rollout = release_context.get("rollout") or "unknown"
analysis_run = release_context.get("analysisRun") or "unknown"

blocked_actions = {
    "ROLLBACK",
    "PROMOTE",
    "DELETE_RESOURCE",
    "PATCH_RESOURCE",
    "APPLY_MANIFEST",
    "PATCH_GITOPS",
    "SCALE_DOWN",
    "RESTART_WORKLOAD",
}

blocked = False
block_reason = ""
candidate_commands = []
human_steps = []

if policy_decision == "BLOCKED":
    blocked = True
    block_reason = "Policy decision is BLOCKED"
elif final_action in blocked_actions:
    blocked = True
    block_reason = f"{final_action} is blocked by policy"

if final_action == "NOOP":
    human_steps = ["无需执行动作，归档发布记录并继续观察。"]
elif final_action == "STOP_PROMOTION" and not blocked:
    human_steps = [
        "停止继续扩大流量。",
        "人工检查 canary 版本日志、事件、AnalysisRun 指标和本次变更内容。",
        "确认原因后发布修复版本，或由人工决定是否中止 Rollout。"
    ]
    candidate_commands = [
        {
            "name": "inspect_rollout",
            "command": f"kubectl argo rollouts get rollout {rollout} -n {namespace}",
            "type": "read_only",
            "willExecute": False,
        },
        {
            "name": "inspect_analysis_run",
            "command": f"kubectl get analysisrun {analysis_run} -n {namespace} -o yaml",
            "type": "read_only",
            "willExecute": False,
        },
        {
            "name": "candidate_abort_rollout",
            "command": f"kubectl argo rollouts abort {rollout} -n {namespace}",
            "type": "write_candidate_requires_human_approval",
            "willExecute": False,
        },
    ]
elif blocked:
    human_steps = [
        f"策略已阻断动作 {final_action}。",
        "不得由 Agent 自动执行该动作。",
        "需要人工根据证据链重新评估。"
    ]
else:
    human_steps = [
        f"动作 {final_action} 仅生成 dry-run 计划。",
        "需要人工确认下一步。"
    ]

plan = {
    "schemaVersion": "release.action-plan/v1alpha1",
    "generatedBy": "build-action-plan.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "sourceReleaseEvidence": str(evidence_path),
    "releaseResult": release_result,
    "policyDecision": policy_decision,
    "finalAction": final_action,
    "executionMode": "dry_run",
    "sourceExecutionMode": source_execution_mode,
    "willExecute": False,
    "requiresHumanApproval": requires_human_approval,
    "target": {
        "namespace": namespace,
        "rollout": rollout,
        "analysisRun": analysis_run,
    },
    "actionPlan": {
        "action": final_action,
        "blocked": blocked,
        "blockReason": block_reason,
        "candidateCommands": candidate_commands,
        "humanSteps": human_steps,
    },
    "guardrails": {
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
    },
}

output_json.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

commands_md = ""
for cmd in candidate_commands:
    commands_md += f"- `{cmd['command']}`\n  - 类型：`{cmd['type']}`\n  - 是否执行：`false`\n"

if not commands_md:
    commands_md = "无候选命令。\n"

steps_md = "\n".join([f"- {step}" for step in human_steps]) or "- 无"

md = f"""<!--
Generated by build-action-plan.sh
Source release evidence: {evidence_path}
-->

# Dry-run 动作计划

## 1. 最终动作

- 发布结果：`{release_result}`
- 策略裁决：`{policy_decision}`
- 建议动作：`{final_action}`
- 执行模式：`dry_run`
- 原始执行模式：`{source_execution_mode}`
- 是否真实执行：`false`
- 是否需要人工审批：`{str(requires_human_approval).lower()}`
- 是否被策略阻断：`{str(blocked).lower()}`

## 2. 目标对象

- Namespace：`{namespace}`
- Rollout：`{rollout}`
- AnalysisRun：`{analysis_run}`

## 3. 候选命令

{commands_md}

## 4. 人工步骤

{steps_md}

## 5. 安全边界

本动作计划只用于 dry-run 审计和人工评估，不会自动执行 Rollback、Promote、Patch、Delete、GitOps 变更、镜像构建、Commit 或 Push。
"""

output_md.write_text(md, encoding="utf-8")
shutil.copyfile(output_md, latest_md)

print(f"Action plan JSON generated: {output_json}")
print(f"Action plan Markdown generated: {output_md}")
print(f"Latest action plan JSON: {latest_json}")
print(f"Latest action plan Markdown: {latest_md}")
print(json.dumps({
    "releaseResult": release_result,
    "policyDecision": policy_decision,
    "finalAction": final_action,
    "executionMode": "dry_run",
    "willExecute": False,
    "blocked": blocked,
    "candidateCommandCount": len(candidate_commands),
}, ensure_ascii=False, indent=2))
PY
