import { AlertTriangle, CheckCircle2, Clock3, FileText, GitBranch, ShieldCheck } from "lucide-react"
import type { ReleaseIndexItem } from "@/types/release"

type TimelineArtifact = {
  path?: string
  baseName?: string
  exists?: boolean
  sizeBytes?: number | null
  modifiedAt?: string | null
}

type TimelineEvent = {
  sequence?: number
  stage: string
  title: string
  description?: string
  status?: string
  artifactKind?: string
  artifact?: TimelineArtifact
}

type ReleaseTimelineDocument = {
  schemaVersion?: string
  generatedAt?: string
  releaseId?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  coverage?: {
    collected?: number
    total?: number
    missingStages?: string[]
  }
  events?: TimelineEvent[]
}

const fallbackStageOrder = [
  {
    kind: "releaseContext",
    stage: "release_context_collected",
    title: "Release Context",
    description: "发布上下文与目标对象被采集。",
  },
  {
    kind: "aiDecision",
    stage: "ai_decision_generated",
    title: "AI Decision",
    description: "Advisor 生成发布判断与建议动作。",
  },
  {
    kind: "policyDecision",
    stage: "policy_decision_evaluated",
    title: "Policy Decision",
    description: "策略层对 AI Decision 进行安全裁决。",
  },
  {
    kind: "releaseEvidence",
    stage: "release_evidence_built",
    title: "Release Evidence",
    description: "发布证据包生成，串联上下文、决策和指标结果。",
  },
  {
    kind: "releaseSummary",
    stage: "release_summary_generated",
    title: "Release Summary",
    description: "面向人工阅读的发布摘要生成。",
  },
  {
    kind: "actionPlan",
    stage: "action_plan_generated",
    title: "Action Plan",
    description: "生成只读安全动作计划。",
  },
  {
    kind: "releaseIntelligence",
    stage: "release_intelligence_generated",
    title: "Release Intelligence",
    description: "结合历史发布记录判断风险模式。",
  },
  {
    kind: "runbook",
    stage: "runbook_generated",
    title: "Runbook",
    description: "生成面向 SRE 操作的运行手册。",
  },
  {
    kind: "rca",
    stage: "rca_generated",
    title: "RCA",
    description: "生成面向复盘的根因分析报告。",
  },
  {
    kind: "aiAdvice",
    stage: "ai_advice_generated",
    title: "AI Advice",
    description: "将策略、智能分析和建议追加到人工报告。",
  },
]

function formatBytes(value?: number | null) {
  if (!value || value <= 0) return "-"
  if (value < 1024) return `${value} B`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`
  return `${(value / 1024 / 1024).toFixed(1)} MiB`
}

function formatTime(value?: string | null) {
  if (!value) return "-"

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  return date.toLocaleString()
}

function parseTimelineDocument(body?: string): ReleaseTimelineDocument | null {
  if (!body) return null

  try {
    const parsed = JSON.parse(body) as ReleaseTimelineDocument
    if (parsed.schemaVersion === "release.timeline/v1alpha1" && Array.isArray(parsed.events)) {
      return parsed
    }
  } catch {
    return null
  }

  return null
}

function fallbackEventsFromResources(selected: ReleaseIndexItem): TimelineEvent[] {
  const resources = selected.resources ?? {}

  return fallbackStageOrder.map((stage, index) => {
    const resource = resources[stage.kind]

    return {
      sequence: index + 1,
      stage: stage.stage,
      title: stage.title,
      description: stage.description,
      status: resource?.baseName ? "COLLECTED" : "MISSING",
      artifactKind: stage.kind,
      artifact: resource
        ? {
            baseName: resource.baseName,
            sizeBytes: resource.sizeBytes,
            modifiedAt: resource.modifiedAt,
            exists: Boolean(resource.baseName),
          }
        : {
            exists: false,
          },
    }
  })
}

function isCollected(event: TimelineEvent) {
  const status = event.status?.toUpperCase()
  return status === "COLLECTED" || status === "GENERATED" || event.artifact?.exists === true
}

function statusLabel(event: TimelineEvent) {
  return event.status ?? (isCollected(event) ? "COLLECTED" : "MISSING")
}

function TimelineItem({ event }: { event: TimelineEvent }) {
  const collected = isCollected(event)
  const status = statusLabel(event)

  return (
    <div className="relative grid gap-4 rounded-xl border border-slate-200 bg-white p-4 shadow-sm md:grid-cols-[240px_minmax(0,1fr)]">
      <div className="flex items-start gap-3">
        <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full border text-sm font-bold ${
          collected
            ? "border-emerald-200 bg-emerald-50 text-emerald-700"
            : "border-amber-200 bg-amber-50 text-amber-700"
        }`}>
          {collected ? <CheckCircle2 className="h-4 w-4" /> : <AlertTriangle className="h-4 w-4" />}
        </div>

        <div>
          <h4 className="font-semibold text-[#031a41]">{event.title}</h4>
          <p className="mt-1 font-mono text-xs text-slate-400">{event.stage}</p>
          <p className="mt-2 text-xs leading-5 text-slate-500">{event.description ?? "-"}</p>
        </div>
      </div>

      <div className="grid gap-2 text-sm">
        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">状态</span>
          <span className={collected ? "font-semibold text-emerald-700" : "font-semibold text-amber-700"}>
            {status}
          </span>
        </div>

        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">Artifact Kind</span>
          <span className="break-words font-mono text-slate-900">{event.artifactKind ?? "-"}</span>
        </div>

        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">Artifact</span>
          <span className="break-words font-mono text-slate-900">{event.artifact?.baseName ?? "-"}</span>
        </div>

        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">ModifiedAt</span>
          <span className="break-words font-mono text-slate-900">{formatTime(event.artifact?.modifiedAt)}</span>
        </div>

        <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">Size</span>
          <span className="font-mono text-slate-900">{formatBytes(event.artifact?.sizeBytes)}</span>
        </div>
      </div>
    </div>
  )
}

export function TimelineProductView({
  selected,
  body,
}: {
  selected: ReleaseIndexItem
  body?: string
}) {
  const timeline = parseTimelineDocument(body)
  const events = timeline?.events ?? fallbackEventsFromResources(selected)
  const collectedCount = timeline?.coverage?.collected ?? events.filter(isCollected).length
  const totalCount = timeline?.coverage?.total ?? events.length
  const missingStages = timeline?.coverage?.missingStages ?? events.filter((event) => !isCollected(event)).map((event) => event.stage)
  const sourceMode = timeline ? "Structured release-timeline.json" : "Metadata fallback"

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-sky-100 bg-sky-50 p-4">
        <div className="flex items-center gap-2 font-semibold text-sky-900">
          <GitBranch className="h-4 w-4" />
          Release Evidence Timeline
        </div>
        <p className="mt-2 text-sm leading-6 text-sky-800">
          该视图优先读取结构化 release-timeline.json，展示一次发布从上下文采集、决策、策略裁决、证据生成到 Runbook / RCA 的事件链。
          如果 timeline 资源缺失，则回退到 Release Portal metadata。
        </p>
        <div className="mt-3 inline-flex rounded-full border border-sky-200 bg-white px-3 py-1 text-xs font-semibold text-sky-800">
          Source：{sourceMode}
        </div>
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <section className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="flex items-center gap-2 text-sm font-semibold text-[#031a41]">
            <FileText className="h-4 w-4" />
            Release
          </div>
          <p className="mt-3 font-mono text-xl font-bold text-[#031a41]">
            {timeline?.releaseId ?? selected.releaseId}
          </p>
          <p className="mt-1 text-xs text-slate-500">
            GeneratedAt {timeline?.generatedAt ?? selected.generatedAt}
          </p>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="flex items-center gap-2 text-sm font-semibold text-[#031a41]">
            <ShieldCheck className="h-4 w-4" />
            Outcome
          </div>
          <p className="mt-3 font-mono text-xl font-bold text-[#031a41]">
            {timeline?.releaseResult ?? selected.summary?.releaseResult ?? "-"}
          </p>
          <p className="mt-1 text-xs text-slate-500">
            Policy {timeline?.policyDecision ?? selected.summary?.policyDecision ?? "-"} · Action {timeline?.finalAction ?? selected.summary?.finalAction ?? "-"}
          </p>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="flex items-center gap-2 text-sm font-semibold text-[#031a41]">
            <Clock3 className="h-4 w-4" />
            Evidence Coverage
          </div>
          <p className="mt-3 font-mono text-xl font-bold text-[#031a41]">
            {collectedCount}/{totalCount}
          </p>
          <p className="mt-1 text-xs text-slate-500">已收集关键发布证据数量</p>
        </section>
      </div>

      {missingStages.length > 0 ? (
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-800">
          Missing Stages：<span className="font-mono">{missingStages.join(", ")}</span>
        </div>
      ) : null}

      <div className="space-y-3">
        {events.map((event, index) => (
          <TimelineItem
            key={`${event.stage}-${event.sequence ?? index}`}
            event={event}
          />
        ))}
      </div>

      <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm leading-6 text-emerald-800">
        说明：当前 Timeline 是只读证据链，不会触发 Rollback、Promote、Patch、Delete 或 GitOps 写入。
      </div>
    </div>
  )
}
