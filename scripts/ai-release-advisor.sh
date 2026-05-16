#!/bin/bash
set -euo pipefail

MODEL="${MODEL:-qwen2.5:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://192.168.30.1:11434}"
REPORT_FILE="${1:-}"

if [ -z "$REPORT_FILE" ]; then
  REPORT_FILE="$(ls -t docs/release-reports/release-report-*.md 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$REPORT_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
  echo "No release report found."
  echo "Run: bash scripts/collect-release-report.sh"
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
OUT="docs/release-reports/ai-advice-${TS}.md"

python3 - "$OLLAMA_URL" "$MODEL" "$REPORT_FILE" "$OUT" <<'PY'
import json
import re
import sys
import urllib.request
import urllib.error
from pathlib import Path

ollama_url = sys.argv[1].rstrip("/")
model = sys.argv[2]
report_file = Path(sys.argv[3])
out_file = Path(sys.argv[4])

report = report_file.read_text(encoding="utf-8", errors="ignore")

def find_table_value(key):
    pattern = rf"^\| {re.escape(key)} \| (.*?) \|$"
    for line in report.splitlines():
        m = re.match(pattern, line.strip())
        if m:
            return m.group(1).strip()
    return "unknown"

rollout_phase = find_table_value("Rollout Phase")
rollout_abort = find_table_value("Rollout Abort")
current_version = find_table_value("Current Desired Version")
stable_rs = find_table_value("Stable ReplicaSet")
target_ar = find_table_value("Target AnalysisRun")
argo_revision = find_table_value("Argo CD Revision")
git_commit = find_table_value("Git Commit")

failed_metric = "none"
if 'Metric "error-rate" assessed Failed' in report:
    failed_metric = "error-rate"
elif 'Metric "p95-latency" assessed Failed' in report:
    failed_metric = "p95-latency"
elif 'Metric "request-count" assessed Failed' in report:
    failed_metric = "request-count"

has_rollout_aborted = "RolloutAborted" in report or rollout_abort.lower() == "true"
has_degraded = rollout_phase.lower() == "degraded"
has_5xx = '"status":"500"' in report or 'status="500"' in report or "5xx" in report
has_prometheus_error = "Prometheus not reachable" in report or "Failed to call Prometheus" in report

interesting_lines = []
keywords = [
    "Rollout Phase",
    "Rollout Abort",
    "Current Desired Version",
    "Stable ReplicaSet",
    "Target AnalysisRun",
    "Argo CD Revision",
    "Git Commit",
    "Metric",
    "Failed",
    "RolloutAborted",
    "Degraded",
    "Healthy",
    "Successful",
    "error-rate",
    "p95-latency",
    "request-count",
    "status",
    "version",
    "v7-actions-bad",
    "v8-actions",
    "v9-actions",
    "500",
    "200",
]

for line in report.splitlines():
    if any(k in line for k in keywords):
        interesting_lines.append(line)

evidence_text = "\n".join(interesting_lines[:180])

structured_input = f"""
发布摘要：
Rollout Phase: {rollout_phase}
Rollout Abort: {rollout_abort}
Current Desired Version: {current_version}
Stable ReplicaSet: {stable_rs}
Target AnalysisRun: {target_ar}
Argo CD Revision: {argo_revision}
Git Commit: {git_commit}
Failed Metric: {failed_metric}
Has RolloutAborted Evidence: {has_rollout_aborted}
Has Degraded Evidence: {has_degraded}
Has 5xx Evidence: {has_5xx}
Has Prometheus Query Error: {has_prometheus_error}

关键原文证据：
{evidence_text}

指标含义说明：
- request-count：最小流量门禁，成功条件是 result[0] >= 20。如果失败，说明样本量不足。
- error-rate：5xx 错误率门禁，成功条件是 result[0] < 5。如果失败，说明错误率超过 5%。
- p95-latency：P95 延迟门禁，成功条件是 result[0] < 0.3。如果失败，说明 P95 延迟超过 0.3 秒。
"""

system_prompt = """
你是一个 Kubernetes / Argo Rollouts / SRE 发布分析助手。

硬性要求：
1. 必须使用中文输出。
2. 只能输出 5 个章节。
3. 只能基于输入内容分析，不允许编造。
4. 如果 Rollout Phase 是 Healthy，且 Failed Metric 是 none，就判断当前发布状态健康。
5. 如果看到 RolloutAborted、Degraded、Failed Metric，才判断发布失败或被中止。
6. 如果 Prometheus 没有错误数据，不要写 Prometheus 排障文档。
7. 不要建议危险操作，例如强制删除稳定版本 Pod、跳过发布门禁、强制覆盖 Git。
8. 不允许输出第 6 个章节。
"""

user_prompt = f"""
请根据下面的发布摘要生成 Release Advisor 分析。

必须严格使用以下 5 个章节标题：

# AI Release Advisor

## 1. 结论

## 2. 关键证据

## 3. 影响范围

## 4. 可能原因

## 5. 建议动作

要求：
- 必须中文。
- 不要输出英文。
- 不要只解释 Prometheus 查询。
- 不允许新增第 6 节。
- 如果当前是健康版本，就明确说明当前发布健康。
- 如果历史里有坏版本证据，可以作为历史验证说明，但不要误判当前发布失败。

发布摘要如下：

{structured_input}
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

data = json.dumps(payload).encode("utf-8")

req = urllib.request.Request(
    f"{ollama_url}/api/chat",
    data=data,
    headers={"Content-Type": "application/json"},
    method="POST"
)

try:
    with urllib.request.urlopen(req, timeout=300) as resp:
        raw = resp.read().decode("utf-8", errors="ignore")
except urllib.error.URLError as e:
    print(f"Failed to call Ollama: {e}", file=sys.stderr)
    sys.exit(1)

try:
    obj = json.loads(raw)
    content = obj.get("message", {}).get("content", "").strip()
except json.JSONDecodeError:
    content = raw.strip()

if not content:
    print("Ollama returned empty response.", file=sys.stderr)
    sys.exit(1)

content = re.sub(r"(?ms)^##\s*6[^\n]*\n.*$", "", content).strip()

final = f"""<!--
Generated by ai-release-advisor.sh
Source report: {report_file}
Model: {model}
Ollama URL: {ollama_url}
-->

{content}
"""

out_file.write_text(final, encoding="utf-8")
print(f"AI advisor report generated: {out_file}")
PY
