import type { ReleaseIndexItem } from "@/types/release"

export function normalize(value?: string) {
  return (value ?? "").toUpperCase()
}

export function statusClass(value: string) {
  const normalized = normalize(value)

  if (
    normalized === "PASS" ||
    normalized === "LOW" ||
    normalized === "ALLOW" ||
    normalized === "NOOP" ||
    normalized === "NOT REQUIRED" ||
    normalized === "ADVISORY_ONLY"
  ) {
    return "border-emerald-200 bg-emerald-50 text-emerald-700"
  }

  if (
    normalized.includes("FAIL") ||
    normalized === "HIGH" ||
    normalized === "CRITICAL" ||
    normalized === "BLOCK" ||
    normalized === "STOP_PROMOTION" ||
    normalized === "REQUIRED"
  ) {
    return "border-rose-200 bg-rose-50 text-rose-700"
  }

  return "border-amber-200 bg-amber-50 text-amber-700"
}

export function approvalText(required: boolean) {
  return required ? "需要审批" : "无需审批"
}

export function approvalRaw(required: boolean) {
  return required ? "REQUIRED" : "NOT REQUIRED"
}

export function riskText(value: string) {
  const normalized = normalize(value)
  if (normalized === "LOW") return "低风险"
  if (normalized === "MEDIUM") return "中风险"
  if (normalized === "HIGH") return "高风险"
  if (normalized === "CRITICAL") return "严重风险"
  return value || "-"
}

export function resultDisplay(value: string) {
  if (normalize(value) === "FAIL_BY_MULTIPLE_SLO") return "FAIL"
  return value || "-"
}

export function policyDisplay(value: string) {
  if (value === "ALLOW_ADVISORY_ONLY") return "ADVISORY"
  return value || "-"
}

export function actionDisplay(value: string) {
  if (value === "STOP_PROMOTION") return "STOP"
  return value || "-"
}

export function formatTime(value?: string) {
  if (!value) return "-"
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  const diffSeconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
  if (diffSeconds < 60) return `${diffSeconds} 秒前`

  const diffMinutes = Math.floor(diffSeconds / 60)
  if (diffMinutes < 60) return `${diffMinutes} 分钟前`

  const diffHours = Math.floor(diffMinutes / 60)
  if (diffHours < 24) return `${diffHours} 小时前`

  const diffDays = Math.floor(diffHours / 24)
  return `${diffDays} 天前`
}

export function resourceKeys(release?: ReleaseIndexItem) {
  return Object.keys(release?.resources ?? {})
}
