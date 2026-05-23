import type { PropsWithChildren } from "react"

export type PanelTone = "default" | "muted" | "danger"
export type PanelPadding = "none" | "sm" | "md" | "lg"

const toneClass: Record<PanelTone, string> = {
  default: "border-[#1f2b3d] bg-[#0f1724] text-slate-100 shadow-black/20",
  muted: "border-[#1a2535] bg-[#0b121d] text-slate-300 shadow-black/10",
  danger: "border-rose-900/45 bg-rose-950/20 text-rose-200 shadow-black/10",
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
    <section
      className={`rounded-2xl border shadow-sm ${toneClass[tone]} ${paddingClass[padding]} ${className}`}
    >
      {children}
    </section>
  )
}
