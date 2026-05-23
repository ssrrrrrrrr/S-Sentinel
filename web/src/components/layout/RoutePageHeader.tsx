export type RouteHeaderBadgeTone = "neutral" | "info" | "success" | "warning" | "danger"

const badgeToneClass: Record<RouteHeaderBadgeTone, string> = {
  neutral: "border-[#243044] bg-[#0b121d] text-slate-300",
  info: "border-[#35517a] bg-[#101a29] text-sky-200",
  success: "border-emerald-900/45 bg-emerald-950/20 text-emerald-200",
  warning: "border-amber-900/45 bg-amber-950/20 text-amber-200",
  danger: "border-rose-900/45 bg-rose-950/20 text-rose-200",
}

export type RouteHeaderBadge = {
  label: string
  value: string
  tone?: RouteHeaderBadgeTone
}

export function RoutePageHeader({
  eyebrow,
  title,
  description,
  badges = [],
}: {
  eyebrow: string
  title: string
  description: string
  badges?: RouteHeaderBadge[]
}) {
  return (
    <section className="rounded-2xl border border-[#1f2b3d] bg-[#0f1724] p-5 shadow-sm shadow-black/20">
      <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">
            {eyebrow}
          </p>
          <h2 className="mt-2 text-xl font-semibold tracking-tight text-slate-100">
            {title}
          </h2>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            {description}
          </p>
        </div>

        {badges.length > 0 ? (
          <div className="flex flex-wrap gap-2 lg:justify-end">
            {badges.map((badge) => (
              <span
                key={`${badge.label}-${badge.value}`}
                className={`rounded-full border px-3 py-1 font-mono text-xs font-semibold ${badgeToneClass[badge.tone ?? "neutral"]}`}
                title={`${badge.label}: ${badge.value}`}
              >
                {badge.label}={badge.value}
              </span>
            ))}
          </div>
        ) : null}
      </div>
    </section>
  )
}
