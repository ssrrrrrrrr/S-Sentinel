import type { LatestReleaseResponse, ReleasesResponse } from "@/types/release"

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

export function fetchReleases() {
  return fetchJson<ReleasesResponse>("/api/releases")
}

export function fetchLatestRelease() {
  return fetchJson<LatestReleaseResponse>("/api/releases/latest")
}
