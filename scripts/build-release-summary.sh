#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
EVIDENCE_FILE="${1:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-release-summary.sh [RELEASE_EVIDENCE_JSON]

Examples:
  scripts/build-release-summary.sh
  scripts/build-release-summary.sh docs/release-reports/release-evidence-20260518-140212.json

Behavior:
  - If RELEASE_EVIDENCE_JSON is omitted, the latest docs/release-reports/release-evidence-*.json is used.
  - The output is written to docs/release-reports/release-summary-*.md.
  - This script only builds a human-readable Chinese summary. It does not modify Rollouts, GitOps manifests, or Kubernetes resources.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ -z "$EVIDENCE_FILE" ]; then
  EVIDENCE_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | head -1 || true)"
fi

if [ -z "$EVIDENCE_FILE" ]; then
  echo "ERROR: no release-evidence-*.json found under $REPORT_DIR" >&2
  exit 1
fi

if [ ! -f "$EVIDENCE_FILE" ]; then
  echo "ERROR: release evidence file does not exist: $EVIDENCE_FILE" >&2
  exit 1
fi

EVIDENCE_BASENAME="$(basename "$EVIDENCE_FILE")"
EVIDENCE_SUFFIX="${EVIDENCE_BASENAME#release-evidence-}"
OUTPUT_FILE="$REPORT_DIR/release-summary-${EVIDENCE_SUFFIX%.json}.md"

python3 - "$EVIDENCE_FILE" "$OUTPUT_FILE" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

data = json.loads(evidence_path.read_text(encoding="utf-8"))

summary = data.get("summary") or {}
artifacts = data.get("artifacts") or {}
decision_refs = data.get("decisionRefs") or {}
ai_decision_ref = decision_refs.get("aiDecision") or {}
policy_decision_ref = decision_refs.get("policyDecision") or {}
release_intelligence_ref = data.get("releaseIntelligenceRef") or {}
approval_ref = data.get("approvalRef") or {}

def resolve_artifact_path(ref):
    if not ref:
        return None

    candidate = Path(str(ref))
    candidates = []

    if candidate.is_absolute():
        candidates.append(candidate)

    candidates.append(evidence_path.parent / candidate.name)
    candidates.append(candidate)

    for item in candidates:
        if item.exists() and item.is_file():
            return item

    return None

def load_release_intelligence():
    ref = artifacts.get("releaseIntelligence") or release_intelligence_ref.get("json")
    path = resolve_artifact_path(ref)

    if not path:
        return None, {}

    try:
        return path, json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return path, {}

def load_approval_record():
    ref = artifacts.get("approvalRecord") or approval_ref.get("json")
    path = resolve_artifact_path(ref)

    if not path:
        return None, {}

    try:
        return path, json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return path, {}

release_intelligence_path, release_intelligence = load_release_intelligence()
approval_record_path, approval_record = load_approval_record()

release_result = data.get("releaseResult", "UNKNOWN")
policy_decision = data.get("policyDecision", "UNKNOWN")
final_action = data.get("finalAction", "UNKNOWN")
execution_mode = data.get("executionMode", "unknown")
requires_human_approval = bool(data.get("requiresHumanApproval", False))
safe_to_retry = bool(data.get("safeToRetry", False))

failed_metrics = summary.get("failedMetrics") or []
matched_rules = summary.get("matchedPolicyRules") or []
raw_policy_reason = policy_decision_ref.get("reason") or "未提供"

def display(value, default="未提供") -> str:
    if value is None:
        return default
    if isinstance(value, str) and value.strip().lower() in ("", "none", "null"):
        return default
    return str(value)

def display_bool(value) -> str:
    if value is None:
        return "未提供"
    return str(bool(value)).lower()

def yes_no(value: bool) -> str:
    return "是" if value else "否"

def translate_reason(reason: str) -> str:
    mapping = {
        "Release passed and no action is required": "发布已通过，不需要执行任何动作。",
        "Release failed; stop promotion is advisory only and requires human approval": "发布失败，建议停止继续扩大流量；该动作仅作为建议，需要人工审批。",
        "Multiple SLO gates failed; action is advisory only and requires human approval": "多个 SLO 门禁失败，建议停止发布；该动作仅作为建议，需要人工审批。",
        "ROLLBACK is blocked by default safety policy": "默认安全策略已阻断 ROLLBACK 动作。",
        "PROMOTE is blocked by default safety policy": "默认安全策略已阻断 PROMOTE 动作。",
        "DELETE_RESOURCE is blocked by default safety policy": "默认安全策略已阻断删除资源动作。",
        "PATCH_RESOURCE is blocked by default safety policy": "默认安全策略已阻断修改资源动作。",
        "APPLY_MANIFEST is blocked by default safety policy": "默认安全策略已阻断应用 Manifest 动作。",
        "Release failed SLO gates and requires human investigation": "发布未通过 SLO 门禁，需要人工排查。",
        "Release passed all SLO gates": "发布通过全部 SLO 门禁。",
        "Canary traffic sample is insufficient": "Canary 流量样本不足。",
        "Release is still in progress": "发布仍在进行中。",
        "Rollout is aborted or degraded and requires investigation": "Rollout 已中止或降级，需要人工排查。",
        "Release result is unknown and requires manual review": "发布结果未知，需要人工复核。",
    }
    return mapping.get(reason, reason or "未提供")

policy_reason = translate_reason(raw_policy_reason)

def bullet(items):
    if not items:
        return "- 无"
    return "\n".join(f"- `{item}`" for item in items)

def artifact_line(name, key):
    value = artifacts.get(key)
    if not value:
        value = "未提供"
    return f"- {name}：`{value}`"

def human_result_text():
    if release_result == "PASS":
        return "本次发布通过全部 SLO 门禁，Rollout 和 AnalysisRun 均处于健康状态。策略评估结果允许记录本次发布结果，不需要执行恢复动作。"
    if release_result == "IN_PROGRESS":
        return "本次发布仍在进行中，当前不应提前下结论，需要继续观察 Rollout 和 AnalysisRun 的后续状态。"
    if release_result == "FAIL_BY_REQUEST_COUNT":
        return "本次发布失败主要原因是请求样本不足。该场景更像是灰度流量不足，不应直接判断为代码质量故障，可以补充流量后重新验证。"
    if release_result == "FAIL_BY_ERROR_RATE":
        return "本次发布因错误率门禁失败，说明 canary 版本 5xx 错误比例超过阈值，不建议继续扩大流量。"
    if release_result == "FAIL_BY_P95_LATENCY":
        return "本次发布因 P95 延迟门禁失败，说明 canary 版本尾延迟超过阈值，不建议继续扩大流量。"
    if release_result == "FAIL_BY_MULTIPLE_SLO":
        return "本次发布存在多个 SLO 门禁失败，说明 canary 版本同时暴露出多个质量风险，应停止继续发布并进行人工排查。"
    if release_result == "FAIL_BY_ROLLOUT_ABORT":
        return "本次发布已经被 Rollout 中止，应保持停止状态并检查 Rollout 事件、AnalysisRun 结果和 canary 版本日志。"
    if release_result == "FAIL_BY_ROLLOUT_DEGRADED":
        return "本次发布对应 Rollout 已进入 Degraded 状态，需要人工介入排查。"
    return "本次发布结果无法被明确分类，需要人工查看 ReleaseContext、ReleaseReport、AI Decision 和 Policy Decision。"

def action_text():
    if final_action == "NOOP":
        return "无需执行动作，继续观察并归档本次发布记录。"
    if final_action == "OBSERVE":
        return "继续观察，不要提前执行 promote 或 rollback。"
    if final_action == "RETRY_WITH_MORE_TRAFFIC":
        return "补充 canary 流量后重新验证发布门禁。"
    if final_action == "STOP_PROMOTION":
        return "停止继续扩大流量，优先排查 canary 版本问题。"
    if final_action == "INVESTIGATE":
        return "进入人工排查流程，检查 Rollout、AnalysisRun、Pod 日志和变更内容。"
    if final_action == "NONE":
        return "策略层未允许执行动作，保持 advisory_only 安全边界。"
    return "需要人工根据证据链判断下一步动作。"

def build_approval_record_section(section_number: int) -> str:
    if not isinstance(approval_record, dict) or not approval_record:
        return ""

    decision = display(approval_record.get("approvalDecision"))
    approved_action = display(approval_record.get("approvedAction"))
    execution_mode_value = display(approval_record.get("executionMode"))
    will_execute = display_bool(approval_record.get("willExecute"))
    approver = display(approval_record.get("approver"))
    reason = approval_record.get("reason") or "未提供"

    approval_file = str(approval_record_path) if approval_record_path else artifacts.get("approvalRecord") or "未提供"
    approval_report = artifacts.get("approvalRecordReport") or approval_ref.get("markdown") or "未提供"

    return f"""

## {section_number}. Human Approval Record 人工审批记录

- Approval Decision：`{decision}`
- Approved Action：`{approved_action}`
- Execution Mode：`{execution_mode_value}`
- Will Execute：`{will_execute}`
- Approver：`{approver}`
- Reason：{reason}

### Approval 证据文件

- Approval Record JSON：`{approval_file}`
- Approval Record Report：`{approval_report}`

本审批记录只用于人工决策留痕，不会自动执行 Rollback、Promote、Patch、Delete 或 GitOps 变更。
"""

def build_release_intelligence_section(section_number: int) -> str:
    if not isinstance(release_intelligence, dict) or not release_intelligence:
        return ""

    intelligence = release_intelligence.get("intelligence") or {}
    history = release_intelligence.get("history") or {}

    risk_pattern = display(intelligence.get("riskPattern"))
    repeated_risk_pattern = display_bool(intelligence.get("repeatedRiskPattern"))
    recommended_next_action = display(intelligence.get("recommendedNextAction"))
    conclusion = intelligence.get("humanSummary") or intelligence.get("conclusion") or "未提供"

    similar_count = history.get("similarFailureCount", 0)
    exact_count = history.get("exactHistoricalMetricSetMatchCount", 0)
    similar_failures = history.get("similarFailures") or []

    if similar_failures:
        similar_lines = []
        for item in similar_failures[:5]:
            metrics = ", ".join(item.get("failedMetrics") or [])
            similarity = item.get("similarity") or {}
            similar_lines.append(
                f"- `{item.get('releaseId', 'unknown')}` / `{item.get('appVersion', 'unknown')}` / "
                f"`{item.get('releaseResult', 'UNKNOWN')}` / `{metrics or 'none'}` / "
                f"FinalAction=`{item.get('finalAction', 'UNKNOWN')}` / "
                f"ExactMatch=`{str(similarity.get('exactMetricSetMatch', False)).lower()}`"
            )
        similar_failure_text = "\n".join(similar_lines)
    else:
        similar_failure_text = "未发现历史相似失败记录。"

    intelligence_file = str(release_intelligence_path) if release_intelligence_path else "未提供"
    intelligence_report = artifacts.get("releaseIntelligenceReport") or release_intelligence_ref.get("markdown") or "未提供"

    return f"""

## {section_number}. Release Intelligence 历史智能摘要

- Risk Pattern：`{risk_pattern}`
- Repeated Risk Pattern：`{repeated_risk_pattern}`
- Similar Historical Failure Count：`{similar_count}`
- Exact Historical Metric Set Match Count：`{exact_count}`
- Recommended Next Action：`{recommended_next_action}`

{conclusion}

### 历史相似失败

{similar_failure_text}

### Intelligence 证据文件

- Release Intelligence JSON：`{intelligence_file}`
- Release Intelligence Report：`{intelligence_report}`
"""

approval_record_section = build_approval_record_section(11)
release_intelligence_section_number = 12 if approval_record_section else 11
release_intelligence_section = build_release_intelligence_section(release_intelligence_section_number)
safety_section_number = 11
if approval_record_section:
    safety_section_number += 1
if release_intelligence_section:
    safety_section_number += 1

content = f"""<!--
Generated by build-release-summary.sh
Source evidence: {evidence_path}
-->

# 发布摘要

## 1. 最终结论

- 发布结果：`{release_result}`
- 策略裁决：`{policy_decision}`
- 最终动作：`{final_action}`
- 执行模式：`{execution_mode}`
- 是否需要人工审批：`{str(requires_human_approval).lower()}`（{yes_no(requires_human_approval)}）
- 是否可以重试：`{str(safe_to_retry).lower()}`（{yes_no(safe_to_retry)}）

## 2. Rollout 状态

- Rollout 阶段：`{display(summary.get("rolloutPhase"))}`
- 是否触发 Abort：`{display_bool(summary.get("rolloutAbort"))}`
- AnalysisRun 阶段：`{display(summary.get("analysisRunPhase"))}`

## 3. 风险摘要

- 运行时风险等级：`{display(summary.get("riskLevel"))}`
- 运行时风险分数：`{display(summary.get("riskScore"))}`
- 变更风险等级：`{display(summary.get("changeRiskLevel"))}`
- 变更风险分数：`{display(summary.get("changeRiskScore"))}`

## 4. 失败的 SLO 门禁

{bullet(failed_metrics) if failed_metrics else "本次发布没有失败的 SLO 门禁。"}

## 5. 命中的策略规则

{bullet(matched_rules)}

## 6. 策略裁决原因

{policy_reason}

## 7. 证据文件

{artifact_line("Release Context", "releaseContext")}
{artifact_line("Release Report", "releaseReport")}
{artifact_line("AI Advice", "aiAdvice")}
{artifact_line("AI Decision", "aiDecision")}
{artifact_line("Policy Decision", "policyDecision")}
- Release Evidence：`{evidence_path}`
{artifact_line("Release Intelligence", "releaseIntelligence")}
{artifact_line("Release Intelligence Report", "releaseIntelligenceReport")}
{artifact_line("Approval Record", "approvalRecord")}
{artifact_line("Approval Record Report", "approvalRecordReport")}

## 8. Agent 建议动作

- Agent Action：`{(ai_decision_ref.get("agentAction") or {}).get("type", "UNKNOWN")}`
- Agent Action Allowed：`{str((ai_decision_ref.get("agentAction") or {}).get("allowed", False)).lower()}`
- Agent Action Requires Approval：`{str((ai_decision_ref.get("agentAction") or {}).get("requiresApproval", False)).lower()}`
- Agent Action Reason：{translate_reason((ai_decision_ref.get("agentAction") or {}).get("reason", "未提供"))}

## 9. 人工结论

{human_result_text()}

## 10. 建议下一步

{action_text()}
{approval_record_section}
{release_intelligence_section}
## {safety_section_number}. 安全边界

本次摘要只用于人工阅读和审计，不会自动执行 Rollback、Promote、Patch、Delete 或 GitOps 变更。当前系统仍保持 `advisory_only` 模式。
"""

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(content, encoding="utf-8")

print(f"Release summary generated: {output_path}")
PY

cat "$OUTPUT_FILE"
