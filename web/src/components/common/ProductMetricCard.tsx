import type { LucideIcon } from "lucide-react"
import { Panel } from "@/components/common/Panel"

function iconTone(value: string) {
  const normalized = value.toLowerCase()

  if (normalized.includes("fail") || normalized.includes("deny") || normalized.includes("block") || normalized.includes("high")) {
    return "border-rose-900/45 bg-rose-950/25 text-rose-200"
  }

  if (normalized.includes("warn") || normalized.includes("pending") || normalized.includes("medium") || normalized.includes("required")) {
    return "border-amber-900/45 bg-amber-950/25 text-amber-200"
  }

  if (normalized.includes("pass") || normalized.includes("allow") || normalized.includes("low") || normalized.includes("success")) {
    return "border-emerald-900/45 bg-emerald-950/25 text-emerald-200"
  }

  return "border-[#243044] bg-[#0b121d] text-slate-400"
}

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
    <Panel padding="sm" className="min-w-0 overflow-hidden transition hover:border-[#35517a] hover:bg-[#101a29]">
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
            className="mt-3 min-w-0 break-words text-2xl font-bold leading-tight tracking-tight text-slate-100 [overflow-wrap:anywhere]"
          >
            {value}
          </p>

          {rawValue ? (
            <p
              title={rawValue}
              className="mt-2 min-w-0 break-words font-mono text-xs leading-5 text-slate-500 [overflow-wrap:anywhere]"
            >
              {rawValue}
            </p>
          ) : null}

          {hint ? (
            <p
              title={hint}
              className="mt-3 min-w-0 break-words text-sm leading-6 text-slate-500 [overflow-wrap:anywhere]"
            >
              {hint}
            </p>
          ) : null}
        </div>

        <div className={`shrink-0 rounded-lg border p-2 ${iconTone(statusValue ?? value)}`}>
          <Icon className="h-4 w-4" />
        </div>
      </div>
    </Panel>
  )
}
