#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${FAILURE_EVIDENCE_DIR:-docs/release-reports}"
RELEASE_CONTEXT_FILE="${1:-}"
COLLECT_K8S_EVIDENCE="${COLLECT_K8S_EVIDENCE:-false}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/collect-failure-evidence.sh [RELEASE_CONTEXT_JSON]

Examples:
  scripts/collect-failure-evidence.sh
  scripts/collect-failure-evidence.sh docs/release-reports/release-context-20260516-203256.json

Optional:
  COLLECT_K8S_EVIDENCE=true scripts/collect-failure-evidence.sh docs/release-reports/release-context-xxx.json

Behavior:
  - If RELEASE_CONTEXT_JSON is omitted, the latest docs/release-reports/release-context-*.json is used.
  - The output is written to:
      failure-evidence-*.json
      failure-evidence-*.md
      failure-evidence-latest.json
      failure-evidence-latest.md
  - This script is advisory_only.
  - It does not rollback, promote, patch, delete, modify GitOps, or modify Kubernetes resources.
  - K8s collection is best-effort and disabled by default.
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

if [ -z "$RELEASE_CONTEXT_FILE" ]; then
  RELEASE_CONTEXT_FILE="$(ls -t "$REPORT_DIR"/release-context-*.json 2>/dev/null | head -1 || true)"
fi

if [ -z "$RELEASE_CONTEXT_FILE" ] || [ ! -f "$RELEASE_CONTEXT_FILE" ]; then
  echo "ERROR: release context file does not exist: ${RELEASE_CONTEXT_FILE:-not provided}" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$RELEASE_CONTEXT_FILE")"
TS="$(date +%Y%m%d-%H%M%S)"
OUTPUT_JSON="$OUTPUT_DIR/failure-evidence-${TS}.json"
OUTPUT_MD="$OUTPUT_DIR/failure-evidence-${TS}.md"
LATEST_JSON="$OUTPUT_DIR/failure-evidence-latest.json"
LATEST_MD="$OUTPUT_DIR/failure-evidence-latest.md"

python3 - "$RELEASE_CONTEXT_FILE" "$OUTPUT_JSON" "$OUTPUT_MD" "$LATEST_JSON" "$LATEST_MD" "$COLLECT_K8S_EVIDENCE" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ctx_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
output_md = Path(sys.argv[3])
latest_json = Path(sys.argv[4])
latest_md = Path(sys.argv[5])
collect_k8s = sys.argv[6].lower() == "true"

ctx = json.loads(ctx_path.read_text(encoding="utf-8"))

namespace = ctx.get("namespace") or "unknown"
rollout = ctx.get("rollout") or "unknown"
analysis_run = ctx.get("analysisRun") or ""
rollout_phase = ctx.get("rolloutPhase")
rollout_abort = ctx.get("rolloutAbort")
rollout_message = ctx.get("rolloutMessage") or ""
analysis_phase = ctx.get("analysisRunPhase")
failed_metrics = ctx.get("failedMetrics") or []
analysis_metrics = ctx.get("analysisRunMetrics") or []
severity = ctx.get("severity")
risk_score = ctx.get("riskScore")
risk_reasons = ctx.get("riskReasons") or []
decision = ctx.get("decision")
recommended_action = ctx.get("recommendedAction")

def run(cmd, timeout=12):
    try:
        out = subprocess.check_output(
            cmd,
            text=True,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return {
            "command": " ".join(cmd),
            "ok": True,
            "output": out[-12000:],
        }
    except Exception as e:
        return {
            "command": " ".join(cmd),
            "ok": False,
            "output": str(e),
        }

def is_failure_context():
    if rollout_phase == "Degraded":
        return True
    if rollout_abort is True:
        return True
    if analysis_phase == "Failed":
        return True
    if failed_metrics:
        return True
    if severity in ("high", "critical"):
        return True
    return False

is_failure = is_failure_context()

k8s_freshness_warning = "Kubernetes live evidence is collected at diagnosis time and may differ from the original failure time."
k8s_freshness_human_warning = "K8s 现场证据是在诊断时采集的，可能与故障发生时的状态不同。如果 ReleaseContext 来自历史失败记录，而当前集群已经恢复，则 kubectl 结果可能显示当前健康状态。"

k8s = {
    "enabled": collect_k8s,
    "available": False,
    "commands": [],
    "freshness": {
        "type": "live_kubernetes_snapshot",
        "warning": k8s_freshness_warning,
        "humanWarning": k8s_freshness_human_warning
    }
}

if collect_k8s:
    kubectl_check = run(["sh", "-c", "command -v kubectl"], timeout=5)
    k8s["available"] = kubectl_check["ok"]

    if k8s["available"] and namespace != "unknown":
        if rollout != "unknown":
            k8s["commands"].append(run(["kubectl", "-n", namespace, "get", "rollout", rollout, "-o", "wide"]))
            k8s["commands"].append(run(["kubectl", "-n", namespace, "describe", "rollout", rollout]))

        if analysis_run:
            k8s["commands"].append(run(["kubectl", "-n", namespace, "get", "analysisrun", analysis_run, "-o", "wide"]))
            k8s["commands"].append(run(["kubectl", "-n", namespace, "describe", "analysisrun", analysis_run]))

        k8s["commands"].append(run(["kubectl", "-n", namespace, "get", "pods", "-l", "app=demo-app", "-o", "wide"]))
        k8s["commands"].append(run(["kubectl", "-n", namespace, "get", "events", "--sort-by=.lastTimestamp"]))

        pod_names_cmd = run([
            "kubectl", "-n", namespace, "get", "pods",
            "-l", "app=demo-app",
            "-o", "jsonpath={range .items[*]}{.metadata.name}{\"\\n\"}{end}"
        ])
        k8s["commands"].append(pod_names_cmd)

        if pod_names_cmd["ok"]:
            pod_names = [x.strip() for x in pod_names_cmd["output"].splitlines() if x.strip()]
            for pod in pod_names[:3]:
                k8s["commands"].append(run(["kubectl", "-n", namespace, "logs", pod, "--tail=120"]))
    else:
        k8s["commands"].append(kubectl_check)

def metric_line(metric):
    name = metric.get("name", "unknown")
    phase = metric.get("phase", "unknown")
    value = metric.get("value", "")
    successful = metric.get("successful", 0)
    failed = metric.get("failed", 0)
    inconclusive = metric.get("inconclusive", 0)
    error = metric.get("error", 0)
    return f"- `{name}`：phase=`{phase}`，value=`{value}`，successful={successful}，failed={failed}，inconclusive={inconclusive}，error={error}"

def failure_summary_text():
    if not is_failure:
        return "当前 ReleaseContext 未显示明确失败信号，本脚本仅归档诊断上下文。"
    if "error-rate" in failed_metrics and "p95-latency" in failed_metrics:
        return "本次发布同时出现错误率和 P95 延迟门禁失败，属于多 SLO 失败，应停止继续扩大流量并优先排查 canary 版本。"
    if "error-rate" in failed_metrics:
        return "本次发布错误率门禁失败，说明 canary 版本 5xx 比例超过阈值，应优先检查应用日志、依赖调用和错误响应。"
    if "p95-latency" in failed_metrics:
        return "本次发布 P95 延迟门禁失败，说明 canary 版本尾延迟超过阈值，应优先检查慢请求、依赖耗时和资源压力。"
    if rollout_abort is True:
        return "本次 Rollout 已经 abort，应保持停止状态并检查 AnalysisRun 和 Rollout 事件。"
    if rollout_phase == "Degraded":
        return "本次 Rollout 进入 Degraded 状态，需要人工介入排查。"
    if analysis_phase == "Failed":
        return "本次 AnalysisRun 失败，需要检查失败指标和 Prometheus 查询结果。"
    return "本次发布存在失败信号，需要人工结合证据链排查。"

def next_action_text():
    if not is_failure:
        return "继续观察并归档记录。"
    if "error-rate" in failed_metrics or "p95-latency" in failed_metrics:
        return "停止继续扩大流量，检查 canary Pod 日志、AnalysisRun 指标值、Rollout 事件和本次变更内容。"
    if rollout_abort is True or rollout_phase == "Degraded":
        return "保持 Rollout 停止状态，检查 Rollout describe、AnalysisRun describe 和 Kubernetes Events。"
    return "人工查看 ReleaseContext、ReleaseReport、AI Decision、Policy Decision 和本故障证据文件。"

failure = {
    "schemaVersion": "failure.evidence/v1alpha1",
    "generatedBy": "collect-failure-evidence.sh",
    "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "sourceReleaseContext": str(ctx_path),
    "executionMode": "advisory_only",
    "isFailure": is_failure,
    "release": {
        "namespace": namespace,
        "rollout": rollout,
        "rolloutPhase": rollout_phase,
        "rolloutAbort": rollout_abort,
        "rolloutMessage": rollout_message,
        "analysisRun": analysis_run,
        "analysisRunPhase": analysis_phase,
        "failedMetrics": failed_metrics,
        "severity": severity,
        "riskScore": risk_score,
        "riskReasons": risk_reasons,
        "decision": decision,
        "recommendedAction": recommended_action
    },
    "analysisRunMetrics": analysis_metrics,
    "diagnosis": {
        "summary": failure_summary_text(),
        "recommendedNextAction": next_action_text(),
        "primarySignals": {
            "rolloutDegraded": rollout_phase == "Degraded",
            "rolloutAborted": rollout_abort is True,
            "analysisRunFailed": analysis_phase == "Failed",
            "failedMetricCount": len(failed_metrics)
        }
    },
    "kubernetesEvidence": k8s,
    "guardrails": {
        "autoExecute": False,
        "doesNotModifyGitOps": True,
        "doesNotModifyKubernetes": True,
        "doesNotRollback": True,
        "doesNotPromote": True,
        "doesNotPatchResources": True,
        "doesNotDeleteResources": True
    }
}

output_json.write_text(json.dumps(failure, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
latest_json.write_text(json.dumps(failure, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

metric_lines = "\n".join(metric_line(m) for m in analysis_metrics) if analysis_metrics else "无"
risk_reason_lines = "\n".join(f"- {r}" for r in risk_reasons) if risk_reasons else "- 无"
failed_metric_lines = "\n".join(f"- `{m}`" for m in failed_metrics) if failed_metrics else "本次没有明确失败的 SLO 门禁。"

k8s_status = "已启用" if collect_k8s else "未启用"
k8s_available = "是" if k8s.get("available") else "否"
k8s_command_count = len(k8s.get("commands") or [])

md = f"""<!--
Generated by collect-failure-evidence.sh
Source release context: {ctx_path}
-->

# 故障诊断证据

## 1. 诊断结论

{failure_summary_text()}

## 2. 发布状态

- Namespace：`{namespace}`
- Rollout：`{rollout}`
- Rollout Phase：`{rollout_phase}`
- Rollout Abort：`{str(rollout_abort).lower()}`
- AnalysisRun：`{analysis_run}`
- AnalysisRun Phase：`{analysis_phase}`
- Severity：`{severity}`
- Risk Score：`{risk_score}`
- Decision：`{decision}`
- Recommended Action：`{recommended_action}`

## 3. 失败的 SLO 门禁

{failed_metric_lines}

## 4. AnalysisRun 指标快照

{metric_lines}

## 5. 风险原因

{risk_reason_lines}

## 6. Rollout Message

~~~text
{rollout_message or "无"}
~~~

## 7. Kubernetes 证据采集状态

- 是否启用 K8s 采集：`{k8s_status}`
- kubectl 是否可用：`{k8s_available}`
- 已采集命令数量：`{k8s_command_count}`

详细命令输出请查看：

~~~text
{output_json}
~~~

## 8. K8s 现场证据时效性说明

{k8s_freshness_human_warning}

## 9. 建议下一步

{next_action_text()}

## 10. 安全边界

本故障证据仅用于人工诊断和 Agent 分析，不会自动执行 Rollback、Promote、Patch、Delete 或 GitOps 变更。当前系统仍保持 `advisory_only` 模式。
"""

output_md.write_text(md, encoding="utf-8")
latest_md.write_text(md, encoding="utf-8")

print(f"Failure evidence JSON generated: {output_json}")
print(f"Failure evidence Markdown generated: {output_md}")
print(f"Latest failure evidence JSON: {latest_json}")
print(f"Latest failure evidence Markdown: {latest_md}")
print(json.dumps({
    "isFailure": is_failure,
    "failedMetrics": failed_metrics,
    "severity": severity,
    "riskScore": risk_score,
    "k8sCollectionEnabled": collect_k8s,
    "k8sCommandCount": k8s_command_count
}, ensure_ascii=False, indent=2))
PY
