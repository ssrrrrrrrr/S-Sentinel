import type { PropsWithChildren } from "react"

export type PillTone = "unstyled" | "neutral" | "muted" | "info" | "dark"

const toneClass: Record<PillTone, string> = {
  unstyled: "",
  neutral: "border-[#26354a] bg-[#101a29] text-slate-200",
  muted: "border-[#1f2b3d] bg-[#0b121d] text-slate-400",
  info: "border-sky-800/50 bg-sky-950/20 text-sky-200",
  dark: "border-[#35517a] bg-[#14233a] text-slate-100",
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
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold leading-none ${toneClass[tone]} ${className}`}
    >
      {children}
    </span>
  )
}
