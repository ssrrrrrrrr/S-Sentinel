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
    <aside className="rounded-2xl border border-[#1f2b3d] bg-[#0f1724] p-4 shadow-sm shadow-black/20">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="font-semibold text-slate-100">最近发布</h3>
          <p className="text-xs text-slate-500">共 {totalCount} 条发布记录</p>
        </div>
        <button
          type="button"
          onClick={onRefresh}
          title="刷新发布列表"
          className="rounded-lg border border-[#243044] bg-[#0b121d] p-2 text-slate-400 transition hover:border-[#35517a] hover:text-slate-100"
        >
          <RefreshCw className="h-4 w-4" />
        </button>
      </div>

      <div className="relative space-y-3 before:absolute before:left-3 before:top-2 before:h-[calc(100%-1rem)] before:w-px before:bg-[#243044]">
        {releases.map((release) => {
          const isActive = release.releaseId === selected.releaseId
          const result = release.summary.releaseResult
          const pass = normalize(result).startsWith("PASS")

          return (
            <button
              key={release.releaseId}
              type="button"
              onClick={() => onSelect(release.releaseId)}
              className={`relative w-full rounded-xl border py-4 pl-9 pr-4 text-left transition ${
                isActive
                  ? "border-[#35517a] bg-[#14233a] text-slate-50 shadow-md shadow-black/20"
                  : "border-[#1f2b3d] bg-[#0b121d] text-slate-300 hover:border-[#35517a] hover:bg-[#101a29]"
              }`}
            >
              <span
                className={`absolute left-[7px] top-5 h-3 w-3 rounded-full border-2 ${
                  pass
                    ? "border-emerald-400 bg-emerald-950"
                    : "border-rose-400 bg-rose-950"
                }`}
              />
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-mono text-sm font-semibold text-slate-100">
                    {release.releaseId}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">{release.generatedAt}</p>
                </div>
                <span className="text-xs text-slate-500">{formatTime(release.modifiedAt)}</span>
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
