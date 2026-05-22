import type { LatestReleaseResponse } from "@/types/release"

type PortalLane = {
  title: string
  subtitle: string
  tabs: string[]
  signal: string
  objects: string[]
}

const portalLanes: PortalLane[] = [
  {
    title: "Release Operations",
    subtitle: "从一次发布进入概览、SLO 结果、时间线和最终发布状态。",
    tabs: ["概览", "Evidence", "Timeline"],
    signal: "release → slo → result",
    objects: ["releaseId", "service", "env", "version"],
  },
  {
    title: "Evidence Control Plane",
    subtitle: "把 release evidence、环境上下文和控制平面对象串成可审计证据链。",
    tabs: ["Evidence", "Context", "概览"],
    signal: "evidence → object → audit",
    objects: ["evidenceId", "sloId", "imageDigest"],
  },
  {
    title: "Safety & Governance",
    subtitle: "聚合 Policy Guard、Supply Chain Gate、人工审批和执行申请视角。",
    tabs: ["Evidence", "Action Plan", "Runbook"],
    signal: "policy → gate → approval",
    objects: ["policyDecisionId", "signedReleaseGateId", "executionRequestId"],
  },
  {
    title: "AI Advisor Observability",
    subtitle: "展示只读 AI 建议、AgentTrace、规划结果和调查线索，先可观测再可执行。",
    tabs: ["AI Advice", "Intelligence", "RCA"],
    signal: "agent → trace → explanation",
    objects: ["agentRunId", "agentTraceId", "traceId"],
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
  const safetyMode = latest?.safety?.readOnly === false ? "Writable" : "Read-only"

  return (
    <section className="rounded-2xl border border-slate-200 bg-white/95 p-5 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Stage 41 · Portal as Product
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-[#031a41]">
            将 Release Portal 整理成产品化控制台，而不是继续堆叠零散报告。
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            当前阶段保持只读展示，优先把 Release、Evidence、Policy、Supply Chain、AI Advisor 和 AgentTrace
            放到统一的信息架构里。后续再逐步补 Evidence Search、Policy Explanation、Supply Chain Gate View
            和 Agent Trace View。
          </p>
        </div>

        <div className="grid grid-cols-2 gap-2 text-xs lg:min-w-[280px]">
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <p className="text-slate-500">Release Records</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">{releaseCount}</p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <p className="text-slate-500">Portal Mode</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">{safetyMode}</p>
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
                Stage 41
              </span>
            </div>

            <p className="mt-3 min-h-[72px] text-sm leading-6 text-slate-600">
              {lane.subtitle}
            </p>

            <div className="mt-4 rounded-xl border border-slate-200 bg-white p-3">
              <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-400">
                Key Objects
              </p>
              <div className="mt-2 flex flex-wrap gap-2">
                {lane.objects.map((objectName) => (
                  <span
                    key={`${lane.title}-${objectName}`}
                    className="rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1 font-mono text-[11px] font-semibold text-slate-600"
                  >
                    {objectName}
                  </span>
                ))}
              </div>
            </div>

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
