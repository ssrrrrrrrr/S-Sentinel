import type { ReleaseIndexItem } from "@/types/release"
import { resourceKeys } from "@/utils/format"

export function ResourceMetadataPanel({ selected }: { selected: ReleaseIndexItem }) {
  const keys = resourceKeys(selected)

  if (keys.length === 0) {
    return (
      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-5 text-sm text-slate-400">
        当前发布没有可展示的资源索引。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#0b121d] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">关联资源</h4>
      </div>
      <div className="divide-y divide-[#1f2b3d]">
        {keys.map((key) => {
          const resource = selected.resources?.[key]
          return (
            <div key={key} className="grid gap-3 px-4 py-3 text-sm md:grid-cols-[180px_1fr_120px]">
              <span className="font-mono font-semibold text-slate-100">{key}</span>
              <span className="truncate text-slate-400">{resource?.baseName ?? resource?.file ?? "-"}</span>
              <span className="text-right text-slate-500">{resource?.sizeBytes ?? 0} bytes</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
