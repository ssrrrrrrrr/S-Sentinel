export function KeyValueRows({ rows }: { rows: Array<[string, string]> }) {
  return (
    <div className="divide-y divide-slate-200 rounded-xl border border-slate-200 bg-white">
      {rows.map(([key, value]) => (
        <div key={key} className="grid gap-2 px-4 py-3 text-sm md:grid-cols-[150px_1fr]">
          <span className="font-mono text-xs text-slate-500">{key}</span>
          <span className="break-all font-mono text-[#031a41]">{value || "-"}</span>
        </div>
      ))}
    </div>
  )
}
