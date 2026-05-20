export function parseJsonResource<T>(body: string): T | null {
  try {
    return JSON.parse(body) as T
  } catch {
    return null
  }
}

export function stringifyValue(value: unknown) {
  if (value === null || value === undefined) return "-"
  if (typeof value === "string") return value
  if (typeof value === "number" || typeof value === "boolean") return String(value)

  try {
    return JSON.stringify(value, null, 2)
  } catch {
    return String(value)
  }
}

export function RuleChipsPanel({ rules }: { rules?: string[] }) {
  const items = rules ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Evidence 没有命中的策略规则。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4">
      <h4 className="text-sm font-semibold text-slate-900">命中的策略规则</h4>
      <div className="mt-3 flex flex-wrap gap-2">
        {items.map((rule) => (
          <span
            key={rule}
            className="rounded-full border border-cyan-200 bg-cyan-50 px-3 py-1 font-mono text-xs font-semibold text-cyan-800"
          >
            {rule}
          </span>
        ))}
      </div>
    </div>
  )
}

export function FailedMetricsPanel({ metrics }: { metrics?: unknown[] }) {
  const items = metrics ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">
        没有失败的 SLO 指标，当前发布通过门禁。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-rose-200 bg-rose-50">
      <div className="border-b border-rose-200 px-4 py-3">
        <h4 className="text-sm font-semibold text-rose-900">失败的 SLO 指标</h4>
      </div>
      <div className="divide-y divide-rose-200">
        {items.map((metric, index) => (
          <pre
            key={index}
            className="overflow-auto whitespace-pre-wrap px-4 py-3 text-xs leading-6 text-rose-900"
          >
            {stringifyValue(metric)}
          </pre>
        ))}
      </div>
    </div>
  )
}

export type JsonRecord = Record<string, unknown>

export function asRecord(value: unknown): JsonRecord | null {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return value as JsonRecord
  }

  return null
}

export function valueFromPath(root: unknown, path: string[]) {
  let current: unknown = root

  for (const key of path) {
    const record = asRecord(current)
    if (!record || !(key in record)) return undefined
    current = record[key]
  }

  return current
}

export function valueFromPaths(root: unknown, paths: string[][]) {
  for (const path of paths) {
    const value = valueFromPath(root, path)
    if (value !== undefined && value !== null) return value
  }

  return undefined
}

export function stringFromPaths(root: unknown, paths: string[][], fallback = "-") {
  const value = valueFromPaths(root, paths)

  if (value === undefined || value === null || value === "") return fallback
  if (typeof value === "string") return value
  if (typeof value === "number" || typeof value === "boolean") return String(value)

  return stringifyValue(value)
}

export function numberFromPaths(root: unknown, paths: string[][], fallback = 0) {
  const value = valueFromPaths(root, paths)

  if (typeof value === "number") return value
  if (typeof value === "string") {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : fallback
  }

  return fallback
}

export function booleanFromPaths(root: unknown, paths: string[][]) {
  const value = valueFromPaths(root, paths)

  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    if (value.toLowerCase() === "true") return true
    if (value.toLowerCase() === "false") return false
  }

  return null
}

export function arrayFromPaths(root: unknown, paths: string[][]) {
  const value = valueFromPaths(root, paths)
  return Array.isArray(value) ? value : []
}

export function markdownValue(body: string, label: string) {
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  const patterns = [
    new RegExp(`^-\\s*${escaped}:\\s*\`?([^\\r\\n\`]+)\`?`, "im"),
    new RegExp(`^${escaped}:\\s*\`?([^\\r\\n\`]+)\`?`, "im"),
  ]

  for (const pattern of patterns) {
    const match = body.match(pattern)
    if (match?.[1]) return match[1].trim()
  }

  return "-"
}

export function markdownBooleanValue(body: string, label: string) {
  const value = markdownValue(body, label).toLowerCase()

  if (value === "true") return true
  if (value === "false") return false

  return null
}

export function markdownNumberValue(body: string, label: string) {
  const value = markdownValue(body, label)
  const parsed = Number(value)

  return Number.isFinite(parsed) ? parsed : 0
}

export function markdownListAfterHeading(body: string, heading: string) {
  const lines = body.split(/\r?\n/)
  const headingIndex = lines.findIndex((line) => line.trim().toLowerCase() === heading.toLowerCase())

  if (headingIndex < 0) return []

  const items: string[] = []

  for (const line of lines.slice(headingIndex + 1)) {
    const trimmed = line.trim()

    if (trimmed.startsWith("#")) break
    if (!trimmed) {
      if (items.length > 0) break
      continue
    }

    if (trimmed.startsWith("- ")) {
      items.push(trimmed.slice(2).replace(/`/g, "").trim())
    }
  }

  return items
}

export function markdownContainsAny(body: string, keywords: string[]) {
  const lower = body.toLowerCase()
  return keywords.some((keyword) => lower.includes(keyword.toLowerCase()))
}


