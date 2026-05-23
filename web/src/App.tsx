import { useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { fetchLatestRelease, fetchReleases } from "@/api/releases"
import {
  fetchReleaseResource,
  getResourceKindByTab,
} from "@/api/releaseResources"
import { LayoutShell } from "@/components/layout/LayoutShell"
import { PortalRouteRenderer } from "@/components/layout/PortalRouteRenderer"
import { PortalState } from "@/components/layout/PortalState"
import {
  defaultPortalRoute,
  type PortalRoute,
} from "@/components/layout/portalRoutes"
import type { ReleaseContext } from "@/components/layout/ReleaseContextBar"

const tabs = ["概览", "Evidence", "Intelligence", "Action Plan", "AI Advice", "Timeline", "Runbook", "RCA", "Context"]

function displayValue(value: unknown, fallback = "unknown") {
  if (typeof value === "string" && value.trim().length > 0) {
    return value
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value)
  }

  return fallback
}

function App() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState("概览")
  const [activeRoute, setActiveRoute] = useState<PortalRoute>(defaultPortalRoute)

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

  const releaseContext = useMemo<ReleaseContext>(() => {
    const release = selected as Record<string, unknown> | undefined
    const summary = selectedSummary as Record<string, unknown> | undefined

    return {
      service: displayValue(summary?.service ?? release?.service, "demo-app"),
      environment: displayValue(summary?.environment ?? summary?.env ?? release?.environment ?? release?.env, "unknown"),
      releaseId: displayValue(selected?.releaseId ?? release?.releaseId, "no release"),
      version: displayValue(summary?.version ?? summary?.targetVersion ?? release?.version, "unknown"),
      result: displayValue(summary?.releaseResult ?? summary?.result ?? release?.result, "unknown"),
      imageDigest: displayValue(summary?.imageDigest ?? release?.imageDigest ?? release?.digest, "not reported"),
    }
  }, [selected, selectedSummary])

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
    <LayoutShell
      hasError={hasError}
      latest={latestQuery.data}
      generatedAt={releasesQuery.data?.generatedAt}
      activeRoute={activeRoute}
      onRouteChange={setActiveRoute}
      releaseContext={releaseContext}
      onRefresh={refreshAll}
    >
      {isLoading ? (
        <PortalState kind="loading" />
      ) : hasError ? (
        <PortalState kind="error" />
      ) : !selected || !selectedSummary ? (
        <PortalState kind="empty" />
      ) : (
        <PortalRouteRenderer
          activeRoute={activeRoute}
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
          evidenceQuery={environmentEvidenceQuery}
          releaseCount={releases.length}
        />
      )}
    </LayoutShell>
  )
}

export default App
