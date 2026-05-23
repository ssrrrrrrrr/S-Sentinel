import {
  AlertTriangle,
  Bot,
  CheckCircle2,
  FileText,
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

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function markdownSection(body: string, heading: string) {
  const pattern = new RegExp(`${escapeRegExp(heading)}\\s*\\n([\\s\\S]*?)(?=\\n##\\s|$)`, "i")
  return pattern.exec(body)?.[1]?.trim() ?? ""
}

function markdownSectionBullets(body: string, heading: string) {
  return markdownSection(body, heading)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("- "))
    .map((line) => line.replace(/^-+\s*/, "").trim())
    .filter(Boolean)
}

function compactText(value: string) {
  return value
    .replace(/\n{3,}/g, "\n\n")
    .trim()
}

function AdvisorConclusionPanel({
  conclusion,
  releaseResult,
  finalAction,
  advisorFallback,
}: {
  conclusion: string
  releaseResult: string
  finalAction: string
  advisorFallback: boolean
}) {
  const isPass = releaseResult === "PASS"

  return (
    <div className={`rounded-2xl border p-5 ${
      isPass
        ? "border-emerald-200 bg-emerald-50"
        : "border-rose-200 bg-rose-50"
    }`}>
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="flex flex-wrap gap-2">
            <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
            <Badge value={finalAction} label={actionDisplay(finalAction)} />
            <Badge
              value={advisorFallback ? "REQUIRED" : "PASS"}
              label={advisorFallback ? "规则兜底" : "模型建议"}
            />
          </div>

          <h4 className={`mt-4 text-lg font-semibold ${isPass ? "text-emerald-950" : "text-rose-950"}`}>
            Advisor 结论：{isPass ? "发布可继续观察" : "发布需要人工排查"}
          </h4>
          <p className={`mt-2 max-w-4xl whitespace-pre-wrap text-sm leading-6 ${isPass ? "text-emerald-800" : "text-rose-800"}`}>
            {conclusion || "当前 Advice 没有解析到结论段落。"}
          </p>
        </div>

        <div className={`rounded-xl border bg-white/80 p-4 text-sm shadow-sm ${
          isPass ? "border-emerald-100" : "border-rose-100"
        }`}>
          <p className="text-slate-500">Advisor Trace 视图职责</p>
          <p className="mt-2 max-w-xs text-slate-700">
            这里重点展示 AI / 规则如何解释这次发布，以及给人看的处理建议。
          </p>
        </div>
      </div>
    </div>
  )
}

function AdvisorRuntimePanel({
  model,
  ollamaUrl,
  ollamaTimeout,
  ollamaNumCtx,
  ollamaNumPredict,
  advisorFallback,
  hasSafetyBoundary,
}: {
  model: string
  ollamaUrl: string
  ollamaTimeout: string
  ollamaNumCtx: string
  ollamaNumPredict: string
  advisorFallback: boolean
  hasSafetyBoundary: boolean
}) {
  return (
    <section className="grid gap-4 lg:grid-cols-2">
      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-900">模型调用上下文</h4>
        <KeyValueRows
          rows={[
            ["model", model || "-"],
            ["ollamaUrl", ollamaUrl || "-"],
            ["ollamaTimeoutSeconds", ollamaTimeout || "-"],
            ["ollamaNumCtx", ollamaNumCtx || "-"],
            ["ollamaNumPredict", ollamaNumPredict || "-"],
          ]}
        />
      </div>

      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-900">Advisor 执行状态</h4>
        <KeyValueRows
          rows={[
            ["advisorMode", advisorFallback ? "deterministic_rule_fallback" : "llm_generated"],
            ["fallbackDetected", String(advisorFallback)],
            ["safetyBoundaryDetected", String(hasSafetyBoundary)],
            ["readOnlyAnalysis", String(hasSafetyBoundary)],
          ]}
        />
      </div>
    </section>
  )
}

function RecommendationPanel({
  impactText,
  recommendationSteps,
  riskReasons,
}: {
  impactText: string
  recommendationSteps: string[]
  riskReasons: string[]
}) {
  return (
    <section className="grid gap-4 lg:grid-cols-2">
      <div className="rounded-xl border border-slate-200 bg-white">
        <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
          <h4 className="text-sm font-semibold text-slate-900">影响范围判断</h4>
        </div>
        <div className="p-4 text-sm leading-6 text-slate-700">
          {impactText ? (
            <p className="whitespace-pre-wrap">{compactText(impactText)}</p>
          ) : (
            <p>当前 Advice 没有解析到影响范围段落。</p>
          )}
        </div>
      </div>

      <div className="rounded-xl border border-slate-200 bg-white">
        <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
          <h4 className="text-sm font-semibold text-slate-900">建议动作</h4>
        </div>
        <div className="p-4">
          {recommendationSteps.length > 0 ? (
            <RuleChipsPanel rules={recommendationSteps} />
          ) : (
            <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
              当前 Advice 没有解析到建议动作列表。
            </div>
          )}
        </div>
      </div>

      <div className="lg:col-span-2">
        <div className="rounded-xl border border-slate-200 bg-white">
          <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
            <h4 className="text-sm font-semibold text-slate-900">Release Risk Reasons</h4>
          </div>
          <div className="p-4">
            {riskReasons.length > 0 ? (
              <RuleChipsPanel rules={riskReasons} />
            ) : (
              <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">
                当前 Advice 没有风险原因列表。
              </div>
            )}
          </div>
        </div>
      </div>
    </section>
  )
}

function PolicyAdvisorPanel({
  policyDecision,
  finalAction,
  executionMode,
  requiresHumanApproval,
  policyReason,
  matchedPolicyRules,
}: {
  policyDecision: string
  finalAction: string
  executionMode: string
  requiresHumanApproval: boolean | null
  policyReason: string
  matchedPolicyRules: string[]
}) {
  return (
    <section className="grid gap-4 lg:grid-cols-2">
      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-900">Policy Evaluator Decision</h4>
        <KeyValueRows
          rows={[
            ["policyDecision", policyDisplay(policyDecision)],
            ["finalAction", actionDisplay(finalAction)],
            ["executionMode", executionMode || "-"],
            ["requiresHumanApproval", String(requiresHumanApproval ?? "-")],
            ["reason", policyReason || "-"],
          ]}
        />
      </div>

      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-900">Matched Policy Rules</h4>
        <RuleChipsPanel rules={matchedPolicyRules} />
      </div>
    </section>
  )
}

function IntelligenceAdvisorPanel({
  riskPattern,
  repeatedRiskPattern,
  similarHistoricalFailureCount,
  exactHistoricalMetricSetMatchCount,
  recommendedNextAction,
  intelligenceText,
}: {
  riskPattern: string
  repeatedRiskPattern: boolean | null
  similarHistoricalFailureCount: number
  exactHistoricalMetricSetMatchCount: number
  recommendedNextAction: string
  intelligenceText: string
}) {
  return (
    <section className="grid gap-4 lg:grid-cols-2">
      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-900">Release Intelligence Summary</h4>
        <KeyValueRows
          rows={[
            ["riskPattern", riskPattern || "-"],
            ["repeatedRiskPattern", String(repeatedRiskPattern ?? "-")],
            ["similarHistoricalFailureCount", String(similarHistoricalFailureCount)],
            ["exactHistoricalMetricSetMatchCount", String(exactHistoricalMetricSetMatchCount)],
            ["recommendedNextAction", recommendedNextAction || "-"],
          ]}
        />
      </div>

      <div className="rounded-xl border border-slate-200 bg-white">
        <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
          <h4 className="text-sm font-semibold text-slate-900">历史智能解释</h4>
        </div>
        <div className="p-4 text-sm leading-6 text-slate-700">
          {intelligenceText ? (
            <p className="whitespace-pre-wrap">{compactText(intelligenceText)}</p>
          ) : (
            <p>当前 Advice 没有额外历史智能解释。</p>
          )}
        </div>
      </div>
    </section>
  )
}

export function AIAdviceProductView({ body }: { body: string }) {
  const model = markdownValue(body, "Model")
  const ollamaUrl = markdownValue(body, "Ollama URL")
  const ollamaTimeout = markdownValue(body, "Ollama Timeout Seconds")
  const ollamaNumCtx = markdownValue(body, "Ollama Num Ctx")
  const ollamaNumPredict = markdownValue(body, "Ollama Num Predict")

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

  const conclusionText = markdownSection(body, "## 1. 结论")
  const impactText = markdownSection(body, "## 5. 影响范围")
  const intelligenceText = markdownSection(body, "## 9. Release Intelligence Summary")
    .split("### Similar Historical Failures")[0]
    .trim()

  const recommendationSteps = markdownSectionBullets(body, "## 6. 建议动作")
  const riskReasons = markdownListAfterHeading(body, "### Release Risk Reasons")
  const matchedPolicyRules = markdownListAfterHeading(body, "### Matched Policy Rules")

  const advisorFallback = markdownContainsAny(body, [
    "Ollama 调用失败",
    "已使用确定性规则生成报告",
    "deterministic",
  ])

  const ollamaTimedOut =
    markdownBooleanValue(body, "Ollama Timed Out") === true ||
    markdownBooleanValue(body, "OllamaTimedOut") === true ||
    markdownBooleanValue(body, "Model Timed Out") === true

  const hasSafetyBoundary = markdownContainsAny(body, ["Safety Boundary", "read-only analysis"])

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Advisor Trace 建议报告视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            重点回答：AI / 规则如何解释本次发布、给出了什么人工建议，以及当前建议是否处于只读安全边界内。
          </p>
        </div>
        <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
      </div>

      <AdvisorConclusionPanel
        conclusion={conclusionText}
        releaseResult={releaseResult}
        finalAction={finalAction}
        advisorFallback={advisorFallback}
      />

      <section className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="Advisor 模式"
          value={advisorFallback ? "规则兜底" : "模型建议"}
          rawValue={model || "-"}
          icon={Bot}
          hint="LLM 不可用时使用确定性规则生成建议"
          statusValue={advisorFallback ? "REQUIRED" : "PASS"}
        />
        <ProductMetricCard
          label="策略动作"
          value={actionDisplay(finalAction)}
          rawValue={finalAction}
          icon={TerminalSquare}
          hint={policyReason || "Policy Evaluator Decision"}
          statusValue={finalAction}
        />
        <ProductMetricCard
          label="推荐下一步"
          value={recommendedNextAction || "-"}
          icon={Sparkles}
          hint="Release Intelligence 推荐动作"
          statusValue={recommendedNextAction.toLowerCase().includes("archive") ? "PASS" : recommendedNextAction}
        />
        <ProductMetricCard
          label="变更风险"
          value={riskText(changeRiskLevel)}
          rawValue={`${changeRiskLevel || "-"} / ${changeRiskScore}`}
          icon={AlertTriangle}
          hint="Change Risk Level / Score"
          statusValue={changeRiskLevel}
        />
        <ProductMetricCard
          label="运行风险"
          value={riskText(releaseSeverity)}
          rawValue={`${releaseSeverity || "-"} / ${releaseRiskScore}`}
          icon={CheckCircle2}
          hint="Release Severity / Risk Score"
          statusValue={releaseSeverity}
        />
        <ProductMetricCard
          label="安全边界"
          value={hasSafetyBoundary ? "只读分析" : "未检测到"}
          rawValue={`ollamaTimedOut=${String(ollamaTimedOut)}`}
          icon={ShieldCheck}
          hint="不会执行 Rollback / Promote / Patch / Delete"
          statusValue={hasSafetyBoundary ? "PASS" : "REQUIRED"}
        />
      </section>

      <AdvisorRuntimePanel
        model={model}
        ollamaUrl={ollamaUrl}
        ollamaTimeout={ollamaTimeout}
        ollamaNumCtx={ollamaNumCtx}
        ollamaNumPredict={ollamaNumPredict}
        advisorFallback={advisorFallback}
        hasSafetyBoundary={hasSafetyBoundary}
      />

      <RecommendationPanel
        impactText={impactText}
        recommendationSteps={recommendationSteps}
        riskReasons={riskReasons}
      />

      <PolicyAdvisorPanel
        policyDecision={policyDecision}
        finalAction={finalAction}
        executionMode={executionMode}
        requiresHumanApproval={requiresHumanApproval}
        policyReason={policyReason}
        matchedPolicyRules={matchedPolicyRules}
      />

      <IntelligenceAdvisorPanel
        riskPattern={riskPattern}
        repeatedRiskPattern={repeatedRiskPattern}
        similarHistoricalFailureCount={similarHistoricalFailureCount}
        exactHistoricalMetricSetMatchCount={exactHistoricalMetricSetMatchCount}
        recommendedNextAction={recommendedNextAction}
        intelligenceText={intelligenceText}
      />

      <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
        <div className="flex items-center gap-2 font-semibold text-[#031a41]">
          <FileText className="h-4 w-4" />
          Advisor Trace 视图边界
        </div>
        <p className="mt-2 leading-6">
          Advisor Trace 是给人工阅读的解释报告。它不会执行发布动作；真正的判断证据请看 Evidence，安全动作建议请看 Action Plan，历史模式请看 Intelligence。
        </p>
      </div>
    </div>
  )
}

