import {
  Activity,
  AlertTriangle,
  FileText,
  History,
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
  FailedMetricsPanel,
  parseJsonResource,
  RuleChipsPanel,
} from "./shared"

type HistoryRecord = {
  releaseId?: string
  generatedAt?: string
  appVersion?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  requiresHumanApproval?: boolean
  failedMetrics?: unknown[]
  riskLevel?: string
  riskScore?: number
  rolloutPhase?: string
  analysisRunPhase?: string
  sourceReleaseEvidence?: string
  failureEvidence?: string | null
  actionPlan?: string
  actionPlanCandidateCommandCount?: number
}

type IntelligencePayload = {
  schemaVersion?: string
  generatedBy?: string
  generatedAt?: string
  sourceReleaseEvidence?: string
  sourceReleaseMemory?: string
  release?: {
    releaseResult?: string
    policyDecision?: string
    finalAction?: string
    executionMode?: string
    requiresHumanApproval?: boolean
    safeToRetry?: boolean
    failedMetrics?: unknown[]
    riskLevel?: string
    riskScore?: number
    rolloutPhase?: string
    rolloutAbort?: boolean
    analysisRunPhase?: string
    currentMemoryRecordFound?: boolean
  }
  history?: {
    recordCount?: number
    passCount?: number
    failureCount?: number
    recentReleases?: HistoryRecord[]
    recentFailures?: HistoryRecord[]
    similarFailureCount?: number
    similarFailureIncludingCurrentCount?: number
    exactHistoricalMetricSetMatchCount?: number
    similarFailures?: HistoryRecord[]
    similarFailuresIncludingCurrent?: HistoryRecord[]
  }
  intelligence?: {
    riskPattern?: string
    repeatedRiskPattern?: boolean
    recommendedNextAction?: string
    conclusion?: string
    humanSummary?: string
  }
  artifacts?: Record<string, string | null>
  guardrails?: Record<string, boolean | string | number | null>
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function boolText(value?: boolean | null) {
  if (value === true) return "是"
  if (value === false) return "否"
  return "-"
}

function IntelligenceConclusionPanel({
  riskPattern,
  repeatedRiskPattern,
  conclusion,
  recommendedNextAction,
}: {
  riskPattern: string
  repeatedRiskPattern?: boolean | null
  conclusion?: string
  recommendedNextAction: string
}) {
  const healthyPattern = riskPattern.toLowerCase().includes("healthy")
  const statusValue = healthyPattern ? "PASS" : repeatedRiskPattern ? "REQUIRED" : "NOT REQUIRED"

  return (
    <div className={`rounded-2xl border p-5 ${
      healthyPattern
        ? "border-emerald-900/45 bg-emerald-950/20"
        : repeatedRiskPattern
          ? "border-rose-900/45 bg-rose-950/20"
          : "border-amber-900/45 bg-amber-950/20"
    }`}>
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="flex flex-wrap gap-2">
            <Badge value={statusValue} label={riskPattern} />
            <Badge
              value={repeatedRiskPattern ? "REQUIRED" : "NOT REQUIRED"}
              label={`repeated=${String(repeatedRiskPattern ?? "-")}`}
            />
            <Badge value={recommendedNextAction} label={recommendedNextAction} />
          </div>

          <h4 className={`mt-4 text-lg font-semibold ${
            healthyPattern
              ? "text-emerald-200"
              : repeatedRiskPattern
                ? "text-rose-200"
                : "text-amber-200"
          }`}>
            历史智能结论：{healthyPattern ? "健康发布模式" : repeatedRiskPattern ? "命中重复风险" : "需要结合历史记录判断"}
          </h4>
          <p className={`mt-2 max-w-4xl text-sm leading-6 ${
            healthyPattern
              ? "text-emerald-200"
              : repeatedRiskPattern
                ? "text-rose-200"
                : "text-amber-200"
          }`}>
            {conclusion || "当前 Intelligence 没有提供 humanSummary / conclusion。"}
          </p>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4 text-sm shadow-sm">
          <p className="text-slate-500">Intelligence 视图职责</p>
          <p className="mt-2 max-w-xs text-slate-300">
            这里重点判断历史上是否出现过类似风险，而不是解释 SLO 证据或执行动作。
          </p>
        </div>
      </div>
    </div>
  )
}

function HistoryStatsPanel({
  recordCount,
  passCount,
  failureCount,
  similarFailureCount,
  similarFailureIncludingCurrentCount,
  exactMetricSetMatchCount,
}: {
  recordCount: number
  passCount: number
  failureCount: number
  similarFailureCount: number
  similarFailureIncludingCurrentCount: number
  exactMetricSetMatchCount: number
}) {
  return (
    <section className="grid gap-3 md:grid-cols-3">
      <ProductMetricCard
        label="历史样本"
        value={String(recordCount)}
        rawValue={`${passCount} pass / ${failureCount} fail`}
        icon={History}
        hint="release-memory.jsonl 中参与分析的历史记录数"
        statusValue="PASS"
      />
      <ProductMetricCard
        label="历史失败"
        value={String(failureCount)}
        rawValue="failureCount"
        icon={AlertTriangle}
        hint="历史失败发布数量"
        statusValue={failureCount > 0 ? "REQUIRED" : "PASS"}
      />
      <ProductMetricCard
        label="相似失败"
        value={String(similarFailureCount)}
        rawValue={`includingCurrent=${similarFailureIncludingCurrentCount}`}
        icon={FileText}
        hint="与当前失败指标相似的历史失败数量"
        statusValue={similarFailureCount > 0 ? "REQUIRED" : "NOT REQUIRED"}
      />
      <ProductMetricCard
        label="指标集合完全匹配"
        value={String(exactMetricSetMatchCount)}
        rawValue="exactHistoricalMetricSetMatchCount"
        icon={Activity}
        hint="失败指标集合完全一致的历史次数"
        statusValue={exactMetricSetMatchCount > 0 ? "REQUIRED" : "NOT REQUIRED"}
      />
      <ProductMetricCard
        label="成功记录"
        value={String(passCount)}
        rawValue="passCount"
        icon={ShieldCheck}
        hint="历史成功发布数量"
        statusValue="PASS"
      />
      <ProductMetricCard
        label="失败占比"
        value={recordCount > 0 ? `${Math.round((failureCount / recordCount) * 100)}%` : "0%"}
        rawValue={`${failureCount}/${recordCount}`}
        icon={Sparkles}
        hint="用于快速观察历史风险密度"
        statusValue={failureCount > 0 ? "REQUIRED" : "PASS"}
      />
    </section>
  )
}

function CurrentReleasePanel({ intelligence }: { intelligence: IntelligencePayload }) {
  const release = intelligence.release ?? {}

  return (
    <section className="grid gap-4 lg:grid-cols-2">
      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-100">当前发布摘要</h4>
        <KeyValueRows
          rows={[
            ["releaseResult", resultDisplay(release.releaseResult ?? "-")],
            ["policyDecision", policyDisplay(release.policyDecision ?? "-")],
            ["finalAction", actionDisplay(release.finalAction ?? "-")],
            ["executionMode", release.executionMode ?? "-"],
            ["requiresHumanApproval", String(release.requiresHumanApproval ?? "-")],
            ["safeToRetry", String(release.safeToRetry ?? "-")],
            ["currentMemoryRecordFound", String(release.currentMemoryRecordFound ?? "-")],
          ]}
        />
      </div>

      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-100">当前风险摘要</h4>
        <KeyValueRows
          rows={[
            ["riskLevel", riskText(release.riskLevel ?? "-")],
            ["riskScore", String(release.riskScore ?? 0)],
            ["rolloutPhase", release.rolloutPhase ?? "-"],
            ["rolloutAbort", String(release.rolloutAbort ?? false)],
            ["analysisRunPhase", release.analysisRunPhase ?? "-"],
            ["failedMetricCount", String(release.failedMetrics?.length ?? 0)],
          ]}
        />
      </div>
    </section>
  )
}

function HistoryRecordList({
  title,
  description,
  records,
}: {
  title: string
  description: string
  records: HistoryRecord[]
}) {
  if (records.length === 0) {
    return (
      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4 text-sm text-slate-400">
        当前没有 {title}。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">{title}</h4>
        <p className="mt-1 text-xs text-slate-500">{description}</p>
      </div>

      <div className="divide-y divide-[#1f2b3d]">
        {records.slice(0, 6).map((record) => (
          <div key={`${record.releaseId}-${record.generatedAt}`} className="space-y-3 px-4 py-4">
            <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
              <div>
                <p className="font-mono text-sm font-semibold text-slate-100">
                  {record.releaseId ?? "-"}
                </p>
                <p className="mt-1 break-all text-xs text-slate-500">
                  {record.generatedAt ?? "-"}
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                <Badge value={record.releaseResult ?? "-"} label={resultDisplay(record.releaseResult ?? "-")} />
                <Badge value={record.riskLevel ?? "-"} label={riskText(record.riskLevel ?? "-")} />
              </div>
            </div>

            <KeyValueRows
              rows={[
                ["appVersion", record.appVersion ?? "-"],
                ["policyDecision", policyDisplay(record.policyDecision ?? "-")],
                ["finalAction", actionDisplay(record.finalAction ?? "-")],
                ["requiresHumanApproval", String(record.requiresHumanApproval ?? "-")],
                ["rolloutPhase", record.rolloutPhase ?? "-"],
                ["analysisRunPhase", record.analysisRunPhase ?? "-"],
                ["candidateCommandCount", String(record.actionPlanCandidateCommandCount ?? 0)],
              ]}
            />

            <FailedMetricsPanel metrics={record.failedMetrics ?? []} />
          </div>
        ))}
      </div>
    </div>
  )
}

function ArtifactsAndGuardrailsPanel({ intelligence }: { intelligence: IntelligencePayload }) {
  const artifactEntries = Object.entries(intelligence.artifacts ?? {})
  const guardrailEntries = Object.entries(intelligence.guardrails ?? {})

  return (
    <section className="grid gap-4 lg:grid-cols-2">
      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
        <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
          <h4 className="text-sm font-semibold text-slate-100">历史智能资源索引</h4>
        </div>
        <div className="divide-y divide-[#1f2b3d]">
          {artifactEntries.length === 0 ? (
            <div className="px-4 py-3 text-sm text-slate-400">没有 artifacts 字段。</div>
          ) : (
            artifactEntries.map(([key, value]) => (
              <div key={key} className="grid gap-2 px-4 py-3 text-sm md:grid-cols-[170px_1fr]">
                <span className="font-mono text-xs text-slate-500">{key}</span>
                <span className="break-all font-mono text-slate-100">{valueOrDash(value)}</span>
              </div>
            ))
          )}
        </div>
      </div>

      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
        <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
          <h4 className="text-sm font-semibold text-slate-100">只读分析边界</h4>
        </div>
        <div className="p-4">
          {guardrailEntries.length === 0 ? (
            <div className="text-sm text-slate-400">没有 guardrails 字段。</div>
          ) : (
            <RuleChipsPanel rules={guardrailEntries.map(([key, value]) => `${key}=${String(value)}`)} />
          )}
        </div>
      </div>
    </section>
  )
}

export function IntelligenceProductView({ body }: { body: string }) {
  const intelligence = parseJsonResource<IntelligencePayload>(body)

  if (!intelligence) {
    return (
      <div className="rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-300">
        Intelligence JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const release = intelligence.release ?? {}
  const history = intelligence.history ?? {}
  const insight = intelligence.intelligence ?? {}

  const riskPattern = insight.riskPattern ?? "-"
  const repeatedRiskPattern = insight.repeatedRiskPattern ?? null
  const recommendedNextAction = insight.recommendedNextAction ?? "-"
  const conclusion = insight.humanSummary ?? insight.conclusion

  const recordCount = history.recordCount ?? 0
  const passCount = history.passCount ?? 0
  const failureCount = history.failureCount ?? 0
  const similarFailureCount = history.similarFailureCount ?? 0
  const similarFailureIncludingCurrentCount = history.similarFailureIncludingCurrentCount ?? 0
  const exactMetricSetMatchCount = history.exactHistoricalMetricSetMatchCount ?? 0

  const recentFailures = history.recentFailures ?? []
  const recentReleases = history.recentReleases ?? []
  const similarFailures = history.similarFailures ?? []
  const focusFailures = similarFailures.length > 0 ? similarFailures : recentFailures

  return (
    <div className="space-y-5 rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-5">
      <div className="flex flex-col gap-3 border-b border-[#1f2b3d] pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-slate-100">Intelligence 历史风险识别视图</h4>
          <p className="mt-1 text-sm text-slate-400">
            重点回答：这类发布风险历史上是否出现过、是否重复、失败指标组合是否相似，以及下一步应该如何处理。
          </p>
        </div>
        <Badge value={riskPattern.toLowerCase().includes("healthy") ? "PASS" : repeatedRiskPattern ? "REQUIRED" : "NOT REQUIRED"} label={riskPattern} />
      </div>

      <IntelligenceConclusionPanel
        riskPattern={riskPattern}
        repeatedRiskPattern={repeatedRiskPattern}
        conclusion={conclusion}
        recommendedNextAction={recommendedNextAction}
      />

      <HistoryStatsPanel
        recordCount={recordCount}
        passCount={passCount}
        failureCount={failureCount}
        similarFailureCount={similarFailureCount}
        similarFailureIncludingCurrentCount={similarFailureIncludingCurrentCount}
        exactMetricSetMatchCount={exactMetricSetMatchCount}
      />

      <section className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="风险模式"
          value={riskPattern}
          icon={Sparkles}
          hint="历史智能识别出的风险模式"
          statusValue={riskPattern.toLowerCase().includes("healthy") ? "PASS" : repeatedRiskPattern ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="重复风险"
          value={boolText(repeatedRiskPattern)}
          rawValue={String(repeatedRiskPattern ?? "-")}
          icon={AlertTriangle}
          hint="是否命中重复风险模式"
          statusValue={repeatedRiskPattern ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="推荐下一步"
          value={recommendedNextAction}
          icon={TerminalSquare}
          hint="Intelligence 推荐的下一步动作"
          statusValue={recommendedNextAction.toLowerCase().includes("archive") ? "PASS" : recommendedNextAction}
        />
        <ProductMetricCard
          label="当前发布"
          value={resultDisplay(release.releaseResult ?? "-")}
          rawValue={release.policyDecision}
          icon={ShieldCheck}
          hint="当前发布结果引用"
          statusValue={release.releaseResult ?? "-"}
        />
        <ProductMetricCard
          label="当前风险"
          value={riskText(release.riskLevel ?? "-")}
          rawValue={`${release.riskLevel ?? "-"} / ${release.riskScore ?? 0}`}
          icon={Activity}
          hint="当前发布运行时风险"
          statusValue={release.riskLevel ?? "-"}
        />
        <ProductMetricCard
          label="当前失败指标"
          value={String(release.failedMetrics?.length ?? 0)}
          rawValue={(release.failedMetrics ?? []).join(", ") || "NO_FAILED_METRICS"}
          icon={FileText}
          hint="当前发布失败指标数量"
          statusValue={(release.failedMetrics?.length ?? 0) > 0 ? "REQUIRED" : "PASS"}
        />
      </section>

      <CurrentReleasePanel intelligence={intelligence} />

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-100">当前失败指标</h4>
          <FailedMetricsPanel metrics={release.failedMetrics ?? []} />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-100">智能建议摘要</h4>
          <KeyValueRows
            rows={[
              ["riskPattern", riskPattern],
              ["repeatedRiskPattern", String(repeatedRiskPattern ?? "-")],
              ["recommendedNextAction", recommendedNextAction],
              ["sourceReleaseEvidence", intelligence.sourceReleaseEvidence ?? "-"],
              ["sourceReleaseMemory", intelligence.sourceReleaseMemory ?? "-"],
              ["generatedAt", intelligence.generatedAt ?? "-"],
            ]}
          />
        </div>
      </section>

      <HistoryRecordList
        title={similarFailures.length > 0 ? "相似历史失败" : "最近历史失败"}
        description={similarFailures.length > 0 ? "与当前失败指标组合相似的历史失败。" : "最近失败记录，用于观察是否存在重复风险。"}
        records={focusFailures}
      />

      <HistoryRecordList
        title="最近发布记录"
        description="最近进入 release-memory 的发布记录，用于对比成功与失败模式。"
        records={recentReleases}
      />

      <ArtifactsAndGuardrailsPanel intelligence={intelligence} />

      <div className="rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4 text-sm text-slate-400">
        <div className="flex items-center gap-2 font-semibold text-slate-100">
          <ShieldCheck className="h-4 w-4" />
          Intelligence 视图边界
        </div>
        <p className="mt-2 leading-6">
          Intelligence 只做历史模式识别和只读分析，不修改 GitOps、不修改 Kubernetes、不执行 rollback / promote / patch / delete。
        </p>
      </div>
    </div>
  )
}

