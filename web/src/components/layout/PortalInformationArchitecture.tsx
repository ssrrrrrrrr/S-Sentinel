import {
  Activity,
  Database,
  GitBranch,
  LockKeyhole,
  ShieldCheck,
} from "lucide-react"
import { Panel } from "@/components/common/Panel"
import { Pill } from "@/components/common/Pill"
import type { LatestReleaseResponse } from "@/types/release"

type PortalLane = {
  title: string
  subtitle: string
  tabs: string[]
  signal: string
  objects: string[]
  icon: typeof GitBranch
}

const portalLanes: PortalLane[] = [
  {
    title: "Release Operations",
    subtitle: "从一次发布进入概览、SLO 结果、时间线和最终状态。",
    tabs: ["概览", "Evidence", "Timeline"],
    signal: "release → slo → result",
    objects: ["releaseId", "service", "env", "version"],
    icon: GitBranch,
  },
  {
    title: "Evidence Plane",
    subtitle: "把发布证据、环境上下文和控制平面对象串成审计链。",
    tabs: ["Evidence", "Context", "概览"],
    signal: "evidence → object → audit",
    objects: ["evidenceId", "sloId", "imageDigest"],
    icon: Database,
  },
  {
    title: "Safety & Governance",
    subtitle: "聚合 Policy Guard、Signed Gate、审批边界和执行申请。",
    tabs: ["Evidence", "Action Plan", "Runbook"],
    signal: "policy → gate → approval",
    objects: ["policyDecisionId", "signedReleaseGateId", "executionRequestId"],
    icon: ShieldCheck,
  },
  {
    title: "Advisor Trace",
    subtitle: "展示只读建议、AgentTrace、规划结果和调查线索。",
    tabs: ["AI Advice", "Intelligence", "RCA"],
    signal: "advisor → trace → explanation",
    objects: ["agentRunId", "agentTraceId", "traceId"],
    icon: Activity,
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
    <Panel padding="md" className="border-[#1f2b3d] bg-[#0f1724]">
      <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Control Plane Map
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-slate-100">
            发布控制台围绕 Release、Evidence、Policy 和 Approval 展开。
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            首页不再承担项目介绍，而是作为控制室入口：快速定位发布状态、证据链、策略裁决、供应链门禁和 Advisor Trace。
          </p>
        </div>

        <div className="grid grid-cols-2 gap-2 text-xs lg:min-w-[280px]">
          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
            <p className="flex items-center gap-2 text-slate-500">
              <Database className="h-3.5 w-3.5" />
              Release Records
            </p>
            <p className="mt-1 text-lg font-semibold text-slate-100">{releaseCount}</p>
          </div>
          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
            <p className="flex items-center gap-2 text-slate-500">
              <LockKeyhole className="h-3.5 w-3.5" />
              Portal Mode
            </p>
            <p className="mt-1 text-lg font-semibold text-slate-100">{safetyMode}</p>
          </div>
        </div>
      </div>

      <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {portalLanes.map((lane) => {
          const Icon = lane.icon

          return (
            <div
              key={lane.title}
              className="rounded-2xl border border-[#1f2b3d] bg-[#0b121d] p-4"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="flex items-center gap-2">
                    <Icon className="h-4 w-4 text-[#5d8fd8]" />
                    <h4 className="font-semibold text-slate-100">{lane.title}</h4>
                  </div>
                  <p className="mt-2 font-mono text-xs font-medium text-slate-500">
                    {lane.signal}
                  </p>
                </div>
              </div>

              <p className="mt-3 min-h-[66px] text-sm leading-6 text-slate-400">
                {lane.subtitle}
              </p>

              <div className="mt-4 rounded-xl border border-[#1f2b3d] bg-[#070b12] p-3">
                <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-600">
                  Key Objects
                </p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {lane.objects.map((objectName) => (
                    <Pill
                      key={`${lane.title}-${objectName}`}
                      tone="muted"
                      className="font-mono text-[11px]"
                    >
                      {objectName}
                    </Pill>
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
                        ? "border-[#35517a] bg-[#14233a] text-slate-50"
                        : "border-[#1f2b3d] bg-[#0f1724] text-slate-400 hover:border-[#35517a] hover:text-slate-100"
                    }`}
                  >
                    {tab}
                  </button>
                ))}
              </div>
            </div>
          )
        })}
      </div>
    </Panel>
  )
}

