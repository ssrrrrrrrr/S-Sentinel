export type EvidenceStoreJson = Record<string, unknown>

async function fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: {
      Accept: "application/json",
      ...(init?.headers ?? {}),
    },
  })

  if (!response.ok) {
    throw new Error(`${path} returned HTTP ${response.status}`)
  }

  return response.json() as Promise<T>
}

export function fetchEvidenceStoreStatus() {
  return fetchJson<EvidenceStoreJson>("/api/evidence-store/status")
}

export function fetchEvidenceStoreRefresh() {
  return fetchJson<EvidenceStoreJson>("/api/evidence-store/refresh", {
    method: "POST",
  })
}

export function fetchEvidenceStoreRelease(releaseId: string, includeRaw = true) {
  const params = new URLSearchParams()

  if (includeRaw) {
    params.set("includeRaw", "true")
  }

  const suffix = params.toString() ? `?${params.toString()}` : ""
  return fetchJson<EvidenceStoreJson>(`/api/evidence/releases/${encodeURIComponent(releaseId)}${suffix}`)
}

export function fetchEvidenceStoreSearch({
  query = "",
  objectType,
  releaseId,
  includeRaw = false,
  limit = 50,
}: {
  query?: string
  objectType?: string
  releaseId?: string
  includeRaw?: boolean
  limit?: number
}) {
  const params = new URLSearchParams()

  if (query) {
    params.set("q", query)
  }

  if (objectType) {
    params.set("objectType", objectType)
  }

  if (releaseId) {
    params.set("releaseId", releaseId)
  }

  if (includeRaw) {
    params.set("includeRaw", "true")
  }

  params.set("limit", String(limit))

  return fetchJson<EvidenceStoreJson>(`/api/evidence/search?${params.toString()}`)
}

export function fetchEvidenceStoreObject({
  objectType,
  objectId,
  releaseId,
  includeRaw = true,
}: {
  objectType: string
  objectId: string
  releaseId?: string
  includeRaw?: boolean
}) {
  const params = new URLSearchParams()

  if (releaseId) {
    params.set("releaseId", releaseId)
  }

  if (includeRaw) {
    params.set("includeRaw", "true")
  }

  const suffix = params.toString() ? `?${params.toString()}` : ""

  return fetchJson<EvidenceStoreJson>(
    `/api/evidence/objects/${encodeURIComponent(objectType)}/${encodeURIComponent(objectId)}${suffix}`,
  )
}

