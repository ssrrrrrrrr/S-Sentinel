import { RefreshCw } from "lucide-react"
import { Badge } from "@/components/common/Badge"
import type { ReleaseIndexItem } from "@/types/release"
import {
  formatTime,
  normalize,
  resultDisplay,
  riskText,
} from "@/utils/format"

export function ReleaseList({
  releases,
  selected,
  totalCount,
  onSelect,
  onRefresh,
}: {
  releases: ReleaseIndexItem[]
  selected: ReleaseIndexItem
  totalCount: number
  onSelect: (releaseId: string) => void
  onRefresh: () => void
}) {
  return (
    <aside className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="font-semibold text-slate-950">最近发布</h3>
          <p className="text-xs text-slate-500">共 {totalCount} 条发布记录</p>
        </div>
        <button type="button" onClick={onRefresh} title="刷新发布列表">
          <RefreshCw className="h-4 w-4 text-slate-400 hover:text-cyan-600" />
        </button>
      </div>

      <div className="relative space-y-3 before:absolute before:left-3 before:top-2 before:h-[calc(100%-1rem)] before:w-px before:bg-slate-200">
        {releases.map((release) => {
          const isActive = release.releaseId === selected.releaseId
          const result = release.summary.releaseResult

          return (
            <button
              key={release.releaseId}
              type="button"
              onClick={() => onSelect(release.releaseId)}
              className={`relative w-full rounded-xl border py-4 pl-9 pr-4 text-left transition ${
                isActive
                  ? "border-[#031a41] bg-[#031a41] text-white shadow-md"
                  : "border-slate-200 bg-white text-slate-900 hover:border-cyan-200 hover:bg-cyan-50/40 hover:shadow-sm"
              }`}
            >
              <span className={`absolute left-[7px] top-5 h-3 w-3 rounded-full border-2 ${normalize(result).startsWith("PASS") ? "border-emerald-600 bg-emerald-100" : "border-rose-600 bg-rose-100"}`} />
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className={`font-mono text-sm font-semibold ${isActive ? "text-white" : "text-[#031a41]"}`}>
                    {release.releaseId}
                  </p>
                  <p className={`mt-1 text-xs ${isActive ? "text-slate-300" : "text-slate-500"}`}>{release.generatedAt}</p>
                </div>
                <span className={`text-xs ${isActive ? "text-cyan-200" : "text-slate-500"}`}>{formatTime(release.modifiedAt)}</span>
              </div>
              <div className="mt-3 flex flex-wrap gap-2">
                <Badge value={result} label={resultDisplay(result)} />
                <Badge value={release.summary.riskLevel} label={riskText(release.summary.riskLevel)} />
              </div>
            </button>
          )
        })}
      </div>
    </aside>
  )
}
