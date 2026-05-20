import {
  Activity,
  AlertTriangle,
  FileText,
  ShieldCheck,
  Sparkles,
  TerminalSquare,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import { ProductMetricCard } from "@/components/common/ProductMetricCard"
import { riskText } from "@/utils/format"
import {
  arrayFromPaths,
  booleanFromPaths,
  FailedMetricsPanel,
  JsonRecord,
  numberFromPaths,
  parseJsonResource,
  stringFromPaths,
  stringifyValue,
} from "./shared"
function HistoryRecordsPanel({ records }: { records: unknown[] }) {
  if (records.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Intelligence 没有关联历史记录。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">关联历史记录</h4>
      </div>
      <div className="divide-y divide-slate-200">
        {records.slice(0, 5).map((record, index) => (
          <pre
            key={index}
            className="max-h-40 overflow-auto whitespace-pre-wrap px-4 py-3 text-xs leading-6 text-slate-700"
          >
            {stringifyValue(record)}
          </pre>
        ))}
      </div>
    </div>
  )
}

export function IntelligenceProductView({ body }: { body: string }) {
  const intelligence = parseJsonResource<JsonRecord>(body)

  if (!intelligence) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
        Intelligence JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const riskPattern = stringFromPaths(intelligence, [
    ["riskPattern"],
    ["summary", "riskPattern"],
    ["intelligence", "riskPattern"],
    ["history", "riskPattern"],
    ["memory", "riskPattern"],
    ["releaseMemory", "riskPattern"],
  ])

  const repeatedRiskPattern = booleanFromPaths(intelligence, [
    ["repeatedRiskPattern"],
    ["summary", "repeatedRiskPattern"],
    ["intelligence", "repeatedRiskPattern"],
    ["history", "repeatedRiskPattern"],
    ["memory", "repeatedRiskPattern"],
    ["releaseMemory", "repeatedRiskPattern"],
  ])

  const similarHistoricalFailureCount = numberFromPaths(intelligence, [
    ["similarHistoricalFailureCount"],
    ["summary", "similarHistoricalFailureCount"],
    ["intelligence", "similarHistoricalFailureCount"],
    ["history", "similarHistoricalFailureCount"],
    ["memory", "similarHistoricalFailureCount"],
    ["releaseMemory", "similarHistoricalFailureCount"],
  ])

  const exactHistoricalMetricSetMatchCount = numberFromPaths(intelligence, [
    ["exactHistoricalMetricSetMatchCount"],
    ["summary", "exactHistoricalMetricSetMatchCount"],
    ["intelligence", "exactHistoricalMetricSetMatchCount"],
    ["history", "exactHistoricalMetricSetMatchCount"],
    ["memory", "exactHistoricalMetricSetMatchCount"],
    ["releaseMemory", "exactHistoricalMetricSetMatchCount"],
  ])

  const recommendedNextAction = stringFromPaths(intelligence, [
    ["recommendedNextAction"],
    ["summary", "recommendedNextAction"],
    ["intelligence", "recommendedNextAction"],
    ["history", "recommendedNextAction"],
    ["memory", "recommendedNextAction"],
    ["releaseMemory", "recommendedNextAction"],
    ["recommendation", "nextAction"],
  ])

  const releaseResult = stringFromPaths(intelligence, [
    ["releaseResult"],
    ["release", "releaseResult"],
    ["summary", "releaseResult"],
  ])

  const policyDecision = stringFromPaths(intelligence, [
    ["policyDecision"],
    ["release", "policyDecision"],
    ["summary", "policyDecision"],
  ])

  const finalAction = stringFromPaths(intelligence, [
    ["finalAction"],
    ["release", "finalAction"],
    ["summary", "finalAction"],
  ])

  const riskLevel = stringFromPaths(intelligence, [
    ["riskLevel"],
    ["release", "riskLevel"],
    ["summary", "riskLevel"],
  ])

  const riskScore = numberFromPaths(intelligence, [
    ["riskScore"],
    ["release", "riskScore"],
    ["summary", "riskScore"],
  ])

  const rolloutPhase = stringFromPaths(intelligence, [
    ["rolloutPhase"],
    ["release", "rolloutPhase"],
    ["summary", "rolloutPhase"],
  ])

  const analysisRunPhase = stringFromPaths(intelligence, [
    ["analysisRunPhase"],
    ["release", "analysisRunPhase"],
    ["summary", "analysisRunPhase"],
  ])

  const failedMetrics = arrayFromPaths(intelligence, [
    ["failedMetrics"],
    ["release", "failedMetrics"],
    ["summary", "failedMetrics"],
  ])

  const historyRecords = arrayFromPaths(intelligence, [
    ["similarHistoricalFailures"],
    ["historicalFailures"],
    ["matchedHistoricalRecords"],
    ["relatedHistoricalRecords"],
    ["history", "records"],
    ["memory", "records"],
    ["releaseMemory", "records"],
  ])

  const repeatedText = repeatedRiskPattern === null ? "-" : repeatedRiskPattern ? "是" : "否"
  const healthyPattern = riskPattern.toLowerCase().includes("healthy")
  const riskPatternStatus = healthyPattern ? "PASS" : repeatedRiskPattern ? "REQUIRED" : "NOT REQUIRED"

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Intelligence 历史智能视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            将 release-intelligence JSON 提炼为历史风险模式、重复风险、相似失败次数和推荐下一步动作。
          </p>
        </div>
        <Badge value={riskPatternStatus} label={riskPattern} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="风险模式"
          value={riskPattern}
          icon={Sparkles}
          hint="历史智能识别出的风险模式"
          statusValue={riskPatternStatus}
        />
        <ProductMetricCard
          label="重复风险"
          value={repeatedText}
          rawValue={String(repeatedRiskPattern ?? "-")}
          icon={AlertTriangle}
          hint="是否命中重复风险模式"
          statusValue={repeatedRiskPattern ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="相似历史失败"
          value={String(similarHistoricalFailureCount)}
          rawValue="similarHistoricalFailureCount"
          icon={FileText}
          hint="相似历史失败次数"
          statusValue={similarHistoricalFailureCount > 0 ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="指标完全匹配"
          value={String(exactHistoricalMetricSetMatchCount)}
          rawValue="exactHistoricalMetricSetMatchCount"
          icon={Activity}
          hint="失败指标集合完全匹配次数"
          statusValue={exactHistoricalMetricSetMatchCount > 0 ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="推荐下一步"
          value={recommendedNextAction}
          icon={TerminalSquare}
          hint="Intelligence 推荐的下一步动作"
          statusValue={recommendedNextAction.toLowerCase().includes("archive") ? "PASS" : recommendedNextAction}
        />
        <ProductMetricCard
          label="当前风险"
          value={riskText(riskLevel)}
          rawValue={`${riskLevel} / ${riskScore}`}
          icon={ShieldCheck}
          hint="当前发布运行时风险"
          statusValue={riskLevel}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">当前发布摘要</h4>
          <KeyValueRows
            rows={[
              ["releaseResult", releaseResult],
              ["policyDecision", policyDecision],
              ["finalAction", finalAction],
              ["rolloutPhase", rolloutPhase],
              ["analysisRunPhase", analysisRunPhase],
              ["failedMetricCount", String(failedMetrics.length)],
            ]}
          />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">失败指标 / 历史关联</h4>
          <FailedMetricsPanel metrics={failedMetrics} />
        </div>
      </section>

      <HistoryRecordsPanel records={historyRecords} />
    </div>
  )
}

