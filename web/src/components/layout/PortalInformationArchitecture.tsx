import type { LatestReleaseResponse } from "@/types/release"

type PortalLane = {
  title: string
  subtitle: string
  tabs: string[]
  signal: string
}

const portalLanes: PortalLane[] = [
  {
    title: "Release Control Plane",
    subtitle: "从一次发布进入 SLO、证据、时间线和最终结果。",
    tabs: ["概览", "Evidence", "Timeline"],
    signal: "release → evidence → timeline",
  },
  {
    title: "Safety & Governance",
    subtitle: "聚合策略裁决、安全边界、人工审批和执行申请视角。",
    tabs: ["Evidence", "Action Plan", "Runbook"],
    signal: "policy → approval → request",
  },
  {
    title: "AI Advisor & Planning",
    subtitle: "展示只读 AI 建议、智能分析、规划结果和调查线索。",
    tabs: ["Intelligence", "AI Advice", "Action Plan"],
    signal: "advisor → plan → recommendation",
  },
  {
    title: "Environment & Packaging",
    subtitle: "承接 Stage 34 的多环境、GitOps overlay 和 evidence 环境字段。",
    tabs: ["Context", "Evidence", "概览"],
    signal: "env → overlay → artifact",
  },
]

export function PortalInformationArchitecture({
  latest,
  releaseCount,
  activeTab,
  onTabChange,
}: {
  latest?: LatestReleaseResponse
  releaseCount: number
  activeTab: string
  onTabChange: (tab: string) => void
}) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white/95 p-5 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Portal Information Architecture
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-[#031a41]">
            按控制平面对象组织 Release Portal，而不是继续堆叠零散报告。
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            Stage 35 将一次发布串成产品主线：环境、SLO、策略、供应链、AI Advisor、执行申请和 Evidence Record。
            当前入口仍然保持只读，只做可观察和可审计展示。
          </p>
        </div>

        <div className="grid grid-cols-2 gap-2 text-xs lg:min-w-[280px]">
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <p className="text-slate-500">Release Records</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">{releaseCount}</p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <p className="text-slate-500">Safety Mode</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">
              {latest?.safety?.readOnly === false ? "Writable" : "Read-only"}
            </p>
          </div>
        </div>
      </div>

      <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {portalLanes.map((lane) => (
          <div
            key={lane.title}
            className="rounded-2xl border border-slate-200 bg-slate-50 p-4"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h4 className="font-semibold text-[#031a41]">{lane.title}</h4>
                <p className="mt-1 text-xs font-medium text-cyan-700">{lane.signal}</p>
              </div>
              <span className="rounded-full border border-cyan-200 bg-white px-2.5 py-1 text-[11px] font-semibold text-cyan-700">
                Stage 35
              </span>
            </div>

            <p className="mt-3 min-h-[48px] text-sm leading-6 text-slate-600">
              {lane.subtitle}
            </p>

            <div className="mt-4 flex flex-wrap gap-2">
              {lane.tabs.map((tab) => (
                <button
                  key={`${lane.title}-${tab}`}
                  type="button"
                  onClick={() => onTabChange(tab)}
                  className={`rounded-full border px-3 py-1.5 text-xs font-semibold transition ${
                    activeTab === tab
                      ? "border-[#031a41] bg-[#031a41] text-white"
                      : "border-slate-200 bg-white text-slate-600 hover:border-cyan-200 hover:text-cyan-700"
                  }`}
                >
                  {tab}
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}
