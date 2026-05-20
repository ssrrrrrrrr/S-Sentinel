import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  ShieldCheck,
  Sparkles,
  TerminalSquare,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import { ProductMetricCard } from "@/components/common/ProductMetricCard"
import {
  actionDisplay,
  policyDisplay,
  resultDisplay,
  riskText,
} from "@/utils/format"
import {
  markdownBooleanValue,
  markdownContainsAny,
  markdownListAfterHeading,
  markdownNumberValue,
  markdownValue,
  RuleChipsPanel,
} from "./shared"
export function AIAdviceProductView({ body }: { body: string }) {
  const model = markdownValue(body, "Model")
  const ollamaTimeout = markdownValue(body, "Ollama Timeout Seconds")
  const changeRiskLevel = markdownValue(body, "Change Risk Level")
  const changeRiskScore = markdownNumberValue(body, "Change Risk Score")
  const releaseResult = markdownValue(body, "Release Result")
  const releaseSeverity = markdownValue(body, "Release Severity")
  const releaseRiskScore = markdownNumberValue(body, "Release Risk Score")
  const policyDecision = markdownValue(body, "Policy Decision")
  const finalAction = markdownValue(body, "Final Action")
  const executionMode = markdownValue(body, "Execution Mode")
  const requiresHumanApproval = markdownBooleanValue(body, "Requires Human Approval")
  const policyReason = markdownValue(body, "Reason")
  const riskPattern = markdownValue(body, "Risk Pattern")
  const repeatedRiskPattern = markdownBooleanValue(body, "Repeated Risk Pattern")
  const similarHistoricalFailureCount = markdownNumberValue(body, "Similar Historical Failure Count")
  const exactHistoricalMetricSetMatchCount = markdownNumberValue(body, "Exact Historical Metric Set Match Count")
  const recommendedNextAction = markdownValue(body, "Recommended Next Action")
  const matchedPolicyRules = markdownListAfterHeading(body, "### Matched Policy Rules")
  const ollamaTimedOut = markdownContainsAny(body, ["timed out", "Ollama 调用失败", "Ollama"])
  const hasSafetyBoundary = markdownContainsAny(body, ["Safety Boundary", "read-only analysis"])

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">AI Advice 决策视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            将 AI Advice Markdown 提炼为模型信息、发布结论、策略动作、历史智能和安全边界。
          </p>
        </div>
        <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="发布结论"
          value={resultDisplay(releaseResult)}
          rawValue={releaseResult}
          icon={CheckCircle2}
          hint="AI Advice 引用的发布结果"
          statusValue={releaseResult}
        />
        <ProductMetricCard
          label="策略动作"
          value={actionDisplay(finalAction)}
          rawValue={finalAction}
          icon={TerminalSquare}
          hint={policyReason}
          statusValue={finalAction}
        />
        <ProductMetricCard
          label="策略裁决"
          value={policyDisplay(policyDecision)}
          rawValue={policyDecision}
          icon={ShieldCheck}
          hint="Policy Evaluator Decision"
          statusValue={policyDecision}
        />
        <ProductMetricCard
          label="变更风险"
          value={riskText(changeRiskLevel)}
          rawValue={`${changeRiskLevel} / ${changeRiskScore}`}
          icon={AlertTriangle}
          hint="Change Risk Level / Score"
          statusValue={changeRiskLevel}
        />
        <ProductMetricCard
          label="运行风险"
          value={riskText(releaseSeverity)}
          rawValue={`${releaseSeverity} / ${releaseRiskScore}`}
          icon={Activity}
          hint="Release Severity / Risk Score"
          statusValue={releaseSeverity}
        />
        <ProductMetricCard
          label="推荐下一步"
          value={recommendedNextAction}
          icon={Sparkles}
          hint="Release Intelligence 推荐动作"
          statusValue={recommendedNextAction.toLowerCase().includes("archive") ? "PASS" : recommendedNextAction}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">模型与执行上下文</h4>
          <KeyValueRows
            rows={[
              ["model", model],
              ["ollamaTimeout", ollamaTimeout],
              ["executionMode", executionMode],
              ["requiresHumanApproval", String(requiresHumanApproval ?? "-")],
              ["ollamaTimedOut", String(ollamaTimedOut)],
              ["safetyBoundary", String(hasSafetyBoundary)],
            ]}
          />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">历史智能摘要</h4>
          <KeyValueRows
            rows={[
              ["riskPattern", riskPattern],
              ["repeatedRiskPattern", String(repeatedRiskPattern ?? "-")],
              ["similarFailureCount", String(similarHistoricalFailureCount)],
              ["metricSetMatchCount", String(exactHistoricalMetricSetMatchCount)],
              ["nextAction", recommendedNextAction],
            ]}
          />
        </div>
      </section>

      <RuleChipsPanel rules={matchedPolicyRules} />

      {ollamaTimedOut ? (
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          <h4 className="font-semibold text-amber-900">模型调用状态提示</h4>
          <p className="mt-1 leading-6">
            Advice 中检测到 Ollama 调用超时或降级信息。当前报告仍然保留了确定性规则分析结果，但后续可以优化模型超时、上下文长度和编码输出。
          </p>
        </div>
      ) : null}
    </div>
  )
}

