import { FileSearch, Lightbulb, Radar, ShieldAlert } from "lucide-react"
import {
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
    <section className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-[#031a41]">
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
        <div key={key} className="grid grid-cols-[170px_minmax(0,1fr)] gap-3 rounded-lg bg-slate-50 px-3 py-2">
          <span className="text-slate-500">{key}</span>
          <span className="break-words font-mono text-slate-900">{value}</span>
        </div>
      ))}
    </div>
  )
}

function BulletPanel({ items, emptyText }: { items: string[]; emptyText: string }) {
  if (items.length === 0) {
    return <p className="text-sm text-slate-500">{emptyText}</p>
  }

  return (
    <ul className="space-y-2">
      {items.map((item, index) => (
        <li key={`${item}-${index}`} className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm leading-6 text-slate-700">
          {item}
        </li>
      ))}
    </ul>
  )
}

export function RCAProductView({ body }: { body: string }) {
  const evidence = markdownListAfterHeading(body, "## 3. SLO Evidence")
  const likelyCause = markdownListAfterHeading(body, "## 4. Likely Cause")
  const mitigation = markdownListAfterHeading(body, "## 6. Mitigation")
  const followUp = markdownListAfterHeading(body, "## 7. Follow-up Actions")

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-indigo-100 bg-indigo-50 p-4">
        <div className="flex items-center gap-2 font-semibold text-indigo-900">
          <FileSearch className="h-4 w-4" />
          RCA 复盘视图
        </div>
        <p className="mt-2 text-sm leading-6 text-indigo-800">
          该视图将 RCA Markdown 拆解为事故摘要、发布上下文、SLO 证据、可能原因、缓解措施和后续动作，方便复盘阅读。
        </p>
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <InfoCard title="Incident Summary" icon={<ShieldAlert className="h-4 w-4" />}>
          <Rows
            rows={[
              ["Release ID", markdownValue(body, "Release ID")],
              ["Release Result", markdownValue(body, "Release Result")],
              ["Policy Decision", markdownValue(body, "Policy Decision")],
              ["Final Action", markdownValue(body, "Final Action")],
              ["Execution Mode", markdownValue(body, "Execution Mode")],
              ["Requires Approval", markdownValue(body, "Requires Human Approval")],
            ]}
          />
        </InfoCard>

        <InfoCard title="Release Context" icon={<Radar className="h-4 w-4" />}>
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

      <InfoCard title="SLO Evidence" icon={<Radar className="h-4 w-4" />}>
        <BulletPanel items={evidence} emptyText="当前 RCA 没有提取到失败 SLO 列表，可能是一次健康发布。" />
      </InfoCard>

      <InfoCard title="Likely Cause" icon={<Lightbulb className="h-4 w-4" />}>
        <BulletPanel items={likelyCause} emptyText="当前 RCA 没有提取到明确的可能原因。" />
      </InfoCard>

      <div className="grid gap-4 xl:grid-cols-2">
        <InfoCard title="Mitigation" icon={<ShieldAlert className="h-4 w-4" />}>
          <BulletPanel items={mitigation} emptyText="当前 RCA 没有提取到缓解措施。" />
        </InfoCard>

        <InfoCard title="Follow-up Actions" icon={<Lightbulb className="h-4 w-4" />}>
          <BulletPanel items={followUp} emptyText="当前 RCA 没有提取到后续动作。" />
        </InfoCard>
      </div>
    </div>
  )
}
