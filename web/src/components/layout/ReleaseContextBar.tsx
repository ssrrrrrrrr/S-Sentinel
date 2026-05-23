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
    return "border-emerald-900/45 bg-emerald-950/25 text-emerald-200"
  }

  if (normalized.includes("fail") || normalized.includes("deny") || normalized.includes("error")) {
    return "border-rose-900/45 bg-rose-950/25 text-rose-200"
  }

  if (normalized.includes("warn") || normalized.includes("pending") || normalized.includes("partial")) {
    return "border-amber-900/45 bg-amber-950/25 text-amber-200"
  }

  return "border-[#243044] bg-[#0b121d] text-slate-300"
}

export function ReleaseContextBar({ context }: { context: ReleaseContext }) {
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
    <section className="rounded-2xl border border-[#1a2535] bg-[#0b121d] p-4 shadow-sm shadow-black/20">
      <div className="grid gap-3 xl:grid-cols-[repeat(5,minmax(0,1fr))_auto]">
        {items.map((item) => (
          <div
            key={item.label}
            className="min-w-0 border-b border-[#1a2535] pb-3 last:border-b-0 xl:border-b-0 xl:border-r xl:pb-0 xl:pr-4 xl:last:border-r-0"
          >
            <p className="text-[10px] font-semibold uppercase tracking-[0.18em] text-slate-600">
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

        <div className="flex min-w-[128px] items-center xl:justify-end">
          <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${resultTone(context.result)}`}>
            {context.result}
          </span>
        </div>
      </div>
    </section>
  )
}
