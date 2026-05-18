#!/bin/bash
set -euo pipefail

REPORT_FILE="${1:-}"
CONTEXT_FILE="${RELEASE_CONTEXT_FILE:-}"
OLLAMA_URL="${OLLAMA_URL:-http://192.168.30.1:11434}"
MODEL="${MODEL:-qwen2.5:3b}"
OUT_DIR="${AI_ADVICE_OUTPUT_DIR:-docs/release-reports}"
TS="$(date +%Y%m%d-%H%M%S)"

if [ -z "$REPORT_FILE" ]; then
  REPORT_FILE="$(ls -t docs/release-reports/release-report-*.md 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$CONTEXT_FILE" ]; then
  CONTEXT_FILE="$(ls -t docs/release-reports/release-context-*.json 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$REPORT_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
  echo "ERROR: release report file not found" >&2
  exit 1
fi

if [ -z "$CONTEXT_FILE" ] || [ ! -f "$CONTEXT_FILE" ]; then
  echo "ERROR: release context file not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
OUT="${OUT_DIR}/ai-advice-${TS}.md"
DECISION_OUT="${OUT_DIR}/ai-decision-${TS}.json"

python3 - "$OLLAMA_URL" "$MODEL" "$REPORT_FILE" "$CONTEXT_FILE" "$OUT" "$DECISION_OUT" <<'PY'
import json
import sys
import urllib.request
from pathlib import Path

ollama_url = sys.argv[1].rstrip("/")
model = sys.argv[2]
report_file = Path(sys.argv[3])
context_file = Path(sys.argv[4])
out_file = Path(sys.argv[5])
decision_out_file = Path(sys.argv[6])

ctx = json.loads(context_file.read_text(encoding="utf-8"))
report_text = report_file.read_text(encoding="utf-8", errors="ignore")[:12000]

def arr(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    return [v]

def bullet(items):
    items = [str(x) for x in items if x not in (None, "")]
    if not items:
        return "- 无"
    return "\n".join(f"- {x}" for x in items)

def j(obj):
    return json.dumps(obj, ensure_ascii=False, indent=2)

change = ctx.get("changeContext") or {}
image = change.get("image") or {}
env_changes = change.get("envChanges") or []
slo_changes = change.get("sloGateChanges") or {}

failed_metrics = arr(ctx.get("failedMetrics"))
release_result = ctx.get("result") or "UNKNOWN"
risk_reasons = arr(ctx.get("riskReasons"))
change_hints = arr(ctx.get("changeRiskHints"))

rollout_phase = ctx.get("rolloutPhase")
rollout_abort = ctx.get("rolloutAbort")
analysis_phase = ctx.get("analysisRunPhase")
severity = ctx.get("severity")
risk_score = ctx.get("riskScore")
change_risk_level = ctx.get("changeRiskLevel")
change_risk_score = ctx.get("changeRiskScore")

conclusion = "本次发布需要人工介入。"

if release_result == "PASS":
    conclusion = "本次发布已通过 SLO 门禁，当前可以继续观察或进入后续发布阶段。"
elif release_result == "IN_PROGRESS":
    conclusion = "本次发布仍在进行中，需要继续观察 Rollout 和 AnalysisRun 状态。"
elif release_result == "FAIL_BY_REQUEST_COUNT":
    conclusion = "本次发布失败主要表现为 request-count 样本不足，需要先补充流量再重试，不应直接判断为代码故障。"
elif release_result == "FAIL_BY_ERROR_RATE":
    conclusion = "本次发布因 error-rate 门禁失败，说明 canary 版本 5xx 错误比例超过阈值，不建议继续 promote。"
elif release_result == "FAIL_BY_P95_LATENCY":
    conclusion = "本次发布因 p95-latency 门禁失败，说明 canary 版本尾延迟超过阈值，不建议继续 promote。"
elif release_result == "FAIL_BY_MULTIPLE_SLO":
    conclusion = "本次发布存在多个 SLO 门禁失败，应停止发布并优先定位 canary 版本质量问题。"
elif release_result == "FAIL_BY_ROLLOUT_ABORT":
    conclusion = "本次发布已经被 Rollout 中止，不建议继续 promote。"
elif release_result == "FAIL_BY_ROLLOUT_DEGRADED":
    conclusion = "本次发布对应 Rollout 已进入 Degraded 状态，需要人工介入排查。"
elif rollout_phase == "Degraded" or rollout_abort is True or analysis_phase == "Failed":
    conclusion = "本次发布失败或已被中止，不建议继续 promote。"

if change_risk_level in ("high", "critical") and release_result in ("FAIL_BY_ERROR_RATE", "FAIL_BY_P95_LATENCY", "FAIL_BY_MULTIPLE_SLO"):
    conclusion = "本次发布属于高风险变更导致质量回退的可能性较高，应停止发布并回滚或修复后重新发布。"

deterministic = f"""# AI Release Advisor

## 1. 结论

{conclusion}

## 2. 本次变更摘要

- Change Risk Level: {change_risk_level}
- Change Risk Score: {change_risk_score}
- Change Risk Hints:
{bullet(change_hints)}

### Image Change

{j(image)}

### Environment Changes

{j(env_changes)}

### SLO Gate Changes

{j(slo_changes)}

## 3. 发布失败证据

- Namespace: {ctx.get("namespace")}
- Rollout: {ctx.get("rollout")}
- Rollout Phase: {rollout_phase}
- Rollout Abort: {rollout_abort}
- AnalysisRun: {ctx.get("analysisRun")}
- AnalysisRun Phase: {analysis_phase}
- Release Result: {release_result}
- Failed Metrics: {", ".join(failed_metrics) if failed_metrics else "无"}
- Release Severity: {severity}
- Release Risk Score: {risk_score}

### Release Risk Reasons

{bullet(risk_reasons)}

## 4. 变更与失败指标的关联分析

"""

if change_risk_level in ("high", "critical"):
    deterministic += "本次变更风险较高，需要优先检查 ChangeContext 中的高风险项。\n\n"
else:
    deterministic += "本次变更风险不高，需要结合 AnalysisRun 失败指标继续判断。\n\n"

if release_result and release_result != "UNKNOWN":
    deterministic += f"- 平台标准发布结果为 `{release_result}`，AI 分析应以该结构化结果为第一判断依据。\n"

if any(x.get("name") == "FAULT_RATE" for x in env_changes):
    deterministic += "- FAULT_RATE 发生变化，若 failedMetrics 包含 error-rate，则说明新版本错误率升高与本次变更存在较强关联。\n"
if any(x.get("name") == "LATENCY_MS" for x in env_changes):
    deterministic += "- LATENCY_MS 发生变化，若 failedMetrics 包含 p95-latency，则说明新版本延迟升高与本次变更存在较强关联。\n"
if image.get("changed"):
    deterministic += "- 镜像 tag 已变化，说明本次确实引入了新的应用版本。\n"
if "request-count" in failed_metrics and len(failed_metrics) == 1:
    deterministic += "- 当前仅 request-count 失败，更可能是灰度阶段请求样本不足，而不是新版本质量问题。\n"
if "error-rate" in failed_metrics:
    deterministic += "- error-rate 失败，说明 canary 版本 5xx 错误比例超过门禁阈值。\n"
if "p95-latency" in failed_metrics:
    deterministic += "- p95-latency 失败，说明 canary 版本尾延迟超过门禁阈值。\n"

deterministic += f"""

## 5. 影响范围

异常发生在 Argo Rollouts 灰度发布阶段。由于 Rollout 已经进入 {rollout_phase}，并且 abort={rollout_abort}，坏版本不会继续扩大到全量发布。

## 6. 建议动作

- 不要强行跳过 SLO 门禁。
- 保持 Rollout 中止状态，先定位 canary 版本问题。
- 优先检查本次变更项，尤其是 FAULT_RATE、LATENCY_MS、镜像 tag 和业务代码变更。
- 如果只是 request-count 样本不足，应补充流量后重试发布。
- 如果 error-rate 或 p95-latency 失败，应回滚或修复后使用新 tag 重新发布。
"""

system_prompt = "你是云原生发布可靠性分析助手。请基于 ReleaseContext、ChangeContext 和发布报告，用中文补充分析。不要编造不存在的数据。"
user_prompt = f"""
请基于以下确定性分析继续补充，但不要覆盖它。

确定性分析：
{deterministic}

ReleaseContext JSON：
{j(ctx)}

发布报告摘录：
{report_text}
"""

llm_text = ""
try:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "stream": False,
    }
    req = urllib.request.Request(
        f"{ollama_url}/api/chat",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        llm_text = data.get("message", {}).get("content", "").strip()
except Exception as e:
    llm_text = f"Ollama 调用失败，已使用确定性规则生成报告。错误：{e}"

final = f"""<!--
Generated by ai-release-advisor.sh
Source context: {context_file}
Source report: {report_file}
Model: {model}
Ollama URL: {ollama_url}
Change Risk Level: {change_risk_level}
Change Risk Score: {change_risk_score}
-->

{deterministic}

## 7. LLM 补充分析

{llm_text}
"""

def bool_from_result(value):
    return bool(value)

requires_human_approval = release_result.startswith("FAIL_") or release_result == "UNKNOWN"
safe_to_retry = release_result in ("PASS", "FAIL_BY_REQUEST_COUNT", "IN_PROGRESS")

if release_result in ("FAIL_BY_ERROR_RATE", "FAIL_BY_P95_LATENCY", "FAIL_BY_MULTIPLE_SLO"):
    safe_to_retry = False

summary = conclusion

decision_source = "deterministic_rule"
confidence = "high"

if release_result == "UNKNOWN":
    decision_source = "insufficient_context"
    confidence = "low"

policy_hints = []

if release_result == "PASS":
    policy_hints.extend([
        "release_result_passed",
        "no_human_approval_required",
        "safe_to_continue",
    ])
elif release_result == "IN_PROGRESS":
    policy_hints.extend([
        "release_in_progress",
        "continue_observing",
        "no_human_approval_required",
    ])
elif release_result == "FAIL_BY_REQUEST_COUNT":
    policy_hints.extend([
        "request_count_insufficient",
        "retry_with_more_traffic_allowed",
        "no_human_approval_required",
    ])
elif release_result == "FAIL_BY_MULTIPLE_SLO":
    policy_hints.extend([
        "multiple_slo_gates_failed",
        "human_approval_required",
        "unsafe_to_retry_without_fix",
        "stop_promotion_recommended",
    ])
elif release_result in ("FAIL_BY_ERROR_RATE", "FAIL_BY_P95_LATENCY"):
    policy_hints.extend([
        "single_slo_gate_failed",
        "human_approval_required",
        "unsafe_to_retry_without_fix",
        "stop_promotion_recommended",
    ])
elif release_result in ("FAIL_BY_ROLLOUT_ABORT", "FAIL_BY_ROLLOUT_DEGRADED"):
    policy_hints.extend([
        "rollout_unhealthy",
        "human_approval_required",
        "investigation_required",
    ])
else:
    policy_hints.extend([
        "insufficient_context",
        "manual_review_required",
    ])

if requires_human_approval and "human_approval_required" not in policy_hints:
    policy_hints.append("human_approval_required")

if not safe_to_retry and "unsafe_to_retry_without_fix" not in policy_hints:
    policy_hints.append("unsafe_to_retry_without_fix")

agent_action = {
    "type": "MANUAL_REVIEW",
    "allowed": False,
    "requiresApproval": True,
    "reason": "Release result is unknown and requires manual review",
}

if release_result == "PASS":
    agent_action = {
        "type": "NOOP",
        "allowed": True,
        "requiresApproval": False,
        "reason": "Release passed all SLO gates",
    }
elif release_result == "IN_PROGRESS":
    agent_action = {
        "type": "OBSERVE",
        "allowed": True,
        "requiresApproval": False,
        "reason": "Release is still in progress",
    }
elif release_result == "FAIL_BY_REQUEST_COUNT":
    agent_action = {
        "type": "RETRY_WITH_MORE_TRAFFIC",
        "allowed": True,
        "requiresApproval": False,
        "reason": "Canary traffic sample is insufficient",
    }
elif release_result in ("FAIL_BY_ERROR_RATE", "FAIL_BY_P95_LATENCY", "FAIL_BY_MULTIPLE_SLO"):
    agent_action = {
        "type": "STOP_PROMOTION",
        "allowed": True,
        "requiresApproval": True,
        "reason": "Release failed SLO gates and requires human investigation",
    }
elif release_result in ("FAIL_BY_ROLLOUT_ABORT", "FAIL_BY_ROLLOUT_DEGRADED"):
    agent_action = {
        "type": "INVESTIGATE",
        "allowed": True,
        "requiresApproval": True,
        "reason": "Rollout is aborted or degraded and requires investigation",
    }

execution_mode = "advisory_only"

next_steps = []
if release_result == "PASS":
    next_steps = [
        "archive_release_record",
        "continue_observing",
    ]
elif release_result == "IN_PROGRESS":
    next_steps = [
        "continue_observing_rollout",
        "wait_for_analysisrun_result",
    ]
elif release_result == "FAIL_BY_REQUEST_COUNT":
    next_steps = [
        "continue_generating_canary_traffic",
        "rerun_release_with_sufficient_request_count",
    ]
elif release_result in ("FAIL_BY_ERROR_RATE", "FAIL_BY_P95_LATENCY", "FAIL_BY_MULTIPLE_SLO"):
    next_steps = [
        "stop_promotion",
        "inspect_canary_logs",
        "compare_change_context",
        "publish_fixed_version_with_new_tag",
    ]
elif release_result in ("FAIL_BY_ROLLOUT_ABORT", "FAIL_BY_ROLLOUT_DEGRADED"):
    next_steps = [
        "inspect_rollout_events",
        "inspect_analysisrun_details",
        "keep_promotion_stopped_until_review",
    ]
else:
    next_steps = [
        "manual_review_release_context",
        "inspect_rollout_and_analysisrun",
    ]

guardrails = {
    "autoExecute": False,
    "executionMode": execution_mode,
    "requiresGitOpsChange": True,
    "requiresHumanApprovalForRiskyAction": True,
    "allowedActions": [
        "NOOP",
        "OBSERVE",
        "RETRY_WITH_MORE_TRAFFIC",
        "STOP_PROMOTION",
        "INVESTIGATE",
        "MANUAL_REVIEW",
    ],
    "blockedActions": [
        "ROLLBACK",
        "PROMOTE",
        "DELETE_RESOURCE",
        "PATCH_RESOURCE",
        "APPLY_MANIFEST",
    ],
}

evidence = {
    "failedMetrics": failed_metrics,
    "rolloutPhase": rollout_phase,
    "rolloutAbort": rollout_abort,
    "analysisRunPhase": analysis_phase,
    "riskLevel": severity,
    "riskScore": risk_score,
    "riskReasons": risk_reasons,
    "changeRiskLevel": change_risk_level,
    "changeRiskScore": change_risk_score,
}

decision_json = {
    "schemaVersion": "ai.release.advisor/v1alpha1",
    "generatedBy": "ai-release-advisor.sh",
    "model": model,
    "releaseResult": release_result,
    "decisionSource": decision_source,
    "confidence": confidence,
    "executionMode": execution_mode,
    "summary": summary,
    "conclusion": conclusion,
    "failedMetrics": failed_metrics,
    "riskLevel": severity,
    "riskScore": risk_score,
    "riskReasons": risk_reasons,
    "changeRiskLevel": change_risk_level,
    "changeRiskScore": change_risk_score,
    "changeRiskHints": change_hints,
    "decision": ctx.get("decision"),
    "recommendedAction": ctx.get("recommendedAction"),
    "requiresHumanApproval": requires_human_approval,
    "safeToRetry": safe_to_retry,
    "policyHints": policy_hints,
    "agentAction": agent_action,
    "guardrails": guardrails,
    "evidence": evidence,
    "nextSteps": next_steps,
    "rollout": {
        "namespace": ctx.get("namespace"),
        "name": ctx.get("rollout"),
        "phase": rollout_phase,
        "abort": rollout_abort,
        "message": ctx.get("rolloutMessage"),
        "stableReplicaSet": ctx.get("stableReplicaSet"),
        "currentDesiredVersion": ctx.get("currentDesiredVersion"),
    },
    "analysisRun": {
        "name": ctx.get("analysisRun"),
        "phase": analysis_phase,
        "metrics": ctx.get("analysisRunMetrics") or [],
    },
    "sources": {
        "releaseContext": str(context_file),
        "releaseReport": str(report_file),
        "aiAdvice": str(out_file),
    },
}

out_file.write_text(final, encoding="utf-8")
decision_out_file.write_text(json.dumps(decision_json, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"AI advisor report generated: {out_file}")
print(f"AI decision generated: {decision_out_file}")
print(f"Source context: {context_file}")
print(f"Source report: {report_file}")
print(f"Change risk: {change_risk_level} score={change_risk_score}")
PY
