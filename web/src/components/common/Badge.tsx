import { Pill } from "@/components/common/Pill"
import { statusClass } from "@/utils/format"

export function Badge({ value, label }: { value: string; label?: string }) {
  return (
    <Pill tone="unstyled" className={statusClass(value)}>
      {label ?? value}
    </Pill>
  )
}
