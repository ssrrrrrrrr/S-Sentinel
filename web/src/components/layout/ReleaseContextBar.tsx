export type ReleaseContext = {
  service: string
  environment: string
  releaseId: string
  version: string
  result: string
  imageDigest: string
}

function shortValue(value: string, maxLength = 22) {
  if (value.length <= maxLength) {
    return value
  }

  return `${value.slice(0, maxLength - 1)}…`
}

function resultTone(value: string) {
  const normalized = value.toLowerCase()

  if (normalized.includes("pass") || normalized.includes("allow") || normalized.includes("success")) {
    return {
      panel: "border-emerald-900/45 bg-emerald-950/20 shadow-[0_0_32px_rgba(16,185,129,0.08)]",
      pill: "border-emerald-800/60 bg-emerald-950/40 text-emerald-200",
      dot: "bg-emerald-400 shadow-[0_0_14px_rgba(52,211,153,0.8)]",
    }
  }

  if (normalized.includes("fail") || normalized.includes("deny") || normalized.includes("error")) {
    return {
      panel: "border-rose-900/50 bg-rose-950/15 shadow-[0_0_36px_rgba(244,63,94,0.12)]",
      pill: "border-rose-800/70 bg-rose-950/45 text-rose-200",
      dot: "bg-rose-400 shadow-[0_0_14px_rgba(251,113,133,0.8)]",
    }
  }

  if (normalized.includes("warn") || normalized.includes("pending") || normalized.includes("partial")) {
    return {
      panel: "border-amber-900/45 bg-amber-950/15 shadow-[0_0_32px_rgba(245,158,11,0.1)]",
      pill: "border-amber-800/60 bg-amber-950/40 text-amber-200",
      dot: "bg-amber-400 shadow-[0_0_14px_rgba(251,191,36,0.75)]",
    }
  }

  return {
    panel: "border-[#243044] bg-[#0b121d]",
    pill: "border-[#243044] bg-[#0b121d] text-slate-300",
    dot: "bg-slate-500",
  }
}

export function ReleaseContextBar({ context }: { context: ReleaseContext }) {
  const tone = resultTone(context.result)

  const items = [
    {
      label: "Service",
      value: context.service,
    },
    {
      label: "Environment",
      value: context.environment,
    },
    {
      label: "Release",
      value: context.releaseId,
      mono: true,
    },
    {
      label: "Version",
      value: context.version,
    },
    {
      label: "Image Digest",
      value: context.imageDigest,
      mono: true,
    },
  ]

  return (
    <section className={`rounded-2xl border bg-[#0b121d]/95 p-4 shadow-sm shadow-black/20 ${tone.panel}`}>
      <div className="grid gap-3 xl:grid-cols-[repeat(5,minmax(0,1fr))_minmax(170px,auto)]">
        {items.map((item) => (
          <div
            key={item.label}
            className="min-w-0 border-b border-[#1a2535] pb-3 last:border-b-0 xl:border-b-0 xl:border-r xl:pb-0 xl:pr-4 xl:last:border-r-0"
          >
            <p className="text-[10px] font-semibold uppercase tracking-[0.2em] text-slate-600">
              {item.label}
            </p>
            <p
              title={item.value}
              className={`mt-2 truncate text-sm font-semibold text-slate-100 ${
                item.mono ? "font-mono tracking-tight" : ""
              }`}
            >
              {shortValue(item.value)}
            </p>
          </div>
        ))}

        <div className="flex min-w-[170px] items-center xl:justify-end">
          <div className={`w-full rounded-xl border px-3 py-2.5 ${tone.pill}`}>
            <p className="text-[10px] font-semibold uppercase tracking-[0.18em] opacity-70">
              Release Result
            </p>
            <div className="mt-1.5 flex min-w-0 items-center gap-2">
              <span className={`h-2 w-2 shrink-0 rounded-full ${tone.dot}`} />
              <span className="truncate font-mono text-xs font-bold tracking-tight" title={context.result}>
                {shortValue(context.result, 28)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
