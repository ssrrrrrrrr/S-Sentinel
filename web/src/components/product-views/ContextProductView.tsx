import {
  Activity,
  AlertTriangle,
  FileText,
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
  changeRiskScore?: number | null
  changeRiskHints?: string[]
  changeContext?: {
    file?: string
    schemaVersion?: string
    generatedAt?: string
    changeType?: string
    app?: string
    namespace?: string
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
    riskScore?: number | null
    riskHints?: string[]
  }
  result?: string
  reason?: string
  decision?: string
  recommendedAction?: string
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function shortCommit(value?: string) {
  if (!value) return "-"
  return value.length > 12 ? value.slice(0, 12) : value
}

function changedText(value?: boolean) {
  if (value === true) return "已变化"
  if (value === false) return "未变化"
  return "未知"
}

function ReleaseContextSummary({
  context,
  imageChanged,
  commitChanged,
  envChangeCount,
  metricCount,
}: {
  context: ContextPayload
  imageChanged?: boolean
  commitChanged: boolean
  envChangeCount: number
  metricCount: number
}) {
  const result = context.result ?? "-"
  const isPass = result === "PASS"

  return (
    <div className={`rounded-2xl border p-5 ${
      isPass
        ? "border-emerald-900/45 bg-emerald-950/20"
        : "border-rose-900/45 bg-rose-950/20"
    }`}>
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="flex flex-wrap gap-2">
            <Badge value={result} label={resultDisplay(result)} />
            <Badge value={context.rolloutPhase ?? "-"} label={`Rollout=${context.rolloutPhase ?? "-"}`} />
            <Badge value={context.analysisRunPhase ?? "-"} label={`AnalysisRun=${context.analysisRunPhase ?? "-"}`} />
            <Badge value={imageChanged ? "REQUIRED" : "PASS"} label={`image=${changedText(imageChanged)}`} />
          </div>

          <h4 className={`mt-4 text-lg font-semibold ${isPass ? "text-emerald-200" : "text-rose-200"}`}>
            发布上下文结论：{context.reason || "Context 已采集"}
          </h4>
          <p className={`mt-2 max-w-4xl text-sm leading-6 ${isPass ? "text-emerald-200" : "text-rose-200"}`}>
            本页重点展示发布对象、GitOps commit、镜像差异、环境变量变化和 AnalysisRun 采样指标，用于回答“这次到底发布了什么、变更了什么”。
          </p>
        </div>

        <div className="grid min-w-[280px] gap-2 rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4 text-sm shadow-sm">
          <div className="flex justify-between gap-4">
            <span className="text-slate-500">imageChanged</span>
            <span className="font-mono font-semibold text-slate-100">{String(imageChanged ?? "-")}</span>
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-slate-500">commitChanged</span>
            <span className="font-mono font-semibold text-slate-100">{String(commitChanged)}</span>
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-slate-500">envChanges</span>
            <span className="font-mono font-semibold text-slate-100">{envChangeCount}</span>
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-slate-500">metrics</span>
            <span className="font-mono font-semibold text-slate-100">{metricCount}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

function GitOpsChangePanel({ context }: { context: ContextPayload }) {
  const git = context.changeContext?.git
  const previousCommit = git?.previousCommit
  const currentCommit = git?.currentCommit
  const commitChanged = Boolean(previousCommit && currentCommit && previousCommit !== currentCommit)

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">GitOps 变更上下文</h4>
        <p className="mt-1 text-xs text-slate-500">
          说明这次发布来自哪个 GitOps 变更，以及 commit 是否发生变化。
        </p>
      </div>

      <div className="p-4">
        <KeyValueRows
          rows={[
            ["changeType", context.changeContext?.changeType ?? "-"],
            ["baseRef", git?.baseRef ?? "-"],
            ["previousCommit", shortCommit(previousCommit)],
            ["currentCommit", shortCommit(currentCommit)],
            ["commitChanged", String(commitChanged)],
            ["commitMessage", git?.commitMessage ?? "-"],
            ["changeContextFile", context.changeContextFile ?? context.changeContext?.file ?? "-"],
          ]}
        />
      </div>
    </div>
  )
}

function ImageChangePanel({ context }: { context: ContextPayload }) {
  const image = context.changeContext?.image

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">镜像变更</h4>
        <p className="mt-1 text-xs text-slate-500">
          对比上一版本镜像和当前目标镜像，判断是否真正引入新版本。
        </p>
      </div>

      <div className="grid gap-4 p-4 lg:grid-cols-2">
        <div className="rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Previous Image</p>
          <p className="mt-3 break-all font-mono text-sm font-semibold text-slate-100">{image?.previous ?? "-"}</p>
        </div>
        <div className="rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Current Image</p>
          <p className="mt-3 break-all font-mono text-sm font-semibold text-slate-100">{image?.current ?? "-"}</p>
        </div>
      </div>

      <div className="border-t border-[#1f2b3d] p-4">
        <Badge
          value={image?.changed ? "REQUIRED" : "PASS"}
          label={changedText(image?.changed)}
        />
      </div>
    </div>
  )
}

function AnalysisMetricsPanel({ metrics }: { metrics?: AnalysisRunMetric[] }) {
  const items = metrics ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4 text-sm text-slate-400">
        当前 Context 没有 AnalysisRun 指标。
      </div>
    )
  }

  return (
    <div className="overflow-hidden rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">AnalysisRun 采样指标</h4>
        <p className="mt-1 text-xs text-slate-500">
          展示本次发布分析阶段采样到的 SLO 指标值和成功 / 失败次数。
        </p>
      </div>
      <div className="overflow-auto">
        <table className="min-w-full text-left text-sm">
          <thead className="border-b border-[#1f2b3d] bg-[#070b12] text-xs uppercase tracking-[0.14em] text-slate-500">
            <tr>
              <th className="px-4 py-3">Metric</th>
              <th className="px-4 py-3">Phase</th>
              <th className="px-4 py-3">Value</th>
              <th className="px-4 py-3">Success</th>
              <th className="px-4 py-3">Failed</th>
              <th className="px-4 py-3">Inconclusive</th>
              <th className="px-4 py-3">Error</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[#1f2b3d]">
            {items.map((metric) => (
              <tr key={metric.name ?? stringifyValue(metric)} className="bg-[#0b121d]">
                <td className="px-4 py-3 font-mono font-semibold text-slate-100">{metric.name ?? "-"}</td>
                <td className="px-4 py-3">
                  <Badge value={metric.phase ?? "-"} />
                </td>
                <td className="break-all px-4 py-3 font-mono text-slate-300">{metric.value ?? "-"}</td>
                <td className="px-4 py-3 font-mono text-emerald-300">{metric.successful ?? 0}</td>
                <td className="px-4 py-3 font-mono text-rose-300">{metric.failed ?? 0}</td>
                <td className="px-4 py-3 font-mono text-slate-300">{metric.inconclusive ?? 0}</td>
                <td className="px-4 py-3 font-mono text-amber-300">{metric.error ?? 0}</td>
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
      <div className="rounded-xl border border-emerald-900/45 bg-emerald-950/20 p-4 text-sm text-emerald-300">
        当前 Context 没有环境变量变更。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">环境变量变更</h4>
        <p className="mt-1 text-xs text-slate-500">
          展示 RELEASE_TAG、VERSION 或其他环境变量是否发生变化。
        </p>
      </div>
      <div className="divide-y divide-[#1f2b3d]">
        {items.map((change, index) => (
          <div key={`${change.name ?? "env"}-${index}`} className="grid gap-3 px-4 py-3 text-sm lg:grid-cols-[150px_1fr_1fr_110px_90px]">
            <span className="font-mono font-semibold text-slate-100">{change.name ?? "-"}</span>
            <span className="break-all font-mono text-slate-400">previous: {change.previous ?? "-"}</span>
            <span className="break-all font-mono text-slate-400">current: {change.current ?? "-"}</span>
            <Badge value={change.changed ? "REQUIRED" : "PASS"} label={changedText(change.changed)} />
            <Badge value={change.risk ?? "-"} label={change.risk ?? "-"} />
          </div>
        ))}
      </div>
    </div>
  )
}

function RiskContextPanel({
  context,
  riskReasons,
  changeRiskHints,
}: {
  context: ContextPayload
  riskReasons: string[]
  changeRiskHints: string[]
}) {
  const severity = context.severity ?? "-"
  const riskScore = context.riskScore ?? 0
  const changeRiskLevel = context.changeRiskLevel ?? context.changeContext?.riskLevel ?? "-"
  const changeRiskScore = context.changeRiskScore ?? context.changeContext?.riskScore

  return (
    <section className="grid gap-4 lg:grid-cols-2">
      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-100">风险上下文</h4>
        <KeyValueRows
          rows={[
            ["runtimeRiskLevel", riskText(severity)],
            ["runtimeRiskScore", String(riskScore)],
            ["changeRiskLevel", riskText(changeRiskLevel)],
            ["changeRiskScore", valueOrDash(changeRiskScore)],
            ["decision", context.decision ?? "-"],
            ["recommendedAction", context.recommendedAction ?? "-"],
          ]}
        />
      </div>

      <div className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-100">风险提示</h4>
        {riskReasons.length === 0 && changeRiskHints.length === 0 ? (
          <div className="rounded-xl border border-emerald-900/45 bg-emerald-950/20 p-4 text-sm text-emerald-300">
            当前 Context 没有运行时风险原因，也没有变更风险提示。
          </div>
        ) : (
          <RuleChipsPanel rules={[...riskReasons, ...changeRiskHints]} />
        )}
      </div>
    </section>
  )
}

export function ContextProductView({ body }: { body: string }) {
  const context = parseJsonResource<ContextPayload>(body)

  if (!context) {
    return (
      <div className="rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-300">
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
  const changeRiskScore = context.changeRiskScore ?? context.changeContext?.riskScore
  const failedMetrics = context.failedMetrics ?? []
  const riskReasons = context.riskReasons ?? []
  const changeRiskHints = context.changeRiskHints ?? context.changeContext?.riskHints ?? []
  const envChanges = context.changeContext?.envChanges ?? []
  const imageChanged = context.changeContext?.image?.changed
  const previousCommit = context.changeContext?.git?.previousCommit
  const currentCommit = context.changeContext?.git?.currentCommit
  const commitChanged = Boolean(previousCommit && currentCommit && previousCommit !== currentCommit)
  const metricCount = context.analysisRunMetrics?.length ?? 0

  return (
    <div className="space-y-5 rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-5">
      <div className="flex flex-col gap-3 border-b border-[#1f2b3d] pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-slate-100">Context 发布变更上下文</h4>
          <p className="mt-1 text-sm text-slate-400">
            重点回答：这次发布对象是谁、GitOps / 镜像 / 环境变量是否变化，以及 AnalysisRun 采样到了什么。
          </p>
        </div>
        <Badge value={result} label={resultDisplay(result)} />
      </div>

      <ReleaseContextSummary
        context={context}
        imageChanged={imageChanged}
        commitChanged={commitChanged}
        envChangeCount={envChanges.length}
        metricCount={metricCount}
      />

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="发布对象"
          value={context.rollout ?? "-"}
          rawValue={context.namespace}
          icon={FileText}
          hint="namespace / rollout"
          statusValue="PASS"
        />
        <ProductMetricCard
          label="目标版本"
          value={context.currentDesiredVersion ?? "-"}
          rawValue={context.stableReplicaSet}
          icon={GitBranch}
          hint="desired version / stable ReplicaSet"
          statusValue="PASS"
        />
        <ProductMetricCard
          label="镜像变化"
          value={changedText(imageChanged)}
          rawValue={context.changeContext?.image?.current}
          icon={AlertTriangle}
          hint="是否引入新的目标镜像"
          statusValue={imageChanged ? "REQUIRED" : "PASS"}
        />
        <ProductMetricCard
          label="Rollout 状态"
          value={rolloutPhase}
          rawValue={`abort=${String(context.rolloutAbort ?? false)}`}
          icon={GitBranch}
          hint={context.rolloutMessage || "Rollout 当前状态"}
          statusValue={rolloutPhase}
        />
        <ProductMetricCard
          label="AnalysisRun 状态"
          value={analysisRunPhase}
          rawValue={context.analysisRun}
          icon={Activity}
          hint={`${metricCount} metrics sampled`}
          statusValue={analysisRunPhase}
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

      <section className="grid gap-4 lg:grid-cols-[0.9fr_1.1fr]">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-100">发布目标</h4>
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

        <GitOpsChangePanel context={context} />
      </section>

      <ImageChangePanel context={context} />

      <EnvChangesPanel changes={envChanges} />

      <AnalysisMetricsPanel metrics={context.analysisRunMetrics} />

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-100">失败指标上下文</h4>
          <FailedMetricsPanel metrics={failedMetrics} />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-100">运行状态摘要</h4>
          <KeyValueRows
            rows={[
              ["result", resultDisplay(result)],
              ["reason", context.reason ?? "-"],
              ["severity", riskText(severity)],
              ["riskScore", String(riskScore)],
              ["changeRiskLevel", riskText(changeRiskLevel)],
              ["changeRiskScore", valueOrDash(changeRiskScore)],
            ]}
          />
        </div>
      </section>

      <RiskContextPanel
        context={context}
        riskReasons={riskReasons}
        changeRiskHints={changeRiskHints}
      />

      <div className="rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4 text-sm text-slate-400">
        <div className="flex items-center gap-2 font-semibold text-slate-100">
          <ShieldCheck className="h-4 w-4" />
          Context 视图边界
        </div>
        <p className="mt-2 leading-6">
          Context 只描述发布目标和变更上下文，不负责解释为什么通过或失败；判断依据请看 Evidence，执行建议请看 Action Plan。
        </p>
      </div>
    </div>
  )
}


