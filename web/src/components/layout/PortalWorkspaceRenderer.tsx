import type { ComponentProps } from "react"
import type { UseQueryResult } from "@tanstack/react-query"
import { AgentTracePanel } from "@/components/release/AgentTracePanel"
import { ApprovalConsolePanel } from "@/components/release/ApprovalConsolePanel"
import { EnvironmentAwarePortalPanel } from "@/components/release/EnvironmentAwarePortalPanel"
import { EvidenceStorePanel } from "@/components/release/EvidenceStorePanel"
import { PolicyExplanationPanel } from "@/components/release/PolicyExplanationPanel"
import { SupplyChainGatePanel } from "@/components/release/SupplyChainGatePanel"
import type { PortalWorkspace } from "@/components/layout/portalWorkspaceConfig"

type SelectedRelease = ComponentProps<typeof EvidenceStorePanel>["selected"]
type EvidenceQuery = ComponentProps<typeof PolicyExplanationPanel>["evidenceQuery"]

export function PortalWorkspaceRenderer({
  activeWorkspace,
  selected,
  evidenceQuery,
  onTabChange,
}: {
  activeWorkspace: PortalWorkspace
  selected: SelectedRelease
  evidenceQuery: EvidenceQuery | UseQueryResult<unknown>
  onTabChange: (tab: string) => void
}) {
  switch (activeWorkspace) {
    case "Evidence":
      return (
        <EvidenceStorePanel
          selected={selected}
          onTabChange={onTabChange}
        />
      )

    case "Policy":
      return (
        <PolicyExplanationPanel
          selected={selected}
          evidenceQuery={evidenceQuery as EvidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Supply Chain":
      return (
        <SupplyChainGatePanel
          selected={selected}
          evidenceQuery={evidenceQuery as EvidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Agent Trace":
      return (
        <AgentTracePanel
          selected={selected}
          evidenceQuery={evidenceQuery as EvidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Approval":
      return (
        <ApprovalConsolePanel
          selected={selected}
          evidenceQuery={evidenceQuery as EvidenceQuery}
          onTabChange={onTabChange}
        />
      )

    case "Environment":
      return (
        <EnvironmentAwarePortalPanel
          selected={selected}
          evidenceQuery={evidenceQuery as EvidenceQuery}
          onTabChange={onTabChange}
        />
      )

    default:
      return null
  }
}
