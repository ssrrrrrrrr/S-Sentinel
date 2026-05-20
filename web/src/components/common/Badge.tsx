import { statusClass } from "@/utils/format"

export function Badge({ value, label }: { value: string; label?: string }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${statusClass(value)}`}>
      {label ?? value}
    </span>
  )
}
