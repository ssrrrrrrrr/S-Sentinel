import { fetchText } from "@/api/client"
import { getReleaseResourceKindByTab } from "@/config/releaseTabs"

export type ReleaseResourceKind =
  | "summary"
  | "evidence"
  | "action-plan"
  | "preview"
  | "execution-result"
  | "gitops-proposal"
  | "gitops-bundle"
  | "gitops-handoff"
  | "gitops-adapter"
  | "gitops-delivery"
  | "gitops-workspace"
  | "gitops-run"
  | "gitops-pickup"
  | "gitops-pickup-ack"
  | "gitops-handoff-state"
  | "gitops-pickup-event"
  | "gitops-pickup-transition"
  | "gitops-handoff-prep"
  | "gitops-handoff-progress"
  | "gitops-payload"
  | "gitops-dispatch"
  | "gitops-provider-request"
  | "gitops-provider-result"
  | "intelligence"
  | "advice"
  | "context"
  | "ai-decision"
  | "policy-decision"
  | "runbook"
  | "rca"
  | "timeline"

export type ReleaseResourceContent = {
  releaseId: string
  kind: ReleaseResourceKind
  contentType: string
  body: string
}

export function getResourceKindByTab(tab: string): ReleaseResourceKind {
  return getReleaseResourceKindByTab(tab)
}

export function isMarkdownContent(contentType: string) {
  return contentType.toLowerCase().includes("markdown") || contentType.toLowerCase().includes("text/plain")
}

export function formatResourceBody(contentType: string, body: string) {
  if (isMarkdownContent(contentType)) {
    return body
  }

  try {
    return JSON.stringify(JSON.parse(body), null, 2)
  } catch {
    return body
  }
}

export async function fetchReleaseResource(
  releaseId: string,
  kind: ReleaseResourceKind,
): Promise<ReleaseResourceContent> {
  const path = `/api/releases/${releaseId}/${kind}`
  const { contentType, body } = await fetchText(path)

  return {
    releaseId,
    kind,
    contentType,
    body,
  }
}
