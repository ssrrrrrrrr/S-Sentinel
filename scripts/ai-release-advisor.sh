#!/bin/bash
set -euo pipefail

MODEL="${MODEL:-qwen2.5:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://192.168.30.1:11434}"

REPORT_FILE="${1:-}"
CONTEXT_FILE="${RELEASE_CONTEXT_FILE:-}"

mkdir -p docs/release-reports

if [ -z "$REPORT_FILE" ]; then
  REPORT_FILE="$(ls -t docs/release-reports/release-report-*.md 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$CONTEXT_FILE" ]; then
  CONTEXT_FILE="$(ls -t docs/release-reports/release-context-*.json 2>/dev/null | head -n 1 || true)"
fi

TS="$(date +%Y%m%d-%H%M%S)"
OUT="docs/release-reports/ai-advice-${TS}.md"

python3 - "$OLLAMA_URL" "$MODEL" "$REPORT_FILE" "$CONTEXT_FILE" "$OUT" <<'PY'
import json
import re
import sys
import urllib.request
import urllib.error
from pathlib import Path

ollama_url = sys.argv[1].rstrip("/")
model = sys.argv[2]
report_arg = sys.argv[3]
context_arg = sys.argv[4]
out_file = Path(sys.argv[5])

report_file = Path(report_arg) if report_arg else None
context_file = Path(context_arg) if context_arg else None

context_data = {}
report = ""

if context_file and context_file.exists():
    context_data = json.loads(context_file.read_text(encoding="utf-8", errors="ignore"))

if report_file and report_file.exists():
    report = report_file.read_text(encoding="utf-8", errors="ignore")

def pick_failed_metric(ctx, text):
    failed_metrics = ctx.get("failedMetrics") or []
    if failed_metrics:
        return failed_metrics[0]

    ctx_metric = ctx.get("failedMetric")
    if ctx_metric and ctx_metric != "unknown":
        return ctx_metric

    msg = (ctx.get("rolloutMessage") or "") + "\n" + (ctx.get("reason") or "") + "\n" + text
    if "error-rate" in msg:
        return "error-rate"
    if "p95-latency" in msg:
        return "p95-latency"
    if "request-count" in msg:
        return "request-count"
    return "unknown"

def extract_key_evidence(text):
    keys = [
        "Rollout Phase",
        "Rollout Abort",
        "Current Desired Version",
        "Stable ReplicaSet",
        "Target AnalysisRun",
        "Metric",
        "Failed",
        "RolloutAborted",
        "error-rate",
        "p95-latency",
        "request-count",
        "status",
        "version",
        "v10-actions-bad",
        "v9-actions",
    ]
    lines = []
    for line in text.splitlines():
        if any(k in line for k in keys):
            lines.append(line)
    return "\n".join(lines[:80])

failed_metric = pick_failed_metric(context_data, report)
failed_metrics = context_data.get("failedMetrics") or ([] if failed_metric == "unknown" else [failed_metric])
key_evidence = extract_key_evidence(report)

rollout_phase = context_data.get("rolloutPhase", "unknown")
rollout_abort = context_data.get("rolloutAbort", False)
analysis_phase = context_data.get("analysisRunPhase", "unknown")
rollout = context_data.get("rollout", "unknown")
namespace = context_data.get("namespace", "unknown")
analysisrun = context_data.get("analysisRun", "unknown")
message = context_data.get("rolloutMessage", "")
reason = context_data.get("reason", "")
decision = context_data.get("decision", "unknown")
recommended_action = context_data.get("recommendedAction", "unknown")
severity = context_data.get("severity", "unknown")
risk_score = context_data.get("riskScore", "unknown")
risk_reasons = context_data.get("riskReasons") or []
risk_reasons_text = "\n".join([f"- {r}" for r in risk_reasons]) if risk_reasons else "- unknown"

context_json = json.dumps(context_data, ensure_ascii=False, indent=2)

system_prompt = """
你是一个 Kubernetes / Argo Rollouts / SRE 发布分析助手。

硬性要求：
1. 必须使用中文输出。
2. 只能输出 5 个章节。
3. 必须优先依据 ReleaseContext JSON 判断发布状态。
4. 只能分析发布状态、失败指标、影响范围和建议动作，不要解释 Argo CD 或 Argo Workflows。
5. 不允许编造输入中不存在的信息。
6. 如果 rolloutPhase=Degraded、rolloutAbort=true、analysisRunPhase=Failed，则必须判断发布失败或被中止。
7. 不允许输出英文。
8. 不允许输出第 6 个章节。
"""

user_prompt = f"""
请根据下面的结构化发布上下文生成 Release Advisor 分析。

必须严格使用以下 5 个章节标题：

# AI Release Advisor

## 1. 结论

## 2. 关键证据

## 3. 影响范围

## 4. 可能原因

## 5. 建议动作

指标含义：
- request-count：最小流量门禁，成功条件 result[0] >= 20。
- error-rate：5xx 错误率门禁，成功条件 result[0] < 5。
- p95-latency：P95 延迟门禁，成功条件 result[0] < 0.3。

ReleaseContext JSON：
{context_json}

已识别失败指标：
{failed_metric}

关键证据摘录：
{key_evidence}
"""


def metric_map(ctx):
    result = {}
    for m in ctx.get("analysisRunMetrics", []) or []:
        name = m.get("name", "unknown")
        result[name] = m
    return result

def clean_metric_value(value):
    if value is None:
        return "unknown"
    value = str(value).strip()
    value = value.strip("[]")
    if not value:
        return "unknown"
    return value

def metric_summary(ctx):
    metrics = metric_map(ctx)

    lines = []
    error_rate_value = "unknown"
    request_count_value = "unknown"
    p95_value = "unknown"

    if "error-rate" in metrics:
        m = metrics["error-rate"]
        error_rate_value = clean_metric_value(m.get("value"))
        lines.append(f"- error-rate: phase={m.get('phase', 'unknown')}, value={error_rate_value}, failed={m.get('failed', 0)}")

    if "request-count" in metrics:
        m = metrics["request-count"]
        request_count_value = clean_metric_value(m.get("value"))
        lines.append(f"- request-count: phase={m.get('phase', 'unknown')}, value={request_count_value}, successful={m.get('successful', 0)}")

    if "p95-latency" in metrics:
        m = metrics["p95-latency"]
        p95_value = clean_metric_value(m.get("value"))
        lines.append(f"- p95-latency: phase={m.get('phase', 'unknown')}, value={p95_value}, failed={m.get('failed', 0)}")

    if not lines:
        lines.append("- 当前 ReleaseContext 中没有 analysisRunMetrics 明细。")

    return "\n".join(lines), error_rate_value, request_count_value, p95_value

def deterministic_report():
    metrics_text, error_rate_value, request_count_value, p95_value = metric_summary(context_data)

    if rollout_phase == "Degraded" or rollout_abort or analysis_phase in ["Failed", "Error"]:
        conclusion = f"本次发布未能成功完成。Rollout 当前处于 {rollout_phase} 状态，RolloutAbort 为 {str(rollout_abort).lower()}，AnalysisRun {analysisrun} 的状态为 {analysis_phase}。"
    else:
        conclusion = f"当前发布未发现明确失败证据。Rollout 当前状态为 {rollout_phase}，AnalysisRun 状态为 {analysis_phase}。"

    failed_set = set(failed_metrics)
    cause_parts = []

    if "error-rate" in failed_set:
        part = f"error-rate 指标失败，当前值约为 {error_rate_value}%，超过 5% 的 SLO 门禁阈值，说明 Canary 版本 5xx 错误率过高。"
        cause_parts.append(part)

    if "p95-latency" in failed_set:
        part = f"p95-latency 指标失败，当前值约为 {p95_value} 秒，超过 0.3 秒的 SLO 门禁阈值，说明 Canary 版本存在明显延迟劣化。"
        cause_parts.append(part)

    if "request-count" in failed_set:
        part = f"request-count 指标失败，当前值约为 {request_count_value}，未达到最小请求量门禁，说明样本量不足。"
        cause_parts.append(part)

    if not cause_parts:
        cause_parts.append("当前只能确定发布被标记为异常，但失败指标需要结合 AnalysisRun 和 Prometheus 指标继续确认。")

    if request_count_value != "unknown" and "request-count" not in failed_set:
        cause_parts.append(f"request-count 约为 {request_count_value}，说明已经有一定请求样本，本次失败不是单纯因为样本量不足。")

    cause = " ".join(cause_parts)

    return f"""# AI Release Advisor

## 1. 结论

{conclusion}

## 2. 关键证据

- Namespace: {namespace}
- Rollout: {rollout}
- Rollout Phase: {rollout_phase}
- Rollout Abort: {rollout_abort}
- Stable ReplicaSet: {context_data.get("stableReplicaSet", "unknown")}
- Current Desired Version: {context_data.get("currentDesiredVersion", "unknown")}
- AnalysisRun: {analysisrun}
- AnalysisRun Phase: {analysis_phase}
- Failed Metric: {failed_metric}
- Failed Metrics: {", ".join(failed_metrics) if failed_metrics else "unknown"}
- Severity: {severity}
- Risk Score: {risk_score}
- Risk Reasons:
{risk_reasons_text}
- Decision: {decision}
- Recommended Action: {recommended_action}
- Rollout Message: {message}

指标明细：

{metrics_text}

## 3. 影响范围

本次异常发生在 Argo Rollouts 灰度发布阶段，影响范围主要集中在 Canary 版本。由于 Rollout 已经被中止，稳定版本不会被坏版本继续替换，故障没有被继续放大到全量发布。

## 4. 可能原因

{cause}

系统识别到的触发原因是：{reason}

## 5. 建议动作

- 保持当前 Rollout 中止状态，不要继续 promote 异常版本。
- 优先查看失败的 AnalysisRun 和对应 Canary Pod 日志，确认失败指标来源。
- 如果失败指标是 error-rate，重点排查新版本接口异常、配置错误、依赖调用失败或故障注入参数。
- 修复后使用新的版本 tag 重新发布，不建议强制跳过 SLO 门禁。
"""

payload = {
    "model": model,
    "stream": False,
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt}
    ],
    "options": {
        "temperature": 0.1
    }
}

content = ""

try:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{ollama_url}/api/chat",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        raw = resp.read().decode("utf-8", errors="ignore")
    obj = json.loads(raw)
    content = obj.get("message", {}).get("content", "").strip()
except Exception as e:
    content = ""

# 兜底：模型跑偏、输出英文、或者没有按标题输出，就用规则报告
bad_signals = [
    "Based on",
    "Argo Workflows",
    "Argo CD Application",
    "If you need",
    "Here's",
    "受影响的 Pod 包括",
    "failureLimit",
    "目标版本为 v11-actions",
]

# For high-confidence rollout failure events, use deterministic report first.
# LLM output is not trusted for safety-critical release decision fields.
high_confidence_failure = (
    rollout_phase == "Degraded"
    or rollout_abort
    or analysis_phase in ["Failed", "Error"]
)

if (
    high_confidence_failure
    or not content
    or "# AI Release Advisor" not in content
    or any(x in content for x in bad_signals)
):
    content = deterministic_report()

content = re.sub(r"(?ms)^##\s*6[^\n]*\n.*$", "", content).strip()

source_report = str(report_file) if report_file else "none"
source_context = str(context_file) if context_file else "none"

final = f"""<!--
Generated by ai-release-advisor.sh
Source context: {source_context}
Source report: {source_report}
Model: {model}
Ollama URL: {ollama_url}
-->

{content}
"""

out_file.write_text(final, encoding="utf-8")
print(f"AI advisor report generated: {out_file}")
PY
