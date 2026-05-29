export type RuntimeConfig = {
  apiBaseUrl?: string
}

declare global {
  interface Window {
    __S_SENTINEL_CONFIG__?: RuntimeConfig
  }
}

const defaultRuntimeConfig: RuntimeConfig = {
  apiBaseUrl: "",
}

let runtimeConfig: RuntimeConfig = defaultRuntimeConfig

function normalizeBaseUrl(value: string | undefined) {
  const trimmed = value?.trim() ?? ""
  return trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed
}

export async function loadRuntimeConfig() {
  try {
    const response = await fetch("/config.json", {
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    })

    if (!response.ok) {
      runtimeConfig = defaultRuntimeConfig
      window.__S_SENTINEL_CONFIG__ = runtimeConfig
      return runtimeConfig
    }

    const config = (await response.json()) as RuntimeConfig
    runtimeConfig = {
      ...defaultRuntimeConfig,
      ...config,
      apiBaseUrl: normalizeBaseUrl(config.apiBaseUrl),
    }
  } catch {
    runtimeConfig = defaultRuntimeConfig
  }

  window.__S_SENTINEL_CONFIG__ = runtimeConfig
  return runtimeConfig
}

export function getRuntimeConfig() {
  return runtimeConfig
}

export function apiUrl(path: string) {
  const normalizedPath = path.startsWith("/") ? path : `/${path}`
  const baseUrl = normalizeBaseUrl(runtimeConfig.apiBaseUrl)

  return baseUrl ? `${baseUrl}${normalizedPath}` : normalizedPath
}
