import type { ReleaseResourceKind } from "@/api/releaseResources"
import type { PortalRoute } from "@/components/layout/portalRoutes"

export type ReleaseTabDefinition = {
  id: string
  resourceKind: ReleaseResourceKind
  targetRoute: PortalRoute | null
}

export const releaseTabs: ReleaseTabDefinition[] = [
  {
    id: "概览",
    resourceKind: "summary",
    targetRoute: "Releases",
  },
  {
    id: "Evidence",
    resourceKind: "evidence",
    targetRoute: "Evidence",
  },
  {
    id: "Intelligence",
    resourceKind: "intelligence",
    targetRoute: "Agent Trace",
  },
  {
    id: "Action Plan",
    resourceKind: "preview",
    targetRoute: "Approval",
  },
  {
    id: "Execution",
    resourceKind: "execution-result",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Proposal",
    resourceKind: "gitops-proposal",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Bundle",
    resourceKind: "gitops-bundle",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Handoff",
    resourceKind: "gitops-handoff",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Adapter",
    resourceKind: "gitops-adapter",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Delivery",
    resourceKind: "gitops-delivery",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Workspace",
    resourceKind: "gitops-workspace",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Run",
    resourceKind: "gitops-run",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Pickup",
    resourceKind: "gitops-pickup",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Pickup Ack",
    resourceKind: "gitops-pickup-ack",
    targetRoute: "Approval",
  },
  {
    id: "GitOps Handoff State",
    resourceKind: "gitops-handoff-state",
    targetRoute: "Approval",
  },
  {
    id: "Advisor Trace",
    resourceKind: "advice",
    targetRoute: "Agent Trace",
  },
  {
    id: "Timeline",
    resourceKind: "timeline",
    targetRoute: "Releases",
  },
  {
    id: "Runbook",
    resourceKind: "runbook",
    targetRoute: "Releases",
  },
  {
    id: "RCA",
    resourceKind: "rca",
    targetRoute: "Releases",
  },
  {
    id: "Context",
    resourceKind: "context",
    targetRoute: "Environment",
  },
]

const legacyReleaseTabAliases: Record<string, ReleaseTabDefinition> = {
  "AI Advice": {
    id: "AI Advice",
    resourceKind: "advice",
    targetRoute: "Agent Trace",
  },
}

export const releaseTabIds = releaseTabs.map((tab) => tab.id)

export function getReleaseTab(tabId: string): ReleaseTabDefinition | undefined {
  return releaseTabs.find((tab) => tab.id === tabId) ?? legacyReleaseTabAliases[tabId]
}

export function getReleaseResourceKindByTab(tabId: string): ReleaseResourceKind {
  return getReleaseTab(tabId)?.resourceKind ?? "summary"
}

export function getPortalRouteByReleaseTab(tabId: string): PortalRoute | null {
  return getReleaseTab(tabId)?.targetRoute ?? null
}
