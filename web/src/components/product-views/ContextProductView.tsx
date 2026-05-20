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
  resultDisplay,
  riskText,
} from "@/utils/format"
import {
  FailedMetricsPanel,
  parseJsonResource,
  RuleChipsPanel,
  stringifyValue,
} from "./shared"
type AnalysisRunMetric = {
  name?: string
  phase?: string
  message?: string
  value?: string
  successful?: number
  failed?: number
  inconclusive?: number
  error?: number
}

type EnvChange = {
  name?: string
  previous?: string
  current?: string
  changed?: boolean
  risk?: string
}

type ContextPayload = {
  generatedAt?: string
  namespace?: string
  rollout?: string
  rolloutPhase?: string
  rolloutAbort?: boolean
  rolloutMessage?: string
  stableReplicaSet?: string
  currentDesiredVersion?: string
  analysisRun?: string
  analysisRunPhase?: string
  failedMetric?: string
  failedMetrics?: unknown[]
  analysisRunMetrics?: AnalysisRunMetric[]
  severity?: string
  riskScore?: number
  riskReasons?: string[]
  changeContextFile?: string
  changeRiskLevel?: string
  changeRiskScore?: number
  changeRiskHints?: string[]
  changeContext?: {
    changeType?: string
    app?: string
    namespace?: string
    generatedAt?: string
    git?: {
      baseRef?: string
      previousCommit?: string
      currentCommit?: string
      commitMessage?: string
    }
    image?: {
      previous?: string
      current?: string
      changed?: boolean
    }
    envChanges?: EnvChange[]
    riskLevel?: string
    riskScore?: number
    riskHints?: string[]
  }
  result?: string
  reason?: string
  decision?: string
  recommendedAction?: string
}

function AnalysisMetricsPanel({ metrics }: { metrics?: AnalysisRunMetric[] }) {
  const items = metrics ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Context 没有 AnalysisRun 指标。
      </div>
    )
  }

  return (
    <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">AnalysisRun 指标</h4>
      </div>
      <div className="overflow-auto">
        <table className="min-w-full text-left text-sm">
          <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-[0.14em] text-slate-500">
            <tr>
              <th className="px-4 py-3">Metric</th>
              <th className="px-4 py-3">Phase</th>
              <th className="px-4 py-3">Value</th>
              <th className="px-4 py-3">Success</th>
              <th className="px-4 py-3">Failed</th>
              <th className="px-4 py-3">Error</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200">
            {items.map((metric) => (
              <tr key={metric.name ?? stringifyValue(metric)} className="bg-white">
                <td className="px-4 py-3 font-mono font-semibold text-[#031a41]">{metric.name ?? "-"}</td>
                <td className="px-4 py-3">
                  <Badge value={metric.phase ?? "-"} />
                </td>
                <td className="px-4 py-3 font-mono text-slate-700">{metric.value ?? "-"}</td>
                <td className="px-4 py-3 font-mono text-emerald-700">{metric.successful ?? 0}</td>
                <td className="px-4 py-3 font-mono text-rose-700">{metric.failed ?? 0}</td>
                <td className="px-4 py-3 font-mono text-amber-700">{metric.error ?? 0}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function EnvChangesPanel({ changes }: { changes?: EnvChange[] }) {
  const items = changes ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Context 没有环境变量变更。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">环境变量变更</h4>
      </div>
      <div className="divide-y divide-slate-200">
        {items.map((change, index) => (
          <div key={`${change.name ?? "env"}-${index}`} className="grid gap-3 px-4 py-3 text-sm lg:grid-cols-[150px_1fr_1fr_90px]">
            <span className="font-mono font-semibold text-[#031a41]">{change.name ?? "-"}</span>
            <span className="break-all font-mono text-slate-600">previous: {change.previous ?? "-"}</span>
            <span className="break-all font-mono text-slate-600">current: {change.current ?? "-"}</span>
            <Badge value={change.risk ?? "-"} label={change.risk ?? "-"} />
          </div>
        ))}
      </div>
    </div>
  )
}

export function ContextProductView({ body }: { body: string }) {
  const context = parseJsonResource<ContextPayload>(body)

  if (!context) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
        Context JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const result = context.result ?? "-"
  const rolloutPhase = context.rolloutPhase ?? "-"
  const analysisRunPhase = context.analysisRunPhase ?? "-"
  const severity = context.severity ?? "-"
  const riskScore = context.riskScore ?? 0
  const changeRiskLevel = context.changeRiskLevel ?? context.changeContext?.riskLevel ?? "-"
  const changeRiskScore = context.changeRiskScore ?? context.changeContext?.riskScore ?? 0
  const failedMetrics = context.failedMetrics ?? []
  const riskReasons = context.riskReasons ?? []
  const changeRiskHints = context.changeRiskHints ?? context.changeContext?.riskHints ?? []

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Context 发布上下文视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            将 release-context JSON 提炼为发布目标、Rollout 状态、AnalysisRun 指标和变更上下文。
          </p>
        </div>
        <Badge value={result} label={resultDisplay(result)} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="发布结果"
          value={resultDisplay(result)}
          rawValue={result}
          icon={CheckCircle2}
          hint={context.reason ?? "Context result"}
          statusValue={result}
        />
        <ProductMetricCard
          label="Rollout 阶段"
          value={rolloutPhase}
          rawValue={`abort=${String(context.rolloutAbort ?? false)}`}
          icon={GitBranch}
          hint={context.rolloutMessage || "Rollout 当前状态"}
          statusValue={rolloutPhase}
        />
        <ProductMetricCard
          label="AnalysisRun 阶段"
          value={analysisRunPhase}
          rawValue={context.analysisRun}
          icon={Activity}
          hint="AnalysisRun 当前状态"
          statusValue={analysisRunPhase}
        />
        <ProductMetricCard
          label="运行风险"
          value={riskText(severity)}
          rawValue={`${severity} / ${riskScore}`}
          icon={ShieldCheck}
          hint="运行时风险等级和分数"
          statusValue={severity}
        />
        <ProductMetricCard
          label="变更风险"
          value={riskText(changeRiskLevel)}
          rawValue={`${changeRiskLevel} / ${changeRiskScore}`}
          icon={AlertTriangle}
          hint={changeRiskHints.length > 0 ? changeRiskHints.join(", ") : "无变更风险提示"}
          statusValue={changeRiskLevel}
        />
        <ProductMetricCard
          label="推荐动作"
          value={context.recommendedAction ?? "-"}
          rawValue={context.decision}
          icon={TerminalSquare}
          hint="Context 推荐动作"
          statusValue={(context.recommendedAction ?? "").includes("no_action") ? "PASS" : context.recommendedAction}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">发布目标</h4>
          <KeyValueRows
            rows={[
              ["namespace", context.namespace ?? "-"],
              ["rollout", context.rollout ?? "-"],
              ["stableReplicaSet", context.stableReplicaSet ?? "-"],
              ["desiredVersion", context.currentDesiredVersion ?? "-"],
              ["analysisRun", context.analysisRun ?? "-"],
              ["generatedAt", context.generatedAt ?? "-"],
            ]}
          />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">GitOps / 镜像变更</h4>
          <KeyValueRows
            rows={[
              ["changeType", context.changeContext?.changeType ?? "-"],
              ["previousCommit", context.changeContext?.git?.previousCommit ?? "-"],
              ["currentCommit", context.changeContext?.git?.currentCommit ?? "-"],
              ["commitMessage", context.changeContext?.git?.commitMessage ?? "-"],
              ["imagePrevious", context.changeContext?.image?.previous ?? "-"],
              ["imageCurrent", context.changeContext?.image?.current ?? "-"],
              ["imageChanged", String(context.changeContext?.image?.changed ?? "-")],
            ]}
          />
        </div>
      </section>

      <AnalysisMetricsPanel metrics={context.analysisRunMetrics} />

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">失败指标</h4>
          <FailedMetricsPanel metrics={failedMetrics} />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">风险原因</h4>
          {riskReasons.length === 0 && changeRiskHints.length === 0 ? (
            <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">
              当前 Context 没有运行时风险原因，只有变更风险或无风险。
            </div>
          ) : (
            <RuleChipsPanel rules={[...riskReasons, ...changeRiskHints]} />
          )}
        </div>
      </section>

      <EnvChangesPanel changes={context.changeContext?.envChanges} />
    </div>
  )
}

