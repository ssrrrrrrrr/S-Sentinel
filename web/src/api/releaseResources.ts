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
  const response = await fetch(`/api/releases/${releaseId}/${kind}`, {
    headers: {
      Accept: "application/json, text/markdown, text/plain, */*",
    },
  })

  if (!response.ok) {
    throw new Error(`/api/releases/${releaseId}/${kind} returned HTTP ${response.status}`)
  }

  const contentType = response.headers.get("content-type") ?? "text/plain; charset=utf-8"
  const body = await response.text()

  return {
    releaseId,
    kind,
    contentType,
    body,
  }
}
