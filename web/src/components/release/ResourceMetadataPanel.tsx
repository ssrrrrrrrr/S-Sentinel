import type { ReleaseIndexItem } from "@/types/release"
import { resourceKeys } from "@/utils/format"

export function ResourceMetadataPanel({ selected }: { selected: ReleaseIndexItem }) {
  const keys = resourceKeys(selected)

  if (keys.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-slate-50 p-5 text-sm text-slate-600">
        当前发布没有可展示的资源索引。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">关联资源</h4>
      </div>
      <div className="divide-y divide-slate-200">
        {keys.map((key) => {
          const resource = selected.resources?.[key]
          return (
            <div key={key} className="grid gap-3 px-4 py-3 text-sm md:grid-cols-[180px_1fr_120px]">
              <span className="font-mono font-semibold text-[#031a41]">{key}</span>
              <span className="truncate text-slate-500">{resource?.baseName ?? resource?.file ?? "-"}</span>
              <span className="text-right text-slate-500">{resource?.sizeBytes ?? 0} bytes</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
