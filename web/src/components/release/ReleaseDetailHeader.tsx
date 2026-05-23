import { GitBranch } from "lucide-react"
import { releaseTabIds } from "@/config/releaseTabs"
import type { ReleaseIndexItem } from "@/types/release"

export function ReleaseDetailHeader({
  selected,
  activeTab,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  activeTab: string
  onTabChange: (tab: string) => void
}) {
  const selectedSummary = selected.summary

  return (
    <div className="border-b border-[#1a2535] p-6">
      <div className="flex flex-col justify-between gap-5 lg:flex-row lg:items-start">
        <div>
          <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
            <GitBranch className="h-4 w-4 text-[#5d8fd8]" />
            当前选中发布
          </div>
          <h3 className="mt-3 text-2xl font-semibold tracking-tight text-slate-100">{selected.releaseId}</h3>
          <p className="mt-2 text-sm text-slate-500">
            GeneratedAt {selected.generatedAt} · ModifiedAt {selected.modifiedAt}
          </p>
        </div>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
            <p className="text-xs text-slate-500">Risk Score</p>
            <p className="mt-1 text-xl font-semibold text-slate-100">{selectedSummary.riskScore}<span className="text-xs text-slate-500"> /100</span></p>
          </div>
          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
            <p className="text-xs text-slate-500">资源数量</p>
            <p className="mt-1 text-xl font-semibold text-slate-100">{selected.resourceCount}</p>
          </div>
        </div>
      </div>

      <div className="mt-6 flex flex-wrap gap-2 rounded-2xl border border-[#1f2b3d] bg-[#0b121d] p-1.5">
        {releaseTabIds.map((tab) => (
          <button
            key={tab}
            type="button"
            onClick={() => onTabChange(tab)}
            className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
              activeTab === tab
                ? "bg-[#14233a] text-slate-50 shadow-sm"
                : "text-slate-400 hover:bg-[#101a29] hover:text-slate-100"
            }`}
          >
            {tab}
          </button>
        ))}
      </div>
    </div>
  )
}
