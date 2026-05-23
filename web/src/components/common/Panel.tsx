import type { PropsWithChildren } from "react"

export type PanelTone = "default" | "muted" | "danger"
export type PanelPadding = "none" | "sm" | "md" | "lg"

const toneClass: Record<PanelTone, string> = {
  default: "border-slate-200 bg-white text-slate-900 shadow-slate-200/60",
  muted: "border-slate-200 bg-white text-slate-600 shadow-slate-200/60",
  danger: "border-rose-200 bg-rose-50 text-rose-700 shadow-rose-100/60",
}

const paddingClass: Record<PanelPadding, string> = {
  none: "",
  sm: "p-4",
  md: "p-5",
  lg: "p-8",
}

export function Panel({
  children,
  tone = "default",
  padding = "md",
  className = "",
}: PropsWithChildren<{
  tone?: PanelTone
  padding?: PanelPadding
  className?: string
}>) {
  return (
    <section className={`rounded-2xl border shadow-sm ${toneClass[tone]} ${paddingClass[padding]} ${className}`}>
      {children}
    </section>
  )
}
