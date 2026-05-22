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

function App() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState("概览")

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

            <EvidenceStorePanel
              selected={selected}
              onTabChange={setActiveTab}
            />

            <PolicyExplanationPanel
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

            <SupplyChainGatePanel
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

            <AgentTracePanel
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

            <ApprovalConsolePanel
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

            <EnvironmentAwarePortalPanel
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

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
