import type { PropsWithChildren } from "react"

export type PillTone = "unstyled" | "neutral" | "muted" | "info" | "dark"

const toneClass: Record<PillTone, string> = {
  unstyled: "",
  neutral: "border-slate-200 bg-white text-slate-600",
  muted: "border-slate-200 bg-slate-50 text-slate-600",
  info: "border-cyan-200 bg-white text-cyan-700",
  dark: "border-[#031a41] bg-[#031a41] text-white",
}

export function Pill({
  children,
  tone = "neutral",
  className = "",
  title,
}: PropsWithChildren<{
  tone?: PillTone
  className?: string
  title?: string
}>) {
  return (
    <span
      title={title}
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${toneClass[tone]} ${className}`}
    >
      {children}
    </span>
  )
}
