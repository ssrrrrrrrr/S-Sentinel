import type { LucideIcon } from "lucide-react"
import { statusClass } from "@/utils/format"

export function ProductMetricCard({
  label,
  value,
  rawValue,
  icon: Icon,
  hint,
  statusValue,
}: {
  label: string
  value: string
  rawValue?: string
  icon: LucideIcon
  hint?: string
  statusValue?: string
}) {
  return (
    <div className="min-w-0 overflow-hidden rounded-xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60">
      <div className="flex min-w-0 items-start justify-between gap-4">
        <div className="min-w-0 flex-1">
          <p
            title={label}
            className="min-w-0 break-words text-sm font-semibold text-slate-500"
          >
            {label}
          </p>

          <p
            title={value}
            className="mt-3 min-w-0 break-words text-2xl font-bold leading-tight tracking-tight text-[#031a41] [overflow-wrap:anywhere]"
          >
            {value}
          </p>

          {rawValue ? (
            <p
              title={rawValue}
              className="mt-2 min-w-0 break-words font-mono text-xs leading-5 text-slate-400 [overflow-wrap:anywhere]"
            >
              {rawValue}
            </p>
          ) : null}

          {hint ? (
            <p
              title={hint}
              className="mt-3 min-w-0 break-words text-sm leading-6 text-slate-600 [overflow-wrap:anywhere]"
            >
              {hint}
            </p>
          ) : null}
        </div>

        <div className={`shrink-0 rounded-lg border p-2 ${statusClass(statusValue ?? value)}`}>
          <Icon className="h-4 w-4" />
        </div>
      </div>
    </div>
  )
}
