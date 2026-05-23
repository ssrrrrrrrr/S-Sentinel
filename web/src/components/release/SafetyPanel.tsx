import type { LatestReleaseResponse } from "@/types/release"

export function SafetyPanel({ latest }: { latest?: LatestReleaseResponse }) {
  const safety = latest?.safety
  const rows = [
    ["mode", latest?.mode ?? "read_only"],
    ["readOnly", String(safety?.readOnly ?? true)],
    ["willExecute", String(safety?.willExecute ?? false)],
    ["supportsRollback", String(safety?.supportsRollback ?? false)],
    ["supportsPromote", String(safety?.supportsPromote ?? false)],
    ["supportsPatch", String(safety?.supportsPatch ?? false)],
    ["supportsDelete", String(safety?.supportsDelete ?? false)],
  ]

  return (
    <div className="grid gap-3 md:grid-cols-2">
      {rows.map(([key, value]) => (
        <div key={key} className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <p className="font-mono text-xs text-slate-500">{key}</p>
          <p className="mt-2 font-mono text-sm font-semibold text-slate-100">{value}</p>
        </div>
      ))}
    </div>
  )
}
