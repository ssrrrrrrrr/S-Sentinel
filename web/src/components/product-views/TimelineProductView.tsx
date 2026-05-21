import { CheckCircle2, Clock3, FileText, GitBranch, ShieldCheck } from "lucide-react"
import type { ReleaseIndexItem, ReleaseResourceRef } from "@/types/release"

const stageOrder = [
  {
    kind: "releaseContext",
    title: "Release Context",
    description: "发布上下文与目标对象被采集。",
  },
  {
    kind: "aiDecision",
    title: "AI Decision",
    description: "Advisor 生成发布判断与建议动作。",
  },
  {
    kind: "policyDecision",
    title: "Policy Decision",
    description: "策略层对 AI Decision 进行安全裁决。",
  },
  {
    kind: "releaseEvidence",
    title: "Release Evidence",
    description: "发布证据包生成，串联上下文、决策和指标结果。",
  },
  {
    kind: "releaseSummary",
    title: "Release Summary",
    description: "面向人工阅读的发布摘要生成。",
  },
  {
    kind: "actionPlan",
    title: "Action Plan",
    description: "生成只读安全动作计划。",
  },
  {
    kind: "releaseIntelligence",
    title: "Release Intelligence",
    description: "结合历史发布记录判断风险模式。",
  },
  {
    kind: "runbook",
    title: "Runbook",
    description: "生成面向 SRE 操作的运行手册。",
  },
  {
    kind: "rca",
    title: "RCA",
    description: "生成面向复盘的根因分析报告。",
  },
  {
    kind: "aiAdvice",
    title: "AI Advice",
    description: "将策略、智能分析和建议追加到人工报告。",
  },
]

function formatBytes(value?: number) {
  if (!value || value <= 0) return "-"
  if (value < 1024) return `${value} B`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`
  return `${(value / 1024 / 1024).toFixed(1)} MiB`
}

function formatTime(value?: string) {
  if (!value) return "-"

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  return date.toLocaleString()
}

function TimelineItem({
  index,
  title,
  description,
  resource,
}: {
  index: number
  title: string
  description: string
  resource?: ReleaseResourceRef
}) {
  const exists = Boolean(resource?.baseName)

  return (
    <div className="relative grid gap-4 rounded-xl border border-slate-200 bg-white p-4 shadow-sm md:grid-cols-[220px_minmax(0,1fr)]">
      <div className="flex items-start gap-3">
        <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full border text-sm font-bold ${
          exists
            ? "border-emerald-200 bg-emerald-50 text-emerald-700"
            : "border-slate-200 bg-slate-50 text-slate-400"
        }`}>
          {exists ? <CheckCircle2 className="h-4 w-4" /> : index + 1}
        </div>

        <div>
          <h4 className="font-semibold text-[#031a41]">{title}</h4>
          <p className="mt-1 text-xs leading-5 text-slate-500">{description}</p>
        </div>
      </div>

      <div className="grid gap-2 text-sm">
        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">状态</span>
          <span className={exists ? "font-semibold text-emerald-700" : "font-semibold text-slate-500"}>
            {exists ? "Collected" : "Missing"}
          </span>
        </div>

        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">Artifact</span>
          <span className="break-words font-mono text-slate-900">{resource?.baseName ?? "-"}</span>
        </div>

        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">ModifiedAt</span>
          <span className="break-words font-mono text-slate-900">{formatTime(resource?.modifiedAt)}</span>
        </div>

        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">Size</span>
          <span className="font-mono text-slate-900">{formatBytes(resource?.sizeBytes)}</span>
        </div>
      </div>
    </div>
  )
}

export function TimelineProductView({ selected }: { selected: ReleaseIndexItem }) {
  const resources = selected.resources ?? {}
  const collectedCount = stageOrder.filter((stage) => Boolean(resources[stage.kind]?.baseName)).length

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-sky-100 bg-sky-50 p-4">
        <div className="flex items-center gap-2 font-semibold text-sky-900">
          <GitBranch className="h-4 w-4" />
          Release Evidence Timeline
        </div>
        <p className="mt-2 text-sm leading-6 text-sky-800">
          该视图按照发布证据链展示一次发布的关键产物，从上下文采集、决策、证据、Action Plan 到 Runbook / RCA。
          当前是只读时间线，不会触发任何发布动作。
        </p>
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <section className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="flex items-center gap-2 text-sm font-semibold text-[#031a41]">
            <FileText className="h-4 w-4" />
            Release
          </div>
          <p className="mt-3 font-mono text-xl font-bold text-[#031a41]">{selected.releaseId}</p>
          <p className="mt-1 text-xs text-slate-500">GeneratedAt {selected.generatedAt}</p>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="flex items-center gap-2 text-sm font-semibold text-[#031a41]">
            <ShieldCheck className="h-4 w-4" />
            Outcome
          </div>
          <p className="mt-3 font-mono text-xl font-bold text-[#031a41]">
            {selected.summary?.releaseResult ?? "-"}
          </p>
          <p className="mt-1 text-xs text-slate-500">
            Policy {selected.summary?.policyDecision ?? "-"} · Action {selected.summary?.finalAction ?? "-"}
          </p>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="flex items-center gap-2 text-sm font-semibold text-[#031a41]">
            <Clock3 className="h-4 w-4" />
            Evidence Coverage
          </div>
          <p className="mt-3 font-mono text-xl font-bold text-[#031a41]">
            {collectedCount}/{stageOrder.length}
          </p>
          <p className="mt-1 text-xs text-slate-500">已收集关键发布证据数量</p>
        </section>
      </div>

      <div className="space-y-3">
        {stageOrder.map((stage, index) => (
          <TimelineItem
            key={stage.kind}
            index={index}
            title={stage.title}
            description={stage.description}
            resource={resources[stage.kind]}
          />
        ))}
      </div>

      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-800">
        说明：当前 Timeline 基于 Release Portal 已收集的 artifact metadata 生成。后续可以升级为独立的
        release-timeline.json，用于记录更细粒度的 GitOps、Rollout、AnalysisRun 和策略事件。
      </div>
    </div>
  )
}
