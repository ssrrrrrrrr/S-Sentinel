export type ReleaseSummary = {
  executionMode: string
  finalAction: string
  policyDecision: string
  releaseResult: string
  requiresHumanApproval: boolean
  riskLevel: string
  riskScore: number
  safeToRetry: boolean
}

export type ReleaseResourceRef = {
  kind?: string
  name?: string
  endpoint?: string
  exists?: boolean
  file?: string
  baseName?: string
  resourceId?: string
  sizeBytes?: number
  modifiedAt?: string
  contentType?: string
  description?: string
}

export type ReleaseIndexItem = {
  releaseId: string
  generatedAt: string
  modifiedAt: string
  resourceCount: number
  summary: ReleaseSummary
  resources?: Record<string, ReleaseResourceRef>
}

export type ReleasesResponse = {
  schemaVersion: string
  generatedAt: string
  reportDir: string
  count: number
  items: ReleaseIndexItem[]
}

export type ReleasePortalSafety = {
  readOnly: boolean
  requiresHumanGate: boolean
  supportsDelete: boolean
  supportsPatch: boolean
  supportsPromote: boolean
  supportsRollback: boolean
  willExecute: boolean
}

export type LatestReleaseResponse = {
  schemaVersion: string
  generatedAt: string
  mode: string
  reportDir: string
  resources: Record<string, ReleaseResourceRef>
  endpoints: string[]
  safety: ReleasePortalSafety
}
