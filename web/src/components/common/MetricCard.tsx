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
      className="group relative overflow-hidden transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md"
    >
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
    </Panel>
  )
}
