import { useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import {
  Activity,
  AlertTriangle,
  Bot,
  CheckCircle2,
  Clock3,
  FileText,
  GitBranch,
  LockKeyhole,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  TerminalSquare,
} from "lucide-react"
import { fetchLatestRelease, fetchReleases } from "@/api/releases"
import {
  fetchReleaseResource,
  formatResourceBody,
  getResourceKindByTab,
  isMarkdownContent,
} from "@/api/releaseResources"
import type { LatestReleaseResponse, ReleaseIndexItem } from "@/types/release"

const tabs = ["概览", "Evidence", "Action Plan", "Intelligence", "AI Advice", "Context"]

function normalize(value?: string) {
  return (value ?? "").toUpperCase()
}

function statusClass(value: string) {
  const normalized = normalize(value)

  if (
    normalized === "PASS" ||
    normalized === "LOW" ||
    normalized === "ALLOW" ||
    normalized === "NOOP" ||
    normalized === "NOT REQUIRED" ||
    normalized === "ADVISORY_ONLY"
  ) {
    return "border-emerald-200 bg-emerald-50 text-emerald-700"
  }

  if (
    normalized.includes("FAIL") ||
    normalized === "HIGH" ||
    normalized === "CRITICAL" ||
    normalized === "BLOCK" ||
    normalized === "STOP_PROMOTION" ||
    normalized === "REQUIRED"
  ) {
    return "border-rose-200 bg-rose-50 text-rose-700"
  }

  return "border-amber-200 bg-amber-50 text-amber-700"
}

function approvalText(required: boolean) {
  return required ? "需要审批" : "无需审批"
}

function approvalRaw(required: boolean) {
  return required ? "REQUIRED" : "NOT REQUIRED"
}

function riskText(value: string) {
  const normalized = normalize(value)
  if (normalized === "LOW") return "低风险"
  if (normalized === "MEDIUM") return "中风险"
  if (normalized === "HIGH") return "高风险"
  if (normalized === "CRITICAL") return "严重风险"
  return value || "-"
}

function resultDisplay(value: string) {
  if (normalize(value) === "FAIL_BY_MULTIPLE_SLO") return "FAIL"
  return value || "-"
}

function policyDisplay(value: string) {
  if (value === "ALLOW_ADVISORY_ONLY") return "ADVISORY"
  return value || "-"
}

function actionDisplay(value: string) {
  if (value === "STOP_PROMOTION") return "STOP"
  return value || "-"
}

function formatTime(value?: string) {
  if (!value) return "-"
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  const diffSeconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
  if (diffSeconds < 60) return `${diffSeconds} 秒前`

  const diffMinutes = Math.floor(diffSeconds / 60)
  if (diffMinutes < 60) return `${diffMinutes} 分钟前`

  const diffHours = Math.floor(diffMinutes / 60)
  if (diffHours < 24) return `${diffHours} 小时前`

  const diffDays = Math.floor(diffHours / 24)
  return `${diffDays} 天前`
}

function resourceKeys(release?: ReleaseIndexItem) {
  return Object.keys(release?.resources ?? {})
}

function Badge({ value, label }: { value: string; label?: string }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${statusClass(value)}`}>
      {label ?? value}
    </span>
  )
}

function MetricCard({
  label,
  value,
  rawValue,
  icon: Icon,
  hint,
}: {
  label: string
  value: string
  rawValue?: string
  icon: typeof Activity
  hint: string
}) {
  return (
    <article className="group relative overflow-hidden rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60 transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md">
      <div className="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-[#031a41] via-cyan-500 to-sky-300" />
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">{label}</p>
        <Icon className="h-4 w-4 text-cyan-500" />
      </div>
      <div className="mt-4">
        <p className="break-words text-[clamp(1.35rem,2vw,1.75rem)] font-bold tracking-tight text-[#031a41]">
          {value}
        </p>
        {rawValue ? (
          <p className="mt-1 break-all font-mono text-[11px] text-slate-400">{rawValue}</p>
        ) : null}
        <p className="mt-1 text-xs text-slate-600">{hint}</p>
      </div>
    </article>
  )
}

function ResourceMetadataPanel({ selected }: { selected: ReleaseIndexItem }) {
  const keys = resourceKeys(selected)

  if (keys.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-slate-50 p-5 text-sm text-slate-600">
        当前发布没有可展示的资源索引。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">关联资源</h4>
      </div>
      <div className="divide-y divide-slate-200">
        {keys.map((key) => {
          const resource = selected.resources?.[key]
          return (
            <div key={key} className="grid gap-3 px-4 py-3 text-sm md:grid-cols-[180px_1fr_120px]">
              <span className="font-mono font-semibold text-[#031a41]">{key}</span>
              <span className="truncate text-slate-500">{resource?.baseName ?? resource?.file ?? "-"}</span>
              <span className="text-right text-slate-500">{resource?.sizeBytes ?? 0} bytes</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}

function SafetyPanel({ latest }: { latest?: LatestReleaseResponse }) {
  const safety = latest?.safety
  const rows = [
    ["mode", latest?.mode ?? "read_only"],
    ["readOnly", String(safety?.readOnly ?? true)],
    ["willExecute", String(safety?.willExecute ?? false)],
    ["supportsRollback", String(safety?.supportsRollback ?? false)],
    ["supportsPromote", String(safety?.supportsPromote ?? false)],
    ["supportsPatch", String(safety?.supportsPatch ?? false)],
    ["supportsDelete", String(safety?.supportsDelete ?? false)],
  ]

  return (
    <div className="grid gap-3 md:grid-cols-2">
      {rows.map(([key, value]) => (
        <div key={key} className="rounded-xl border border-slate-200 bg-slate-50 p-4">
          <p className="font-mono text-xs text-slate-500">{key}</p>
          <p className="mt-2 font-mono text-sm font-semibold text-[#031a41]">{value}</p>
        </div>
      ))}
    </div>
  )
}

type ActionPlanPayload = {
  schemaVersion?: string
  generatedAt?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  sourceExecutionMode?: string
  willExecute?: boolean
  requiresHumanApproval?: boolean
  target?: {
    namespace?: string
    rollout?: string
    analysisRun?: string
  }
  actionPlan?: {
    action?: string
    blocked?: boolean
    blockReason?: string
    candidateCommands?: string[]
    humanSteps?: string[]
  }
  guardrails?: Record<string, boolean | string | number | null>
}

function parseJsonResource<T>(body: string): T | null {
  try {
    return JSON.parse(body) as T
  } catch {
    return null
  }
}

function ProductMetricCard({
  label,
  value,
  rawValue,
  hint,
  icon: Icon,
  statusValue,
}: {
  label: string
  value: string
  rawValue?: string
  hint: string
  icon: typeof Activity
  statusValue?: string
}) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">{label}</p>
          <p className="mt-2 text-xl font-bold tracking-tight text-[#031a41]">{value}</p>
          {rawValue ? <p className="mt-1 break-all font-mono text-[11px] text-slate-400">{rawValue}</p> : null}
          <p className="mt-2 text-xs text-slate-600">{hint}</p>
        </div>
        <div className={`rounded-lg border p-2 ${statusClass(statusValue ?? value)}`}>
          <Icon className="h-4 w-4" />
        </div>
      </div>
    </div>
  )
}

function KeyValueRows({ rows }: { rows: Array<[string, string]> }) {
  return (
    <div className="divide-y divide-slate-200 rounded-xl border border-slate-200 bg-white">
      {rows.map(([key, value]) => (
        <div key={key} className="grid gap-2 px-4 py-3 text-sm md:grid-cols-[150px_1fr]">
          <span className="font-mono text-xs text-slate-500">{key}</span>
          <span className="break-all font-mono text-[#031a41]">{value || "-"}</span>
        </div>
      ))}
    </div>
  )
}

function GuardrailGrid({ guardrails }: { guardrails?: Record<string, boolean | string | number | null> }) {
  const entries = Object.entries(guardrails ?? {})

  if (entries.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Action Plan 没有 guardrails 字段。
      </div>
    )
  }

  return (
    <div className="grid gap-3 md:grid-cols-2">
      {entries.map(([key, value]) => {
        const isBoolean = typeof value === "boolean"
        const valueText = String(value)
        return (
          <div key={key} className="rounded-xl border border-slate-200 bg-white p-4">
            <p className="break-all font-mono text-xs text-slate-500">{key}</p>
            <div className="mt-2">
              <span
                className={`inline-flex rounded-full border px-2.5 py-1 font-mono text-xs font-semibold ${
                  isBoolean && value === true
                    ? "border-emerald-200 bg-emerald-50 text-emerald-700"
                    : isBoolean && value === false
                      ? "border-amber-200 bg-amber-50 text-amber-700"
                      : "border-slate-200 bg-slate-50 text-slate-700"
                }`}
              >
                {valueText}
              </span>
            </div>
          </div>
        )
      })}
    </div>
  )
}

function HumanStepsPanel({ steps }: { steps?: string[] }) {
  const items = steps ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Action Plan 没有人工步骤。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">人工处理步骤</h4>
      </div>
      <div className="divide-y divide-slate-200">
        {items.map((step, index) => (
          <div key={`${index}-${step}`} className="flex gap-3 px-4 py-3 text-sm">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[#031a41] text-xs font-semibold text-white">
              {index + 1}
            </span>
            <span className="leading-6 text-slate-700">{step}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function CandidateCommandsPanel({ commands }: { commands?: string[] }) {
  const items = commands ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Action Plan 没有候选命令，说明本次发布无需人工执行命令。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-amber-200 bg-amber-50 p-4">
      <h4 className="text-sm font-semibold text-amber-900">候选命令</h4>
      <p className="mt-1 text-xs text-amber-700">这些命令仅作为建议展示，前端不会执行。</p>
      <pre className="mt-3 overflow-auto rounded-lg bg-[#031a41] p-4 text-xs leading-6 text-cyan-50">
        {items.join("\n")}
      </pre>
    </div>
  )
}

function ActionPlanProductView({ body }: { body: string }) {
  const plan = parseJsonResource<ActionPlanPayload>(body)

  if (!plan) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
        Action Plan JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const action = plan.actionPlan?.action ?? plan.finalAction ?? "-"
  const blocked = Boolean(plan.actionPlan?.blocked)
  const willExecute = Boolean(plan.willExecute)
  const requiresApproval = Boolean(plan.requiresHumanApproval)

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Action Plan 决策视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            将原始 action-plan JSON 提炼为 SRE 可以快速判断的执行、安全和人工门禁信息。
          </p>
        </div>
        <Badge value={action} label={actionDisplay(action)} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="最终动作"
          value={actionDisplay(action)}
          rawValue={action}
          icon={TerminalSquare}
          hint="Action Plan 建议的最终动作"
          statusValue={action}
        />
        <ProductMetricCard
          label="阻断状态"
          value={blocked ? "已阻断" : "未阻断"}
          rawValue={String(blocked)}
          icon={AlertTriangle}
          hint={plan.actionPlan?.blockReason || "当前没有阻断原因"}
          statusValue={blocked ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="是否执行"
          value={willExecute ? "会执行" : "不会执行"}
          rawValue={String(willExecute)}
          icon={LockKeyhole}
          hint="前端只读展示，不触发 Kubernetes 修改"
          statusValue={willExecute ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="人工审批"
          value={approvalText(requiresApproval)}
          rawValue={approvalRaw(requiresApproval)}
          icon={ShieldCheck}
          hint="Human Gate 状态"
          statusValue={approvalRaw(requiresApproval)}
        />
        <ProductMetricCard
          label="执行模式"
          value={plan.executionMode ?? "-"}
          rawValue={plan.sourceExecutionMode}
          icon={Sparkles}
          hint="dry_run / advisory_only 等安全模式"
          statusValue={plan.executionMode ?? "-"}
        />
        <ProductMetricCard
          label="发布结果"
          value={resultDisplay(plan.releaseResult ?? "-")}
          rawValue={plan.policyDecision}
          icon={CheckCircle2}
          hint="来自 release evidence 的最终结论"
          statusValue={plan.releaseResult ?? "-"}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">目标对象</h4>
          <KeyValueRows
            rows={[
              ["namespace", plan.target?.namespace ?? "-"],
              ["rollout", plan.target?.rollout ?? "-"],
              ["analysisRun", plan.target?.analysisRun ?? "-"],
              ["generatedAt", plan.generatedAt ?? "-"],
            ]}
          />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">人工步骤</h4>
          <HumanStepsPanel steps={plan.actionPlan?.humanSteps} />
        </div>
      </section>

      <section className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-900">安全护栏</h4>
        <GuardrailGrid guardrails={plan.guardrails} />
      </section>

      <CandidateCommandsPanel commands={plan.actionPlan?.candidateCommands} />
    </div>
  )
}

function RawResourceViewer({ contentType, body }: { contentType: string; body: string }) {
  if (isMarkdownContent(contentType)) {
    return (
      <pre className="max-h-[520px] overflow-auto whitespace-pre-wrap rounded-lg border border-slate-200 bg-white p-5 text-sm leading-7 text-slate-700">
        {formatResourceBody(contentType, body)}
      </pre>
    )
  }

  return (
    <pre className="max-h-[520px] overflow-auto rounded-lg bg-[#031a41] p-5 text-xs leading-6 text-cyan-50">
      {formatResourceBody(contentType, body)}
    </pre>
  )
}

function App() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState("Action Plan")

  const releasesQuery = useQuery({
    queryKey: ["releases"],
    queryFn: fetchReleases,
    refetchInterval: 15000,
  })

  const latestQuery = useQuery({
    queryKey: ["latest-release"],
    queryFn: fetchLatestRelease,
    refetchInterval: 15000,
  })

  const releases = useMemo(() => releasesQuery.data?.items ?? [], [releasesQuery.data?.items])
  const selected = releases.find((release) => release.releaseId === selectedId) ?? releases[0]
  const selectedSummary = selected?.summary
  const resourceKind = getResourceKindByTab(activeTab)

  const resourceQuery = useQuery({
    queryKey: ["release-resource", selected?.releaseId, resourceKind],
    queryFn: () => fetchReleaseResource(selected!.releaseId, resourceKind),
    enabled: Boolean(selected?.releaseId),
    staleTime: 10000,
  })

  const isLoading = releasesQuery.isLoading || latestQuery.isLoading
  const hasError = releasesQuery.isError || latestQuery.isError

  function refreshAll() {
    void releasesQuery.refetch()
    void latestQuery.refetch()
  }

  return (
    <main className="min-h-screen text-slate-900">
      <header className="sticky top-0 z-20 border-b border-slate-200/80 bg-white/90 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-[1440px] items-center justify-between px-6">
          <div className="flex items-center gap-4">
            <img
              src="/brand/s-sentinel-logo.svg"
              alt="S Sentinel logo"
              className="h-11 w-11 object-contain"
            />
            <div className="flex items-center leading-tight">
              <h1 className="text-xl font-bold tracking-tight text-[#031a41]">S Sentinel</h1>
            </div>
          </div>

          <div className="hidden items-center gap-2 md:flex">
            <span className={`inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-semibold ${
              hasError
                ? "border-rose-200 bg-rose-50 text-rose-700"
                : "border-emerald-200 bg-emerald-50 text-emerald-700"
            }`}>
              <span className={`h-1.5 w-1.5 rounded-full ${hasError ? "bg-rose-500" : "bg-emerald-500"}`} />
              {hasError ? "Watcher 异常" : "Watcher 在线"}
            </span>
            <span className="inline-flex items-center gap-1.5 rounded-md border border-slate-200 bg-slate-50 px-2.5 py-1 text-xs font-semibold text-slate-600">
              <LockKeyhole className="h-3.5 w-3.5" />
              {latestQuery.data?.safety?.readOnly === false ? "非只读模式" : "只读模式"}
            </span>
            <span className="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium text-slate-500">
              <Clock3 className="h-3.5 w-3.5" />
              {formatTime(releasesQuery.data?.generatedAt)}刷新
            </span>
          </div>
        </div>
      </header>

      <section className="mx-auto flex max-w-[1440px] flex-col gap-6 px-6 py-6">
        <section className="rounded-2xl border border-slate-200 bg-white/95 p-4 shadow-sm shadow-slate-200/60">
          <div className="flex flex-col justify-between gap-6 lg:flex-row lg:items-end">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-cyan-600">
                阶段 22.6 · Release Portal API 联调
              </p>
              <h2 className="mt-2 max-w-3xl text-[1.35rem] font-semibold leading-snug tracking-tight text-[#031a41]">
                真实读取发布证据、SLO 决策和 Action Plan，形成安全的只读发布控制台。
              </h2>
              <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-600">
                当前页面数据来自 Release Portal API：/api/releases 与 /api/releases/latest。前端不会暴露 Rollback、Promote、Patch 或 Delete 等高风险操作。
              </p>
            </div>
            <div className="rounded-xl border border-cyan-100 bg-cyan-50 px-4 py-3 text-sm text-cyan-800">
              <div className="flex items-center gap-2 font-semibold">
                <ShieldCheck className="h-4 w-4" />
                安全边界已启用
              </div>
              <p className="mt-1 text-xs text-cyan-700">
                willExecute={String(latestQuery.data?.safety?.willExecute ?? false)} · readOnly={String(latestQuery.data?.safety?.readOnly ?? true)}
              </p>
            </div>
          </div>
        </section>

        {isLoading ? (
          <section className="rounded-2xl border border-slate-200 bg-white p-8 text-sm text-slate-600 shadow-sm">
            正在加载 Release Portal API 数据...
          </section>
        ) : hasError ? (
          <section className="rounded-2xl border border-rose-200 bg-rose-50 p-8 text-sm text-rose-700 shadow-sm">
            Release Portal API 读取失败。请确认虚拟机 port-forward 仍在运行，并且 Vite proxy 指向 http://192.168.30.11:18090。
          </section>
        ) : !selected || !selectedSummary ? (
          <section className="rounded-2xl border border-slate-200 bg-white p-8 text-sm text-slate-600 shadow-sm">
            当前没有可展示的发布记录。
          </section>
        ) : (
          <>
            <section className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4">
              <MetricCard label="最新结果" value={resultDisplay(selectedSummary.releaseResult)} rawValue={selectedSummary.releaseResult} icon={CheckCircle2} hint="最近一次 evidence-backed 发布" />
              <MetricCard
                label="策略决策"
                value={policyDisplay(selectedSummary.policyDecision)}
                rawValue={selectedSummary.policyDecision}
                icon={ShieldCheck}
                hint="Policy Decision 结果"
              />
              <MetricCard
                label="最终动作"
                value={actionDisplay(selectedSummary.finalAction)}
                rawValue={selectedSummary.finalAction}
                icon={TerminalSquare}
                hint="系统建议的最终动作"
              />
              <MetricCard label="风险等级" value={riskText(selectedSummary.riskLevel)} rawValue={selectedSummary.riskLevel} icon={AlertTriangle} hint={`Risk Score ${selectedSummary.riskScore}/100`} />
              <MetricCard label="人工审批" value={approvalText(selectedSummary.requiresHumanApproval)} rawValue={approvalRaw(selectedSummary.requiresHumanApproval)} icon={LockKeyhole} hint="人工门禁状态" />
              <MetricCard label="资源数量" value={String(selected.resourceCount)} icon={FileText} hint="关联发布证据资源" />
            </section>

            <section className="grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
              <aside className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60">
                <div className="mb-4 flex items-center justify-between">
                  <div>
                    <h3 className="font-semibold text-slate-950">最近发布</h3>
                    <p className="text-xs text-slate-500">共 {releasesQuery.data?.count ?? releases.length} 条发布记录</p>
                  </div>
                  <button type="button" onClick={refreshAll} title="刷新发布列表">
                    <RefreshCw className="h-4 w-4 text-slate-400 hover:text-cyan-600" />
                  </button>
                </div>

                <div className="relative space-y-3 before:absolute before:left-3 before:top-2 before:h-[calc(100%-1rem)] before:w-px before:bg-slate-200">
                  {releases.map((release) => {
                    const isActive = release.releaseId === selected.releaseId
                    const result = release.summary.releaseResult
                    return (
                      <button
                        key={release.releaseId}
                        type="button"
                        onClick={() => setSelectedId(release.releaseId)}
                        className={`relative w-full rounded-xl border py-4 pl-9 pr-4 text-left transition ${
                          isActive
                            ? "border-[#031a41] bg-[#031a41] text-white shadow-md"
                            : "border-slate-200 bg-white text-slate-900 hover:border-cyan-200 hover:bg-cyan-50/40 hover:shadow-sm"
                        }`}
                      >
                        <span className={`absolute left-[7px] top-5 h-3 w-3 rounded-full border-2 ${normalize(result).startsWith("PASS") ? "border-emerald-600 bg-emerald-100" : "border-rose-600 bg-rose-100"}`} />
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <p className={`font-mono text-sm font-semibold ${isActive ? "text-white" : "text-[#031a41]"}`}>
                              {release.releaseId}
                            </p>
                            <p className={`mt-1 text-xs ${isActive ? "text-slate-300" : "text-slate-500"}`}>{release.generatedAt}</p>
                          </div>
                          <span className={`text-xs ${isActive ? "text-cyan-200" : "text-slate-500"}`}>{formatTime(release.modifiedAt)}</span>
                        </div>
                        <div className="mt-3 flex flex-wrap gap-2">
                          <Badge value={result} label={resultDisplay(result)} />
                          <Badge value={release.summary.riskLevel} label={riskText(release.summary.riskLevel)} />
                        </div>
                      </button>
                    )
                  })}
                </div>
              </aside>

              <section className="rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-200/60">
                <div className="border-b border-slate-200 p-6">
                  <div className="flex flex-col justify-between gap-5 lg:flex-row lg:items-start">
                    <div>
                      <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-cyan-600">
                        <GitBranch className="h-4 w-4" />
                        当前选中发布
                      </div>
                      <h3 className="mt-3 text-2xl font-semibold tracking-tight text-[#031a41]">{selected.releaseId}</h3>
                      <p className="mt-2 text-sm text-slate-500">
                        GeneratedAt {selected.generatedAt} · ModifiedAt {selected.modifiedAt}
                      </p>
                    </div>
                    <div className="grid grid-cols-2 gap-3 text-sm">
                      <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                        <p className="text-xs text-slate-500">Risk Score</p>
                        <p className="mt-1 text-xl font-semibold text-[#031a41]">{selectedSummary.riskScore}<span className="text-xs text-slate-400"> /100</span></p>
                      </div>
                      <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                        <p className="text-xs text-slate-500">资源数量</p>
                        <p className="mt-1 text-xl font-semibold text-[#031a41]">{selected.resourceCount}</p>
                      </div>
                    </div>
                  </div>

                  <div className="mt-6 flex flex-wrap gap-2 rounded-2xl border border-slate-200 bg-slate-50 p-1.5">
                    {tabs.map((tab) => (
                      <button
                        key={tab}
                        type="button"
                        onClick={() => setActiveTab(tab)}
                        className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                          activeTab === tab
                            ? "bg-[#031a41] text-white shadow-sm"
                            : "text-slate-600 hover:bg-white hover:text-[#031a41] hover:shadow-sm"
                        }`}
                      >
                        {tab}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="p-6">
                  <div className="space-y-5">
                    {activeTab === "Action Plan" ? (
                      <div className="rounded-xl border border-cyan-100 bg-cyan-50 p-4">
                        <div className="flex items-center gap-2 font-semibold text-cyan-900">
                          <Sparkles className="h-4 w-4" />
                          Action Plan 安全建议
                        </div>
                        <p className="mt-2 text-sm leading-6 text-cyan-800">
                          当前系统处于只读观察模式。Release Portal 返回的 Action Plan 仅用于辅助判断，不会修改 Kubernetes 资源。
                        </p>
                      </div>
                    ) : null}

                    {activeTab === "Action Plan" ? <SafetyPanel latest={latestQuery.data} /> : null}

                    <div className="rounded-xl border border-slate-200 bg-slate-50 p-5">
                      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
                        <div>
                          <div className="flex items-center gap-2 font-semibold text-[#031a41]">
                            {activeTab === "AI Advice" ? <Bot className="h-4 w-4" /> : <Activity className="h-4 w-4" />}
                            {activeTab}
                          </div>
                          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-600">
                            正在读取 <span className="font-mono text-[#031a41]">/api/releases/{selected.releaseId}/{resourceKind}</span>
                          </p>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          <span className="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-semibold text-slate-600">
                            {resourceQuery.data?.contentType ?? "loading"}
                          </span>
                          <span className="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-semibold text-slate-600">
                            {resourceKind}
                          </span>
                        </div>
                      </div>

                      {resourceQuery.isLoading ? (
                        <div className="mt-4 rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
                          正在加载资源内容...
                        </div>
                      ) : resourceQuery.isError ? (
                        <div className="mt-4 rounded-lg border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
                          资源读取失败：{resourceQuery.error instanceof Error ? resourceQuery.error.message : "unknown error"}
                        </div>
                      ) : resourceQuery.data ? (
                        <div className="mt-4 space-y-5">
                          {activeTab === "Action Plan" && !isMarkdownContent(resourceQuery.data.contentType) ? (
                            <ActionPlanProductView body={resourceQuery.data.body} />
                          ) : null}

                          <div>
                            <div className="mb-2 flex items-center justify-between">
                              <h4 className="text-sm font-semibold text-slate-900">原始资源内容</h4>
                              <span className="rounded-full border border-slate-200 bg-white px-2.5 py-1 text-xs font-semibold text-slate-500">
                                Audit View
                              </span>
                            </div>
                            <RawResourceViewer
                              contentType={resourceQuery.data.contentType}
                              body={resourceQuery.data.body}
                            />
                          </div>
                        </div>
                      ) : (
                        <div className="mt-4 rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
                          暂无资源内容。
                        </div>
                      )}
                    </div>

                    {activeTab === "概览" ? <ResourceMetadataPanel selected={selected} /> : null}
                  </div>
                </div>
              </section>
            </section>
          </>
        )}
      </section>
    </main>
  )
}

export default App



