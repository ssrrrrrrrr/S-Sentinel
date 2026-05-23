import { Pill } from "@/components/common/Pill"

function badgeTone(value: string) {
  const normalized = value.toLowerCase()

  if (normalized.includes("fail") || normalized.includes("deny") || normalized.includes("block") || normalized.includes("error")) {
    return "border-rose-900/45 bg-rose-950/25 text-rose-200"
  }

  if (normalized.includes("missing") || normalized.includes("warn") || normalized.includes("pending") || normalized.includes("partial") || normalized.includes("required")) {
    return "border-amber-900/45 bg-amber-950/25 text-amber-200"
  }

  if (normalized.includes("pass") || normalized.includes("allow") || normalized.includes("linked") || normalized.includes("success") || normalized.includes("read-only")) {
    return "border-emerald-900/45 bg-emerald-950/25 text-emerald-200"
  }

  return "border-[#243044] bg-[#0b121d] text-slate-300"
}

export function Badge({ value, label }: { value: string; label?: string }) {
  return (
    <Pill tone="unstyled" className={badgeTone(value)}>
      {label ?? value}
    </Pill>
  )
}
