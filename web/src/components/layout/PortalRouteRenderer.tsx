import type { UseQueryResult } from "@tanstack/react-query"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { PortalInformationArchitecture } from "@/components/layout/PortalInformationArchitecture"
import { StageBanner } from "@/components/layout/StageBanner"
import type { PortalRoute } from "@/components/layout/portalRoutes"
import { AgentTracePanel } from "@/components/release/AgentTracePanel"
import { ApprovalConsolePanel } from "@/components/release/ApprovalConsolePanel"
import { ControlPlaneGraph } from "@/components/release/ControlPlaneGraph"
import { ControlPlaneObjectCards } from "@/components/release/ControlPlaneObjectCards"
import { EnvironmentAwarePortalPanel } from "@/components/release/EnvironmentAwarePortalPanel"
import { EvidenceStorePanel } from "@/components/release/EvidenceStorePanel"
import { PolicyExplanationPanel } from "@/components/release/PolicyExplanationPanel"
import { ReleaseDetailWorkspace } from "@/components/release/ReleaseDetailWorkspace"
import { ReleaseMetricGrid } from "@/components/release/ReleaseMetricGrid"
import { SupplyChainGatePanel } from "@/components/release/SupplyChainGatePanel"
import type { LatestReleaseResponse, ReleaseIndexItem } from "@/types/release"

export function PortalRouteRenderer({
  activeRoute,
  releases,
  selected,
  totalCount,
  onSelect,
  onRefresh,
  tabs,
  activeTab,
  onTabChange,
  latest,
  resourceKind,
  resourceQuery,
  evidenceQuery,
  releaseCount,
}: {
  activeRoute: PortalRoute
  releases: ReleaseIndexItem[]
  selected: ReleaseIndexItem
  totalCount: number
  onSelect: (releaseId: string) => void
  onRefresh: () => void
  tabs: string[]
  activeTab: string
  onTabChange: (tab: string) => void
  latest?: LatestReleaseResponse
  resourceKind: string
  resourceQuery: UseQueryResult<ReleaseResourceContent, Error>
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  releaseCount: number
}) {
  switch (activeRoute) {
    case "Overview":
      return (
        <>
          <StageBanner latest={latest} />

          <PortalInformationArchitecture
            latest={latest}
            releaseCount={releaseCount}
            activeTab={activeTab}
            onTabChange={onTabChange}
          />

          <ReleaseMetricGrid selected={selected} />
        </>
      )

    case "Releases":
      return (
        <ReleaseDetailWorkspace
          releases={releases}
          selected={selected}
          totalCount={totalCount}
          onSelect={onSelect}
          onRefresh={onRefresh}
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={onTabChange}
          latest={latest}
          resourceKind={resourceKind}
          resourceQuery={resourceQuery}
        />
      )

    case "Evidence":
      return (
        <>
          <ControlPlaneObjectCards
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={onTabChange}
          />

          <ControlPlaneGraph
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={onTabChange}
          />

          <EvidenceStorePanel
            selected={selected}
            onTabChange={onTabChange}
          />
        </>
      )

    case "Policy":
      return (
        <PolicyExplanationPanel
          selected={selected}
          evidenceQuery={evidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Supply Chain":
      return (
        <SupplyChainGatePanel
          selected={selected}
          evidenceQuery={evidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Agent Trace":
      return (
        <AgentTracePanel
          selected={selected}
          evidenceQuery={evidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Approval":
      return (
        <ApprovalConsolePanel
          selected={selected}
          evidenceQuery={evidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Environment":
      return (
        <EnvironmentAwarePortalPanel
          selected={selected}
          evidenceQuery={evidenceQuery}
          onTabChange={onTabChange}
        />
      )

    default:
      return null
  }
}
