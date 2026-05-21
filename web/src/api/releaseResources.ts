export type ReleaseResourceKind =
  | "summary"
  | "evidence"
  | "action-plan"
  | "intelligence"
  | "advice"
  | "context"
  | "ai-decision"
  | "policy-decision"
  | "runbook"
  | "rca"

export type ReleaseResourceContent = {
  releaseId: string
  kind: ReleaseResourceKind
  contentType: string
  body: string
}

const resourcePathByTab: Record<string, ReleaseResourceKind> = {
  "概览": "summary",
  Timeline: "summary",
  Evidence: "evidence",
  "Action Plan": "action-plan",
  Intelligence: "intelligence",
  Runbook: "runbook",
  RCA: "rca",
  "AI Advice": "advice",
  Context: "context",
}

export function getResourceKindByTab(tab: string): ReleaseResourceKind {
  return resourcePathByTab[tab] ?? "summary"
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
