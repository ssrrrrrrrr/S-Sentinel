import { ClipboardList, RotateCcw, ShieldCheck, Target } from "lucide-react"
import {
  markdownBooleanValue,
  markdownListAfterHeading,
  markdownValue,
} from "./shared"

function InfoCard({
  title,
  icon,
  children,
}: {
  title: string
  icon: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <section className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4 shadow-sm">
      <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-slate-100">
        {icon}
        {title}
      </div>
      {children}
    </section>
  )
}

function Rows({ rows }: { rows: Array<[string, string]> }) {
  return (
    <div className="grid gap-2 text-sm">
      {rows.map(([key, value]) => (
        <div key={key} className="grid grid-cols-[160px_minmax(0,1fr)] gap-3 rounded-lg bg-[#070b12] px-3 py-2">
          <span className="text-slate-500">{key}</span>
          <span className="break-words font-mono text-slate-100">{value}</span>
        </div>
      ))}
    </div>
  )
}

function ActionList({ items }: { items: string[] }) {
  if (items.length === 0) {
    return <p className="text-sm text-slate-500">当前 Runbook 没有提取到明确的操作步骤。</p>
  }

  return (
    <ol className="space-y-2">
      {items.map((item, index) => (
        <li key={`${item}-${index}`} className="rounded-lg border border-[#1f2b3d] bg-[#070b12] px-3 py-2 text-sm leading-6 text-slate-300">
          <span className="mr-2 font-mono text-xs font-semibold text-sky-300">#{index + 1}</span>
          {item}
        </li>
      ))}
    </ol>
  )
}

export function RunbookProductView({ body }: { body: string }) {
  const safeToRetry = markdownBooleanValue(body, "Safe To Retry")
  const actions = markdownListAfterHeading(body, "## 5. Recommended Actions")
  const rollbackActions = markdownListAfterHeading(body, "## 6. Rollback / Recovery Notes")

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-cyan-100 bg-[#101a29] p-4">
        <div className="flex items-center gap-2 font-semibold text-sky-200">
          <ClipboardList className="h-4 w-4" />
          Runbook 执行视图
        </div>
        <p className="mt-2 text-sm leading-6 text-sky-200">
          该视图从 Runbook Markdown 中提取关键状态、目标对象和建议动作。当前仍是只读展示，不会执行任何 Kubernetes / GitOps 操作。
        </p>
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <InfoCard title="Release Status" icon={<ShieldCheck className="h-4 w-4" />}>
          <Rows
            rows={[
              ["Release ID", markdownValue(body, "Release ID")],
              ["Release Result", markdownValue(body, "Release Result")],
              ["Policy Decision", markdownValue(body, "Policy Decision")],
              ["Final Action", markdownValue(body, "Final Action")],
              ["Execution Mode", markdownValue(body, "Execution Mode")],
              ["Safe To Retry", safeToRetry === null ? "-" : String(safeToRetry)],
            ]}
          />
        </InfoCard>

        <InfoCard title="Target" icon={<Target className="h-4 w-4" />}>
          <Rows
            rows={[
              ["Namespace", markdownValue(body, "Namespace")],
              ["Rollout", markdownValue(body, "Rollout")],
              ["AnalysisRun", markdownValue(body, "AnalysisRun")],
              ["Rollout Phase", markdownValue(body, "Rollout Phase")],
              ["AnalysisRun Phase", markdownValue(body, "AnalysisRun Phase")],
            ]}
          />
        </InfoCard>
      </div>

      <InfoCard title="Recommended Actions" icon={<ClipboardList className="h-4 w-4" />}>
        <ActionList items={actions} />
      </InfoCard>

      <InfoCard title="Rollback / Recovery Notes" icon={<RotateCcw className="h-4 w-4" />}>
        <ActionList items={rollbackActions} />
      </InfoCard>

      <div className="rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm leading-6 text-amber-200">
        安全边界：Runbook 只提供人工操作建议。当前 Release Portal 不会自动执行 rollback、promote、patch、delete 或 GitOps 写入。
      </div>
    </div>
  )
}

