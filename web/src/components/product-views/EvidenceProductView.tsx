import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  GitBranch,
  ShieldCheck,
  TerminalSquare,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import { ProductMetricCard } from "@/components/common/ProductMetricCard"
import {
  actionDisplay,
  policyDisplay,
  resultDisplay,
} from "@/utils/format"
import {
  FailedMetricsPanel,
  parseJsonResource,
  RuleChipsPanel,
} from "./shared"
type EvidencePayload = {
  schemaVersion?: string
  generatedAt?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  requiresHumanApproval?: boolean
  safeToRetry?: boolean
  summary?: {
    rolloutPhase?: string
    rolloutAbort?: boolean
    analysisRunPhase?: string
    riskLevel?: string
    riskScore?: number
    changeRiskLevel?: string
    changeRiskScore?: number
    failedMetrics?: unknown[]
    matchedPolicyRules?: string[]
  }
  failedMetrics?: unknown[]
  matchedPolicyRules?: string[]
}

export function EvidenceProductView({ body }: { body: string }) {
  const evidence = parseJsonResource<EvidencePayload>(body)

  if (!evidence) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
        Evidence JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const summary = evidence.summary ?? {}
  const failedMetrics = Array.isArray(summary.failedMetrics)
    ? summary.failedMetrics
    : Array.isArray(evidence.failedMetrics)
      ? evidence.failedMetrics
      : []

  const matchedPolicyRules = Array.isArray(summary.matchedPolicyRules)
    ? summary.matchedPolicyRules
    : Array.isArray(evidence.matchedPolicyRules)
      ? evidence.matchedPolicyRules
      : []

  const releaseResult = evidence.releaseResult ?? "-"
  const policyDecision = evidence.policyDecision ?? "-"
  const finalAction = evidence.finalAction ?? "-"
  const rolloutPhase = summary.rolloutPhase ?? "-"
  const analysisRunPhase = summary.analysisRunPhase ?? "-"
  const riskLevel = summary.riskLevel ?? "-"
  const riskScore = summary.riskScore ?? 0
  const changeRiskLevel = summary.changeRiskLevel ?? "-"
  const changeRiskScore = summary.changeRiskScore ?? 0

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Evidence 决策视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            将 release-evidence JSON 提炼为发布结果、Rollout 状态、AnalysisRun 状态、风险和 SLO 门禁信息。
          </p>
        </div>
        <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="发布结果"
          value={resultDisplay(releaseResult)}
          rawValue={releaseResult}
          icon={CheckCircle2}
          hint="Release Evidence 最终结论"
          statusValue={releaseResult}
        />
        <ProductMetricCard
          label="策略裁决"
          value={policyDisplay(policyDecision)}
          rawValue={policyDecision}
          icon={ShieldCheck}
          hint="Policy Decision 结果"
          statusValue={policyDecision}
        />
        <ProductMetricCard
          label="最终动作"
          value={actionDisplay(finalAction)}
          rawValue={finalAction}
          icon={TerminalSquare}
          hint="策略评估后的建议动作"
          statusValue={finalAction}
        />
        <ProductMetricCard
          label="Rollout 阶段"
          value={rolloutPhase}
          rawValue={String(summary.rolloutAbort ?? false)}
          icon={GitBranch}
          hint="rawValue 表示 rolloutAbort"
          statusValue={rolloutPhase}
        />
        <ProductMetricCard
          label="AnalysisRun 阶段"
          value={analysisRunPhase}
          icon={Activity}
          hint="AnalysisRun 执行状态"
          statusValue={analysisRunPhase}
        />
        <ProductMetricCard
          label="失败指标"
          value={String(failedMetrics.length)}
          rawValue={failedMetrics.length > 0 ? "FAILED_METRICS_FOUND" : "NO_FAILED_METRICS"}
          icon={AlertTriangle}
          hint="失败的 SLO 门禁数量"
          statusValue={failedMetrics.length > 0 ? "REQUIRED" : "NOT REQUIRED"}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">风险摘要</h4>
          <KeyValueRows
            rows={[
              ["riskLevel", riskLevel],
              ["riskScore", String(riskScore)],
              ["changeRiskLevel", changeRiskLevel],
              ["changeRiskScore", String(changeRiskScore)],
              ["executionMode", evidence.executionMode ?? "-"],
              ["safeToRetry", String(evidence.safeToRetry ?? "-")],
            ]}
          />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">SLO 门禁</h4>
          <FailedMetricsPanel metrics={failedMetrics} />
        </div>
      </section>

      <RuleChipsPanel rules={matchedPolicyRules} />
    </div>
  )
}

