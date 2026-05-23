import { ActionButton } from "@/components/common/ActionButton"
import type { ComponentType } from "react"
import type { UseQueryResult } from "@tanstack/react-query"
import {
  AlertTriangle,
  CheckCircle2,
  Fingerprint,
  GitBranch,
  Image,
  LockKeyhole,
  PackageCheck,
  ShieldCheck,
  Tags,
} from "lucide-react"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import {
  parseJsonResource,
  stringifyValue,
} from "@/components/product-views/shared"
import type { ReleaseIndexItem } from "@/types/release"
import {
  approvalRaw,
  approvalText,
  policyDisplay,
  riskText,
} from "@/utils/format"

type SupplyChainDecisionRef = {
  supplyChainDecisionId?: string
  mode?: string
  decision?: string
  allowed?: boolean
  requiresHumanApproval?: boolean
  riskLevel?: string
  riskScore?: number
  image?: string | null
  imageTag?: string | null
  imageDigest?: string | null
  gitopsManifest?: string
  gitopsReleaseTag?: string
  blockingReasons?: string[]
  warningReasons?: string[]
  willExecute?: boolean
}

type SignedReleaseGateRef = {
  signedReleaseGateId?: string
  decision?: string
  allowed?: boolean
  reason?: string
  imageDigest?: string
  supplyChainDecisionId?: string
  policyDecisionId?: string
}

type SupplyChainEvidencePayload = {
  releaseId?: string
  service?: string
  env?: string
  version?: string
  commit?: string
  imageDigest?: string
  supplyChainDecisionId?: string
  signedReleaseGateId?: string
  policyDecision?: string
  requiresHumanApproval?: boolean
  executionMode?: string
  summary?: {
    riskLevel?: string
    riskScore?: number
  }
  artifacts?: Record<string, string>
  decisionRefs?: {
    supplyChainDecision?: SupplyChainDecisionRef
    signedReleaseGate?: SignedReleaseGateRef
  }
  release?: {
    service?: string
    env?: string
    version?: string
    commit?: string
    imageDigest?: string
  }
}

type GateMetric = {
  label: string
  value: string
  hint: string
  status: string
  icon: ComponentType<{ className?: string }>
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return stringifyValue(value)
}

function boolText(value: boolean | null | undefined) {
  if (value === true) return "true"
  if (value === false) return "false"
  return "-"
}

function shortValue(value: string, max = 54) {
  if (value.length <= max) return value
  return `${value.slice(0, 24)}…${value.slice(-20)}`
}

function statusClass(status: string) {
  const normalized = status.toLowerCase()

  if (
    normalized.includes("deny") ||
    normalized.includes("block") ||
    normalized.includes("fail") ||
    normalized.includes("required") ||
    normalized.includes("missing")
  ) {
    return "border-rose-900/45 bg-rose-950/20 text-rose-200"
  }

  if (
    normalized.includes("allow") ||
    normalized.includes("pass") ||
    normalized.includes("true") ||
    normalized.includes("linked")
  ) {
    return "border-emerald-900/45 bg-emerald-950/20 text-emerald-200"
  }

  if (normalized.includes("warn") || normalized.includes("medium")) {
    return "border-amber-900/45 bg-amber-950/20 text-amber-200"
  }

  return "border-[#35517a] bg-[#101a29] text-[#5d8fd8]"
}

function GateMetricCard({ metric }: { metric: GateMetric }) {
  const Icon = metric.icon

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-[#243044] bg-[#101a29] text-[#5d8fd8]">
            <Icon className="h-4 w-4" />
          </div>
          <div className="min-w-0">
            <p className="text-xs text-slate-500">{metric.label}</p>
            <p className="mt-1 break-all font-semibold text-slate-100">{shortValue(metric.value)}</p>
          </div>
        </div>

        <span className={`shrink-0 rounded-full border px-2.5 py-1 text-[11px] font-semibold ${statusClass(metric.status)}`}>
          {metric.status}
        </span>
      </div>

      <p className="mt-3 text-xs leading-5 text-slate-500">{metric.hint}</p>
    </div>
  )
}

function ReasonListPanel({
  title,
  items,
  empty,
  tone,
}: {
  title: string
  items: string[]
  empty: string
  tone: "danger" | "warning"
}) {
  const hasItems = items.length > 0
  const danger = tone === "danger"

  return (
    <div className={`rounded-xl border p-4 ${
      hasItems
        ? danger
          ? "border-rose-900/45 bg-rose-950/20"
          : "border-amber-900/45 bg-amber-950/20"
        : "border-emerald-900/45 bg-emerald-950/20"
    }`}>
      <h4 className={`text-sm font-semibold ${
        hasItems
          ? danger
            ? "text-rose-200"
            : "text-amber-200"
          : "text-emerald-200"
      }`}>
        {title}
      </h4>

      <div className="mt-3 space-y-2">
        {hasItems ? (
          items.map((item) => (
            <div
              key={item}
              className={`rounded-lg border bg-[#0b121d] px-3 py-2 text-sm ${
                danger
                  ? "border-rose-900/45 text-rose-200"
                  : "border-amber-900/45 text-amber-200"
              }`}
            >
              {item}
            </div>
          ))
        ) : (
          <p className="text-sm text-emerald-200">{empty}</p>
        )}
      </div>
    </div>
  )
}

export function SupplyChainGatePanel({
  selected,
  evidenceQuery,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  onTabChange: (tab: string) => void
}) {
  const evidence = evidenceQuery.data
    ? parseJsonResource<SupplyChainEvidencePayload>(evidenceQuery.data.body)
    : null

  const refs = evidence?.decisionRefs ?? {}
  const supply = refs.supplyChainDecision
  const signedGate = refs.signedReleaseGate
  const summary = selected.summary

  const service = evidence?.service ?? evidence?.release?.service ?? "-"
  const env = evidence?.env ?? evidence?.release?.env ?? "-"
  const version = evidence?.version ?? evidence?.release?.version ?? "-"
  const commit = evidence?.commit ?? evidence?.release?.commit ?? "-"
  const imageDigest =
    supply?.imageDigest ??
    signedGate?.imageDigest ??
    evidence?.imageDigest ??
    evidence?.release?.imageDigest ??
    "-"
  const supplyChainDecisionId =
    evidence?.supplyChainDecisionId ??
    supply?.supplyChainDecisionId ??
    signedGate?.supplyChainDecisionId ??
    "-"
  const signedReleaseGateId =
    evidence?.signedReleaseGateId ??
    signedGate?.signedReleaseGateId ??
    "-"
  const gateDecision =
    signedGate?.decision ??
    supply?.decision ??
    (supplyChainDecisionId !== "-" ? "linked" : "missing")
  const allowed = signedGate?.allowed ?? supply?.allowed
  const requiresHumanApproval =
    supply?.requiresHumanApproval ??
    evidence?.requiresHumanApproval ??
    summary.requiresHumanApproval
  const riskLevel = supply?.riskLevel ?? evidence?.summary?.riskLevel ?? summary.riskLevel ?? "-"
  const riskScore = supply?.riskScore ?? evidence?.summary?.riskScore ?? summary.riskScore ?? 0
  const blockingReasons = supply?.blockingReasons ?? []
  const warningReasons = supply?.warningReasons ?? []
  const policyDecision = evidence?.policyDecision ?? summary.policyDecision
  const executionMode = evidence?.executionMode ?? summary.executionMode

  const metrics: GateMetric[] = [
    {
      label: "Gate Decision",
      value: policyDisplay(gateDecision),
      hint: `signedReleaseGateId=${signedReleaseGateId}`,
      status: gateDecision,
      icon: PackageCheck,
    },
    {
      label: "Allowed",
      value: boolText(allowed),
      hint: "Signed Release Gate / Supply Chain Decision 综合允许状态",
      status: boolText(allowed),
      icon: allowed ? CheckCircle2 : AlertTriangle,
    },
    {
      label: "Risk",
      value: riskText(riskLevel),
      hint: `riskScore=${riskScore}`,
      status: riskLevel,
      icon: ShieldCheck,
    },
    {
      label: "Image Digest",
      value: imageDigest,
      hint: "不可变镜像摘要，用于防止 mutable tag 漂移。",
      status: imageDigest === "-" ? "missing" : "linked",
      icon: Fingerprint,
    },
    {
      label: "Human Gate",
      value: approvalText(Boolean(requiresHumanApproval)),
      hint: `requiresHumanApproval=${approvalRaw(Boolean(requiresHumanApproval))}`,
      status: approvalRaw(Boolean(requiresHumanApproval)),
      icon: LockKeyhole,
    },
    {
      label: "Execution Boundary",
      value: supply?.willExecute ? "willExecute=true" : "read-only",
      hint: `executionMode=${valueOrDash(executionMode)}`,
      status: supply?.willExecute ? "required" : "pass",
      icon: ShieldCheck,
    },
  ]

  return (
    <section className="rounded-2xl border border-[#1f2b3d] bg-[#0b121d] p-5 shadow-sm shadow-black/20">
      <div className="flex flex-col justify-between gap-4 border-b border-[#1f2b3d] pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Supply Chain Gate View
          </p>
          <h3 className="mt-2 flex items-center gap-2 text-lg font-semibold tracking-tight text-slate-100">
            <PackageCheck className="h-5 w-5 text-[#5d8fd8]" />
            镜像可信度与签名发布门禁
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            从 release evidence 聚合 SupplyChainDecision 和 SignedReleaseGate，
            展示镜像摘要、GitOps 发布标签、风险评分、阻断原因和只读安全边界。
          </p>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] px-4 py-3 text-sm">
          <p className="text-xs text-slate-500">Gate Source</p>
          <p className="mt-1 font-semibold text-slate-100">
            {evidenceQuery.isLoading ? "loading" : evidence ? "release evidence" : "release summary fallback"}
          </p>
          <p className="mt-1 font-mono text-xs text-slate-500">releaseId={selected.releaseId}</p>
        </div>
      </div>

      {evidenceQuery.isError ? (
        <div className="mt-4 rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-200">
          Supply Chain Gate 无法读取 release evidence，已回退到 Release summary。
        </div>
      ) : null}

      <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {metrics.map((metric) => (
          <GateMetricCard key={metric.label} metric={metric} />
        ))}
      </div>

      <section className="mt-5 grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
            <Image className="h-4 w-4 text-[#5d8fd8]" />
            Image Trust
          </div>
          <KeyValueRows
            rows={[
              ["image", valueOrDash(supply?.image)],
              ["imageTag", valueOrDash(supply?.imageTag)],
              ["imageDigest", valueOrDash(imageDigest)],
              ["supplyChainDecisionId", valueOrDash(supplyChainDecisionId)],
              ["signedReleaseGateId", valueOrDash(signedReleaseGateId)],
              ["allowed", boolText(allowed)],
            ]}
          />
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
            <GitBranch className="h-4 w-4 text-[#5d8fd8]" />
            GitOps Trust
          </div>
          <KeyValueRows
            rows={[
              ["service", service],
              ["env", env],
              ["version", version],
              ["commit", commit],
              ["gitopsManifest", valueOrDash(supply?.gitopsManifest)],
              ["gitopsReleaseTag", valueOrDash(supply?.gitopsReleaseTag)],
            ]}
          />
        </div>
      </section>

      <section className="mt-5 grid gap-4 lg:grid-cols-2">
        <ReasonListPanel
          title="Blocking Reasons"
          items={blockingReasons}
          empty="当前供应链门禁没有阻断原因。"
          tone="danger"
        />

        <ReasonListPanel
          title="Warning Reasons"
          items={warningReasons}
          empty="当前供应链门禁没有 warning reason。"
          tone="warning"
        />
      </section>

      <section className="mt-5 grid gap-4 lg:grid-cols-[0.9fr_1.1fr]">
        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
            <Tags className="h-4 w-4 text-[#5d8fd8]" />
            Gate Decision Inputs
          </div>
          <KeyValueRows
            rows={[
              ["mode", valueOrDash(supply?.mode)],
              ["decision", valueOrDash(gateDecision)],
              ["policyDecision", valueOrDash(policyDecision)],
              ["riskLevel", riskText(riskLevel)],
              ["riskScore", String(riskScore)],
              ["requiresHumanApproval", boolText(requiresHumanApproval)],
              ["willExecute", boolText(supply?.willExecute)],
            ]}
          />
        </div>

        <div className="rounded-xl border border-[#35517a] bg-[#101a29] p-4">
          <div className="flex items-center gap-2 font-semibold text-slate-100">
            <ShieldCheck className="h-4 w-4 text-[#5d8fd8]" />
            Safety Boundary
          </div>
          <p className="mt-3 text-sm leading-6 text-slate-300">
            当前视图只解释供应链门禁，不提供任何执行按钮。即使后续出现 promote、rollback、patch、
            delete 或重新签名动作，也必须先进入 Policy-bound Execution Request，再经过人工审批和审计记录。
          </p>
        </div>
      </section>

      <div className="mt-5 flex flex-wrap gap-2">
        <ActionButton onClick={() => onTabChange("Evidence")}>查看 Evidence</ActionButton>
        <ActionButton onClick={() => onTabChange("Action Plan")}>查看 Action Plan</ActionButton>
        <ActionButton onClick={() => onTabChange("Runbook")}>查看 Runbook</ActionButton>
      </div>
    </section>
  )
}






