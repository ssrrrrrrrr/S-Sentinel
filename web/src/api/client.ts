import { apiUrl } from "@/config/runtimeConfig"

export async function fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(apiUrl(path), {
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

export async function fetchText(path: string, init?: RequestInit): Promise<{
  contentType: string
  body: string
}> {
  const response = await fetch(apiUrl(path), {
    ...init,
    headers: {
      Accept: "application/json, text/markdown, text/plain, */*",
      ...(init?.headers ?? {}),
    },
  })

  if (!response.ok) {
    throw new Error(`${path} returned HTTP ${response.status}`)
  }

  return {
    contentType: response.headers.get("content-type") ?? "text/plain; charset=utf-8",
    body: await response.text(),
  }
}
