import type { LucideIcon } from "lucide-react"
import { statusClass } from "@/utils/format"

export function ProductMetricCard({
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
  icon: LucideIcon
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
