export type EvidenceStoreJson = Record<string, unknown>

async function fetchJson<T>(path: string): Promise<T> {
  const response = await fetch(path, {
    headers: {
      Accept: "application/json",
    },
  })

  if (!response.ok) {
    throw new Error(`${path} returned HTTP ${response.status}`)
  }

  return response.json() as Promise<T>
}

export function fetchEvidenceStoreRelease(releaseId: string, includeRaw = true) {
  const params = new URLSearchParams()

  if (includeRaw) {
    params.set("includeRaw", "true")
  }

  const suffix = params.toString() ? `?${params.toString()}` : ""
  return fetchJson<EvidenceStoreJson>(`/api/evidence-store/releases/${encodeURIComponent(releaseId)}${suffix}`)
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
    `/api/evidence-store/objects/${encodeURIComponent(objectType)}/${encodeURIComponent(objectId)}${suffix}`,
  )
}
