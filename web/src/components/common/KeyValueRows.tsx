export function KeyValueRows({ rows }: { rows: Array<[string, string]> }) {
  return (
    <div className="divide-y divide-slate-200 rounded-xl border border-slate-200 bg-white">
      {rows.map(([key, value]) => (
        <div
          key={key}
          className="grid min-w-0 gap-2 px-4 py-3 text-sm md:grid-cols-[minmax(0,190px)_minmax(0,1fr)]"
        >
          <span
            title={key}
            className="min-w-0 break-all font-mono text-xs leading-5 text-slate-500"
          >
            {key}
          </span>
          <span
            title={value || "-"}
            className="min-w-0 break-words font-mono leading-6 text-[#031a41]"
          >
            {value || "-"}
          </span>
        </div>
      ))}
    </div>
  )
}
