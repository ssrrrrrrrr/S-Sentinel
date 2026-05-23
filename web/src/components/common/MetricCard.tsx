import type { LucideIcon } from "lucide-react"
import { Panel } from "@/components/common/Panel"

export function MetricCard({
  label,
  value,
  rawValue,
  icon: Icon,
  hint,
}: {
  label: string
  value: string
  rawValue?: string
  icon: LucideIcon
  hint: string
}) {
  return (
    <Panel
      padding="sm"
      className="group relative overflow-hidden transition hover:border-[#35517a] hover:bg-[#101a29]"
    >
      <div className="absolute inset-x-0 top-0 h-[3px] bg-[#294061]" />
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">{label}</p>
        <div className="rounded-lg border border-[#243044] bg-[#0b121d] p-2 text-slate-400">
          <Icon className="h-4 w-4" />
        </div>
      </div>
      <div className="mt-4">
        <p className="break-words text-[clamp(1.35rem,2vw,1.75rem)] font-bold tracking-tight text-slate-100">
          {value}
        </p>
        {rawValue ? (
          <p className="mt-1 break-all font-mono text-[11px] text-slate-500">{rawValue}</p>
        ) : null}
        <p className="mt-1 text-xs text-slate-500">{hint}</p>
      </div>
    </Panel>
  )
}
