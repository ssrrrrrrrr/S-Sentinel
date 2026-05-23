import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  Compass,
  FileText,
  GitBranch,
  Sparkles,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import { ProductMetricCard } from "@/components/common/ProductMetricCard"
import { ResourceMetadataPanel } from "@/components/release/ResourceMetadataPanel"
import type { LatestReleaseResponse, ReleaseIndexItem } from "@/types/release"
import {
  actionDisplay,
  normalize,
  policyDisplay,
  resultDisplay,
  riskText,
} from "@/utils/format"
import { RuleChipsPanel } from "./shared"

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function markdownSection(body: string, heading: string) {
  const pattern = new RegExp(`${escapeRegExp(heading)}\\s*\\n([\\s\\S]*?)(?=\\n##\\s|$)`, "i")
  return pattern.exec(body)?.[1]?.trim() ?? ""
}

function markdownCodeValueAfterLabel(body: string, label: string) {
  const pattern = new RegExp(`-\\s*${escapeRegExp(label)}[：:]\\s*\`([^\`]+)\``, "i")
  return pattern.exec(body)?.[1]?.trim() ?? "-"
}

function markdownPlainTextSection(body: string, heading: string) {
  return markdownSection(body, heading)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => !line.startsWith("<!--"))
    .join("\n")
    .trim()
}

function markdownCodeBulletsFromSection(body: string, heading: string) {
  return markdownSection(body, heading)
    .split(/\r?\n/)
    .map((line) => line.trim().match(/^-\s*`([^`]+)`/)?.[1]?.trim())
    .filter((value): value is string => Boolean(value))
}

function markdownArtifactCompleteness(body: string) {
  const section = markdownSection(body, "## 7. 证据文件")
  const lines = section.split(/\r?\n/).filter((line) => line.trim().startsWith("- "))
  const provided = lines.filter((line) => !line.includes("未提供")).length
  return {
    total: lines.length,
    provided,
  }
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function buildFocusTab({
  releaseResult,
  finalAction,
  repeatedRiskPattern,
}: {
  releaseResult: string
  finalAction: string
  repeatedRiskPattern: string
}) {
  if (normalize(releaseResult).includes("FAIL")) {
    if (repeatedRiskPattern === "true") return "Intelligence → Evidence → Action Plan"
    if (normalize(finalAction).includes("STOP")) return "Evidence → Action Plan"
    return "Evidence → Advisor Trace"
  }

  return "Context → Intelligence → Advisor Trace"
}

function ReleaseHeroPanel({
  releaseResult,
  policyDecision,
  finalAction,
  humanConclusion,
  nextStep,
  focusTab,
}: {
  releaseResult: string
  policyDecision: string
  finalAction: string
  humanConclusion: string
  nextStep: string
  focusTab: string
}) {
  const failed = normalize(releaseResult).includes("FAIL")

  return (
    <div className={`rounded-2xl border p-5 ${
      failed
        ? "border-rose-200 bg-rose-50"
        : "border-emerald-200 bg-emerald-50"
    }`}>
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="flex flex-wrap gap-2">
            <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
            <Badge value={policyDecision} label={policyDisplay(policyDecision)} />
            <Badge value={finalAction} label={actionDisplay(finalAction)} />
          </div>

          <h4 className={`mt-4 text-lg font-semibold ${failed ? "text-rose-950" : "text-emerald-950"}`}>
            发布总览结论：{failed ? "当前发布不安全，需要先处理风险" : "当前发布通过，可归档并继续观察"}
          </h4>

          <p className={`mt-2 max-w-4xl whitespace-pre-wrap text-sm leading-6 ${failed ? "text-rose-800" : "text-emerald-800"}`}>
            {humanConclusion || "当前摘要没有解析到人工结论。"}
          </p>
        </div>

        <div className="grid min-w-[280px] gap-3 rounded-xl border border-white/70 bg-white/80 p-4 text-sm shadow-sm">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Next Step</p>
            <p className="mt-2 font-semibold text-[#031a41]">{nextStep || "-"}</p>
          </div>
          <div className="border-t border-slate-200 pt-3">
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Recommended Tabs</p>
            <p className="mt-2 font-semibold text-[#031a41]">{focusTab}</p>
          </div>
        </div>
      </div>
    </div>
  )
}

function TabGuidePanel({
  releaseResult,
  repeatedRiskPattern,
}: {
  releaseResult: string
  repeatedRiskPattern: string
}) {
  const failed = normalize(releaseResult).includes("FAIL")

  const guides = failed
    ? [
        ["Evidence", "先看 SLO 证据链，确认哪些门禁失败以及为什么失败。"],
        ["Action Plan", "再看安全执行视图，确认 STOP_PROMOTION 等动作是否需要人工审批。"],
        ["Intelligence", repeatedRiskPattern === "true" ? "最后看历史智能，因为本次属于重复风险模式。" : "最后看历史智能，确认是否存在历史相似失败。"],
      ]
    : [
        ["Context", "先看发布对象和变更上下文，确认本次到底发布了什么。"],
        ["Intelligence", "再看历史智能，确认是否存在潜在重复风险。"],
        ["Advisor Trace", "最后看 Advisor 报告，用于归档和人工阅读。"],
      ]

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">推荐排查路径</h4>
        <p className="mt-1 text-xs text-slate-500">
          Overview 只做总览，不展开全部细节；具体问题跳转到对应 Tab。
        </p>
      </div>

      <div className="divide-y divide-slate-200">
        {guides.map(([tab, desc], index) => (
          <div key={tab} className="flex gap-3 px-4 py-3">
            <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[#031a41] text-xs font-bold text-white">
              {index + 1}
            </div>
            <div>
              <p className="font-semibold text-[#031a41]">{tab}</p>
              <p className="mt-1 text-sm leading-6 text-slate-600">{desc}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function OverviewBoundaryPanel({ latest }: { latest?: LatestReleaseResponse }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">系统安全边界</h4>
      </div>

      <div className="p-4">
        <KeyValueRows
          rows={[
            ["readOnly", String(latest?.safety?.readOnly ?? true)],
            ["willExecute", String(latest?.safety?.willExecute ?? false)],
            ["supportsRollback", String(latest?.safety?.supportsRollback ?? false)],
            ["supportsPromote", String(latest?.safety?.supportsPromote ?? false)],
            ["supportsDelete", String(latest?.safety?.supportsDelete ?? false)],
          ]}
        />
      </div>
    </div>
  )
}

export function OverviewProductView({
  body,
  selected,
  latest,
}: {
  body: string
  selected: ReleaseIndexItem
  latest?: LatestReleaseResponse
}) {
  const summary = selected.summary

  const releaseResult = summary.releaseResult || markdownCodeValueAfterLabel(body, "发布结果")
  const policyDecision = summary.policyDecision || markdownCodeValueAfterLabel(body, "策略裁决")
  const finalAction = summary.finalAction || markdownCodeValueAfterLabel(body, "最终动作")
  const executionMode = summary.executionMode || markdownCodeValueAfterLabel(body, "执行模式")
  const requiresHumanApproval = summary.requiresHumanApproval
  const safeToRetry = summary.safeToRetry

  const rolloutPhase = markdownCodeValueAfterLabel(body, "Rollout 阶段")
  const rolloutAbort = markdownCodeValueAfterLabel(body, "是否触发 Abort")
  const analysisRunPhase = markdownCodeValueAfterLabel(body, "AnalysisRun 阶段")

  const runtimeRiskLevel = summary.riskLevel || markdownCodeValueAfterLabel(body, "运行时风险等级")
  const runtimeRiskScore = Number.isFinite(summary.riskScore)
    ? summary.riskScore
    : Number(markdownCodeValueAfterLabel(body, "运行时风险分数") || 0)
  const changeRiskLevel = markdownCodeValueAfterLabel(body, "变更风险等级")
  const changeRiskScore = markdownCodeValueAfterLabel(body, "变更风险分数")

  const failedSloGates = markdownCodeBulletsFromSection(body, "## 4. 失败的 SLO 门禁")
  const matchedRules = markdownCodeBulletsFromSection(body, "## 5. 命中的策略规则")

  const policyReason = markdownPlainTextSection(body, "## 6. 策略裁决原因")
  const humanConclusion = markdownPlainTextSection(body, "## 9. 人工结论")
  const nextStep = markdownPlainTextSection(body, "## 10. 建议下一步")

  const riskPattern = markdownCodeValueAfterLabel(body, "Risk Pattern")
  const repeatedRiskPattern = markdownCodeValueAfterLabel(body, "Repeated Risk Pattern")
  const similarHistoricalFailureCount = markdownCodeValueAfterLabel(body, "Similar Historical Failure Count")
  const exactHistoricalMetricSetMatchCount = markdownCodeValueAfterLabel(body, "Exact Historical Metric Set Match Count")
  const recommendedNextAction = markdownCodeValueAfterLabel(body, "Recommended Next Action")

  const artifactCompleteness = markdownArtifactCompleteness(body)
  const focusTab = buildFocusTab({ releaseResult, finalAction, repeatedRiskPattern })

  const failed = normalize(releaseResult).includes("FAIL")
  const chainComplete = artifactCompleteness.total > 0 && artifactCompleteness.provided >= Math.min(artifactCompleteness.total, 7)

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Overview 发布总览</h4>
          <p className="mt-1 text-sm text-slate-600">
            只保留最终结论、当前风险、建议下一步和推荐查看路径，用于快速判断这次发布是否安全。
          </p>
        </div>
        <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
      </div>

      <ReleaseHeroPanel
        releaseResult={releaseResult}
        policyDecision={policyDecision}
        finalAction={finalAction}
        humanConclusion={humanConclusion}
        nextStep={nextStep}
        focusTab={focusTab}
      />

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="最终结论"
          value={resultDisplay(releaseResult)}
          rawValue={releaseResult}
          icon={CheckCircle2}
          hint={failed ? "发布未通过，需要先处理风险" : "发布通过，可以继续观察"}
          statusValue={releaseResult}
        />
        <ProductMetricCard
          label="当前风险"
          value={riskText(runtimeRiskLevel)}
          rawValue={`${runtimeRiskLevel} / ${runtimeRiskScore}`}
          icon={AlertTriangle}
          hint="运行时风险等级和分数"
          statusValue={runtimeRiskLevel}
        />
        <ProductMetricCard
          label="推荐下一步"
          value={recommendedNextAction !== "-" ? recommendedNextAction : finalAction}
          rawValue={nextStep}
          icon={Sparkles}
          hint="来自 Summary / Intelligence 的综合建议"
          statusValue={(recommendedNextAction !== "-" ? recommendedNextAction : finalAction).includes("archive") ? "PASS" : finalAction}
        />
        <ProductMetricCard
          label="Rollout"
          value={rolloutPhase}
          rawValue={`abort=${rolloutAbort}`}
          icon={GitBranch}
          hint="Rollout 当前状态"
          statusValue={rolloutPhase}
        />
        <ProductMetricCard
          label="AnalysisRun"
          value={analysisRunPhase}
          icon={Activity}
          hint="SLO AnalysisRun 状态"
          statusValue={analysisRunPhase}
        />
        <ProductMetricCard
          label="证据链完整度"
          value={`${artifactCompleteness.provided}/${artifactCompleteness.total || 0}`}
          rawValue={chainComplete ? "chain_complete" : "chain_incomplete"}
          icon={FileText}
          hint="证据文件是否基本齐全"
          statusValue={chainComplete ? "PASS" : "REQUIRED"}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <TabGuidePanel
          releaseResult={releaseResult}
          repeatedRiskPattern={repeatedRiskPattern}
        />

        <div className="space-y-4">
          <div className="space-y-3">
            <h4 className="text-sm font-semibold text-slate-900">发布链路摘要</h4>
            <KeyValueRows
              rows={[
                ["releaseId", selected.releaseId],
                ["executionMode", executionMode],
                ["policyDecision", policyDisplay(policyDecision)],
                ["finalAction", actionDisplay(finalAction)],
                ["requiresHumanApproval", String(requiresHumanApproval)],
                ["safeToRetry", String(safeToRetry)],
              ]}
            />
          </div>
        </div>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-slate-200 bg-white">
          <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
            <h4 className="text-sm font-semibold text-slate-900">SLO 门禁总览</h4>
          </div>
          <div className="p-4">
            {failedSloGates.length > 0 ? (
              <RuleChipsPanel rules={failedSloGates} />
            ) : (
              <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">
                当前发布没有失败的 SLO 门禁。
              </div>
            )}
          </div>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white">
          <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
            <h4 className="text-sm font-semibold text-slate-900">Policy Rules</h4>
          </div>
          <div className="p-4">
            <RuleChipsPanel rules={matchedRules} />
          </div>
        </div>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">策略裁决原因</h4>
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm leading-6 text-slate-700">
            {policyReason || "-"}
          </div>
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">历史智能摘要</h4>
          <KeyValueRows
            rows={[
              ["riskPattern", riskPattern],
              ["repeatedRiskPattern", repeatedRiskPattern],
              ["similarHistoricalFailureCount", similarHistoricalFailureCount],
              ["exactHistoricalMetricSetMatchCount", exactHistoricalMetricSetMatchCount],
              ["recommendedNextAction", recommendedNextAction],
            ]}
          />
        </div>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">风险摘要</h4>
          <KeyValueRows
            rows={[
              ["runtimeRiskLevel", riskText(runtimeRiskLevel)],
              ["runtimeRiskScore", String(runtimeRiskScore)],
              ["changeRiskLevel", riskText(changeRiskLevel)],
              ["changeRiskScore", valueOrDash(changeRiskScore)],
              ["failedSloGateCount", String(failedSloGates.length)],
              ["focusTab", focusTab],
            ]}
          />
        </div>

        <OverviewBoundaryPanel latest={latest} />
      </section>

      <ResourceMetadataPanel selected={selected} />

      <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
        <div className="flex items-center gap-2 font-semibold text-[#031a41]">
          <Compass className="h-4 w-4" />
          Overview 视图边界
        </div>
        <p className="mt-2 leading-6">
          Overview 只做发布总览和导航收口，不展开完整证据、变更上下文、历史风险或执行命令。详细判断请分别查看 Evidence、Context、Intelligence、Advisor Trace 和 Action Plan。
        </p>
      </div>
    </div>
  )
}


