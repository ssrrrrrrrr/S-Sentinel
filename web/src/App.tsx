import { useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { fetchLatestRelease, fetchReleases } from "@/api/releases"
import {
  fetchReleaseResource,
  getResourceKindByTab,
} from "@/api/releaseResources"
import { DashboardHeader } from "@/components/layout/DashboardHeader"
import { PortalInformationArchitecture } from "@/components/layout/PortalInformationArchitecture"
import { StageBanner } from "@/components/layout/StageBanner"
import { ControlPlaneObjectCards } from "@/components/release/ControlPlaneObjectCards"
import { ControlPlaneGraph } from "@/components/release/ControlPlaneGraph"
import { EnvironmentAwarePortalPanel } from "@/components/release/EnvironmentAwarePortalPanel"
import { EvidenceStorePanel } from "@/components/release/EvidenceStorePanel"
import { PolicyExplanationPanel } from "@/components/release/PolicyExplanationPanel"
import { SupplyChainGatePanel } from "@/components/release/SupplyChainGatePanel"
import { AgentTracePanel } from "@/components/release/AgentTracePanel"
import { ApprovalConsolePanel } from "@/components/release/ApprovalConsolePanel"
import { ReleaseDetailHeader } from "@/components/release/ReleaseDetailHeader"
import { ReleaseList } from "@/components/release/ReleaseList"
import { ReleaseMetricGrid } from "@/components/release/ReleaseMetricGrid"
import { ReleaseResourcePanel } from "@/components/release/ReleaseResourcePanel"

const tabs = ["概览", "Evidence", "Intelligence", "Action Plan", "AI Advice", "Timeline", "Runbook", "RCA", "Context"]

const portalWorkspaces = [
  {
    id: "Evidence",
    title: "Evidence",
    description: "EvidenceStore 检索与对象详情",
  },
  {
    id: "Policy",
    title: "Policy",
    description: "策略裁决解释与安全边界",
  },
  {
    id: "Supply Chain",
    title: "Supply Chain",
    description: "镜像可信度与签名发布门禁",
  },
  {
    id: "Agent Trace",
    title: "Agent Trace",
    description: "AI Advisor 可观测链路",
  },
  {
    id: "Approval",
    title: "Approval",
    description: "人工审批与执行申请",
  },
  {
    id: "Environment",
    title: "Environment",
    description: "环境上下文与多环境证据",
  },
] as const

type PortalWorkspace = (typeof portalWorkspaces)[number]["id"]

function PortalWorkspaceTabs({
  activeWorkspace,
  onWorkspaceChange,
}: {
  activeWorkspace: PortalWorkspace
  onWorkspaceChange: (workspace: PortalWorkspace) => void
}) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-4 border-b border-slate-200 pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Portal Workspace
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-[#031a41]">
            选择一个产品工作台查看详情
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            发布总览保持在上方，长内容面板收进工作台，避免所有控制台视图堆在一个超长页面里。
          </p>
        </div>

        <div className="rounded-xl border border-cyan-100 bg-cyan-50 px-4 py-3 text-sm text-cyan-800">
          <p className="text-xs text-cyan-700">Active Workspace</p>
          <p className="mt-1 font-semibold">{activeWorkspace}</p>
        </div>
      </div>

      <div className="mt-4 grid gap-2 md:grid-cols-2 xl:grid-cols-6">
        {portalWorkspaces.map((workspace) => {
          const active = workspace.id === activeWorkspace

          return (
            <button
              key={workspace.id}
              type="button"
              onClick={() => onWorkspaceChange(workspace.id)}
              className={`rounded-xl border p-3 text-left transition ${
                active
                  ? "border-[#031a41] bg-[#031a41] text-white shadow-sm"
                  : "border-slate-200 bg-slate-50 text-slate-700 hover:border-cyan-200 hover:bg-cyan-50"
              }`}
            >
              <p className="text-sm font-semibold">{workspace.title}</p>
              <p className={`mt-1 text-xs leading-5 ${active ? "text-cyan-50" : "text-slate-500"}`}>
                {workspace.description}
              </p>
            </button>
          )
        })}
      </div>
    </section>
  )
}

function App() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState("概览")
  const [activeWorkspace, setActiveWorkspace] = useState<PortalWorkspace>("Evidence")

  const releasesQuery = useQuery({
    queryKey: ["releases"],
    queryFn: fetchReleases,
    refetchInterval: 15000,
  })

  const latestQuery = useQuery({
    queryKey: ["latest-release"],
    queryFn: fetchLatestRelease,
    refetchInterval: 15000,
  })

  const releases = useMemo(() => releasesQuery.data?.items ?? [], [releasesQuery.data?.items])
  const selected = releases.find((release) => release.releaseId === selectedId) ?? releases[0]
  const selectedSummary = selected?.summary
  const resourceKind = getResourceKindByTab(activeTab)

  const resourceQuery = useQuery({
    queryKey: ["release-resource", selected?.releaseId, resourceKind],
    queryFn: () => fetchReleaseResource(selected!.releaseId, resourceKind),
    enabled: Boolean(selected?.releaseId),
    staleTime: 10000,
  })

  const environmentEvidenceQuery = useQuery({
    queryKey: ["release-environment-evidence", selected?.releaseId],
    queryFn: () => fetchReleaseResource(selected!.releaseId, "evidence"),
    enabled: Boolean(selected?.releaseId),
    staleTime: 10000,
  })

  const isLoading = releasesQuery.isLoading || latestQuery.isLoading
  const hasError = releasesQuery.isError || latestQuery.isError

  function refreshAll() {
    void releasesQuery.refetch()
    void latestQuery.refetch()
    void environmentEvidenceQuery.refetch()
  }

  return (
    <main className="min-h-screen text-slate-900">
      <DashboardHeader
        hasError={hasError}
        latest={latestQuery.data}
        generatedAt={releasesQuery.data?.generatedAt}
      />

      <section className="mx-auto flex max-w-[1440px] flex-col gap-6 px-6 py-6">
        <StageBanner latest={latestQuery.data} />

        <PortalInformationArchitecture
          latest={latestQuery.data}
          releaseCount={releases.length}
          activeTab={activeTab}
          onTabChange={setActiveTab}
        />

        {isLoading ? (
          <section className="rounded-2xl border border-slate-200 bg-white p-8 text-sm text-slate-600 shadow-sm">
            正在加载 Release Portal API 数据...
          </section>
        ) : hasError ? (
          <section className="rounded-2xl border border-rose-200 bg-rose-50 p-8 text-sm text-rose-700 shadow-sm">
            Release Portal API 读取失败。请确认虚拟机 port-forward 仍在运行，并且 Vite proxy 指向 http://192.168.30.11:18090。
          </section>
        ) : !selected || !selectedSummary ? (
          <section className="rounded-2xl border border-slate-200 bg-white p-8 text-sm text-slate-600 shadow-sm">
            当前没有可展示的发布记录。
          </section>
        ) : (
          <>
            <ReleaseMetricGrid selected={selected} />

            <ControlPlaneObjectCards
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

            <ControlPlaneGraph
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

            <PortalWorkspaceTabs
              activeWorkspace={activeWorkspace}
              onWorkspaceChange={setActiveWorkspace}
            />

            {activeWorkspace === "Evidence" ? (
              <EvidenceStorePanel
                selected={selected}
                onTabChange={setActiveTab}
              />
            ) : null}

            {activeWorkspace === "Policy" ? (
              <PolicyExplanationPanel
                selected={selected}
                evidenceQuery={environmentEvidenceQuery}
                onTabChange={setActiveTab}
              />
            ) : null}

            {activeWorkspace === "Supply Chain" ? (
              <SupplyChainGatePanel
                selected={selected}
                evidenceQuery={environmentEvidenceQuery}
                onTabChange={setActiveTab}
              />
            ) : null}

            {activeWorkspace === "Agent Trace" ? (
              <AgentTracePanel
                selected={selected}
                evidenceQuery={environmentEvidenceQuery}
                onTabChange={setActiveTab}
              />
            ) : null}

            {activeWorkspace === "Approval" ? (
              <ApprovalConsolePanel
                selected={selected}
                evidenceQuery={environmentEvidenceQuery}
                onTabChange={setActiveTab}
              />
            ) : null}

            {activeWorkspace === "Environment" ? (
              <EnvironmentAwarePortalPanel
                selected={selected}
                evidenceQuery={environmentEvidenceQuery}
                onTabChange={setActiveTab}
              />
            ) : null}

            <section className="grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
              <ReleaseList
                releases={releases}
                selected={selected}
                totalCount={releasesQuery.data?.count ?? releases.length}
                onSelect={setSelectedId}
                onRefresh={refreshAll}
              />

              <section className="rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-200/60">
                <ReleaseDetailHeader
                  selected={selected}
                  tabs={tabs}
                  activeTab={activeTab}
                  onTabChange={setActiveTab}
                />

                <div className="p-6">
                  <ReleaseResourcePanel
                    activeTab={activeTab}
                    selected={selected}
                    latest={latestQuery.data}
                    resourceKind={resourceKind}
                    resourceQuery={resourceQuery}
                  />
                </div>
              </section>
            </section>
          </>
        )}
      </section>
    </main>
  )
}

export default App
