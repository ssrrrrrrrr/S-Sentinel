import { useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { fetchLatestRelease, fetchReleases } from "@/api/releases"
import {
  fetchReleaseResource,
  getResourceKindByTab,
} from "@/api/releaseResources"
import { DashboardHeader } from "@/components/layout/DashboardHeader"
import { PortalInformationArchitecture } from "@/components/layout/PortalInformationArchitecture"
import { PortalState } from "@/components/layout/PortalState"
import { StageBanner } from "@/components/layout/StageBanner"
import { ControlPlaneObjectCards } from "@/components/release/ControlPlaneObjectCards"
import { ControlPlaneGraph } from "@/components/release/ControlPlaneGraph"
import {
  defaultPortalWorkspace,
  type PortalWorkspace,
} from "@/components/layout/portalWorkspaceConfig"
import { PortalWorkspaceRenderer } from "@/components/layout/PortalWorkspaceRenderer"
import { PortalWorkspaceTabs } from "@/components/layout/PortalWorkspaceTabs"
import { ReleaseMetricGrid } from "@/components/release/ReleaseMetricGrid"
import { ReleaseDetailWorkspace } from "@/components/release/ReleaseDetailWorkspace"

const tabs = ["概览", "Evidence", "Intelligence", "Action Plan", "AI Advice", "Timeline", "Runbook", "RCA", "Context"]

function App() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState("概览")
  const [activeWorkspace, setActiveWorkspace] = useState<PortalWorkspace>(defaultPortalWorkspace)

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
    <main className="min-h-screen bg-[#070b12] text-slate-100">
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
          <PortalState kind="loading" />
        ) : hasError ? (
          <PortalState kind="error" />
        ) : !selected || !selectedSummary ? (
          <PortalState kind="empty" />
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

            <PortalWorkspaceRenderer
              activeWorkspace={activeWorkspace}
              selected={selected}
              evidenceQuery={environmentEvidenceQuery}
              onTabChange={setActiveTab}
            />

            <ReleaseDetailWorkspace
              releases={releases}
              selected={selected}
              totalCount={releasesQuery.data?.count ?? releases.length}
              onSelect={setSelectedId}
              onRefresh={refreshAll}
              tabs={tabs}
              activeTab={activeTab}
              onTabChange={setActiveTab}
              latest={latestQuery.data}
              resourceKind={resourceKind}
              resourceQuery={resourceQuery}
            />
          </>
        )}
      </section>
    </main>
  )
}

export default App
