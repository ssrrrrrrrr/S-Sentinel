import { fetchJson } from "@/api/client"
import type { LatestReleaseResponse, ReleasesResponse } from "@/types/release"

export function fetchReleases() {
  return fetchJson<ReleasesResponse>("/api/releases")
}

export function fetchLatestRelease() {
  return fetchJson<LatestReleaseResponse>("/api/releases/latest")
}
