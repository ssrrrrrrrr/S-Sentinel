import type { ReleaseResourceKind } from "@/api/releaseResources"
import type { PortalRoute } from "@/components/layout/portalRoutes"

export type ReleaseTabDefinition = {
  id: string
  resourceKind: ReleaseResourceKind
  targetRoute: PortalRoute | null
}

export const releaseTabs: ReleaseTabDefinition[] = [
  {
    id: "\u6982\u89c8",
    resourceKind: "summary",
    targetRoute: "Releases",
  },
  {
    id: "Evidence",
    resourceKind: "evidence",
    targetRoute: "Evidence",
  },
  {
    id: "Runtime Actions",
    resourceKind: "execution-result",
    targetRoute: "Approval",
  },
  {
    id: "GitOps",
    resourceKind: "gitops-provider-result",
    targetRoute: "Approval",
  },
  {
    id: "Advisor",
    resourceKind: "advice",
    targetRoute: "Agent Trace",
  },
  {
    id: "Docs",
    resourceKind: "runbook",
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
  Intelligence: {
    id: "Intelligence",
    resourceKind: "intelligence",
    targetRoute: "Agent Trace",
  },
  "Action Plan": {
    id: "Action Plan",
    resourceKind: "preview",
    targetRoute: "Approval",
  },
  Execution: {
    id: "Execution",
    resourceKind: "execution-result",
    targetRoute: "Approval",
  },
  "GitOps Proposal": {
    id: "GitOps Proposal",
    resourceKind: "gitops-proposal",
    targetRoute: "Approval",
  },
  "GitOps Bundle": {
    id: "GitOps Bundle",
    resourceKind: "gitops-bundle",
    targetRoute: "Approval",
  },
  "GitOps Handoff": {
    id: "GitOps Handoff",
    resourceKind: "gitops-handoff",
    targetRoute: "Approval",
  },
  "GitOps Adapter": {
    id: "GitOps Adapter",
    resourceKind: "gitops-adapter",
    targetRoute: "Approval",
  },
  "GitOps Delivery": {
    id: "GitOps Delivery",
    resourceKind: "gitops-delivery",
    targetRoute: "Approval",
  },
  "GitOps Workspace": {
    id: "GitOps Workspace",
    resourceKind: "gitops-workspace",
    targetRoute: "Approval",
  },
  "GitOps Run": {
    id: "GitOps Run",
    resourceKind: "gitops-run",
    targetRoute: "Approval",
  },
  "GitOps Pickup": {
    id: "GitOps Pickup",
    resourceKind: "gitops-pickup",
    targetRoute: "Approval",
  },
  "GitOps Pickup Ack": {
    id: "GitOps Pickup Ack",
    resourceKind: "gitops-pickup-ack",
    targetRoute: "Approval",
  },
  "GitOps Handoff State": {
    id: "GitOps Handoff State",
    resourceKind: "gitops-handoff-state",
    targetRoute: "Approval",
  },
  "GitOps Pickup Event": {
    id: "GitOps Pickup Event",
    resourceKind: "gitops-pickup-event",
    targetRoute: "Approval",
  },
  "GitOps Pickup Transition": {
    id: "GitOps Pickup Transition",
    resourceKind: "gitops-pickup-transition",
    targetRoute: "Approval",
  },
  "GitOps Handoff Prep": {
    id: "GitOps Handoff Prep",
    resourceKind: "gitops-handoff-prep",
    targetRoute: "Approval",
  },
  "GitOps Handoff Progress": {
    id: "GitOps Handoff Progress",
    resourceKind: "gitops-handoff-progress",
    targetRoute: "Approval",
  },
  "GitOps Payload": {
    id: "GitOps Payload",
    resourceKind: "gitops-payload",
    targetRoute: "Approval",
  },
  "GitOps Dispatch": {
    id: "GitOps Dispatch",
    resourceKind: "gitops-dispatch",
    targetRoute: "Approval",
  },
  "GitOps Provider Request": {
    id: "GitOps Provider Request",
    resourceKind: "gitops-provider-request",
    targetRoute: "Approval",
  },
  "GitOps Provider Result": {
    id: "GitOps Provider Result",
    resourceKind: "gitops-provider-result",
    targetRoute: "Approval",
  },
  "Advisor Trace": {
    id: "Advisor Trace",
    resourceKind: "advice",
    targetRoute: "Agent Trace",
  },
  Timeline: {
    id: "Timeline",
    resourceKind: "timeline",
    targetRoute: "Releases",
  },
  Runbook: {
    id: "Runbook",
    resourceKind: "runbook",
    targetRoute: "Releases",
  },
  RCA: {
    id: "RCA",
    resourceKind: "rca",
    targetRoute: "Releases",
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
