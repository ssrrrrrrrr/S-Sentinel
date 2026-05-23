import type { ComponentType } from "react"
import type { UseQueryResult } from "@tanstack/react-query"
import {
  AlertTriangle,
  CheckCircle2,
  FileText,
  LockKeyhole,
  Route,
  Scale,
  ShieldAlert,
  ShieldCheck,
} from "lucide-react"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import {
  parseJsonResource,
  RuleChipsPanel,
} from "@/components/product-views/shared"
import type { ReleaseIndexItem } from "@/types/release"
import {
  actionDisplay,
  approvalRaw,
  approvalText,
  policyDisplay,
  resultDisplay,
} from "@/utils/format"

type PolicyDecisionRef = {
  policyDecisionId?: string
  policyRuntimeResultId?: string
  requestedAction?: string
  allowed?: boolean
  reason?: string
  matchedRules?: string[]
  inputSummary?: {
    releaseResult?: string
    agentActionType?: string
    agentActionAllowed?: boolean
    agentActionRequiresApproval?: boolean
    autoExecute?: boolean
  }
}

type SupplyChainDecisionRef = {
  supplyChainDecisionId?: string
  decision?: string
  allowed?: boolean
  requiresHumanApproval?: boolean
  riskLevel?: string
  riskScore?: number
  blockingReasons?: string[]
  warningReasons?: string[]
  willExecute?: boolean
}

type ExecutionRequestRef = {
  executionRequestId?: string
  requestedAction?: string
  requestStatus?: string
  policyDecision?: string
  requiresHumanApproval?: boolean
  approvalStatus?: string
  approved?: boolean
  willExecute?: boolean
}

type AIDecisionRef = {
  agentAction?: {
    type?: string
    allowed?: boolean
    requiresApproval?: boolean
    reason?: string
  }
  policyHints?: string[]
  nextSteps?: string[]
}

type PolicyEvidencePayload = {
  releaseId?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  requiresHumanApproval?: boolean
  safeToRetry?: boolean
  policyDecisionId?: string
  policyRuntimeResultId?: string
  summary?: {
    matchedPolicyRules?: string[]
    failedMetrics?: unknown[]
    riskLevel?: string
    riskScore?: number
  }
  matchedPolicyRules?: string[]
  decisionRefs?: {
    policyDecision?: PolicyDecisionRef
    supplyChainDecision?: SupplyChainDecisionRef
    executionRequest?: ExecutionRequestRef
    aiDecision?: AIDecisionRef
  }
}

type DecisionMetric = {
  label: string
  value: string
  hint: string
  status: string
  icon: ComponentType<{ className?: string }>
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function boolText(value: boolean | null | undefined) {
  if (value === true) return "true"
  if (value === false) return "false"
  return "-"
}

function statusClass(status: string) {
  const normalized = status.toLowerCase()

  if (
    normalized.includes("deny") ||
    normalized.includes("block") ||
    normalized.includes("fail") ||
    normalized.includes("required")
  ) {
    return "border-rose-900/45 bg-rose-950/20 text-rose-200"
  }

  if (
    normalized.includes("allow") ||
    normalized.includes("pass") ||
    normalized.includes("true") ||
    normalized.includes("approved")
  ) {
    return "border-emerald-900/45 bg-emerald-950/20 text-emerald-200"
  }

  return "border-[#35517a] bg-[#101a29] text-[#5d8fd8]"
}

function DecisionMetricCard({ metric }: { metric: DecisionMetric }) {
  const Icon = metric.icon

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-[#243044] bg-[#101a29] text-[#5d8fd8]">
            <Icon className="h-4 w-4" />
          </div>
          <div>
            <p className="text-xs text-slate-500">{metric.label}</p>
            <p className="mt-1 font-semibold text-slate-100">{metric.value}</p>
          </div>
        </div>
        <span className={`rounded-full border px-2.5 py-1 text-[11px] font-semibold ${statusClass(metric.status)}`}>
          {metric.status}
        </span>
      </div>
      <p className="mt-3 text-xs leading-5 text-slate-500">{metric.hint}</p>
    </div>
  )
}

function ReasonPanel({
  policyReason,
  agentReason,
  blockingReasons,
  warningReasons,
}: {
  policyReason: string
  agentReason: string
  blockingReasons: string[]
  warningReasons: string[]
}) {
  const hasBlocking = blockingReasons.length > 0
  const hasWarning = warningReasons.length > 0

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#0b121d] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">Policy Explanation</h4>
        <p className="mt-1 text-xs text-slate-500">
          聚合策略原因、Advisor action reason、供应链阻断原因和 warning reason。
        </p>
      </div>

      <div className="grid gap-4 p-4 lg:grid-cols-2">
        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-400">Policy reason</p>
          <p className="mt-3 text-sm leading-6 text-slate-300">{policyReason}</p>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-400">Advisor action reason</p>
          <p className="mt-3 text-sm leading-6 text-slate-300">{agentReason}</p>
        </div>
      </div>

      <div className="grid gap-4 border-t border-[#1f2b3d] p-4 lg:grid-cols-2">
        <div className={`rounded-xl border p-4 ${
          hasBlocking ? "border-rose-900/45 bg-rose-950/20" : "border-emerald-900/45 bg-emerald-950/20"
        }`}>
          <p className={`text-sm font-semibold ${hasBlocking ? "text-rose-200" : "text-emerald-200"}`}>
            Blocking reasons
          </p>
          <div className="mt-3 space-y-2">
            {hasBlocking ? (
              blockingReasons.map((reason) => (
                <div key={reason} className="rounded-lg border border-rose-900/45 bg-[#0b121d] px-3 py-2 text-sm text-rose-200">
                  {reason}
                </div>
              ))
            ) : (
              <p className="text-sm text-emerald-200">当前没有供应链或策略阻断原因。</p>
            )}
          </div>
        </div>

        <div className={`rounded-xl border p-4 ${
          hasWarning ? "border-amber-900/45 bg-amber-950/20" : "border-emerald-900/45 bg-emerald-950/20"
        }`}>
          <p className={`text-sm font-semibold ${hasWarning ? "text-amber-200" : "text-emerald-200"}`}>
            Warning reasons
          </p>
          <div className="mt-3 space-y-2">
            {hasWarning ? (
              warningReasons.map((reason) => (
                <div key={reason} className="rounded-lg border border-amber-900/45 bg-[#0b121d] px-3 py-2 text-sm text-amber-200">
                  {reason}
                </div>
              ))
            ) : (
              <p className="text-sm text-emerald-200">当前没有 warning reason。</p>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export function PolicyExplanationPanel({
  selected,
  evidenceQuery,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  onTabChange: (tab: string) => void
}) {
  const evidence = evidenceQuery.data
    ? parseJsonResource<PolicyEvidencePayload>(evidenceQuery.data.body)
    : null

  const summary = selected.summary
  const refs = evidence?.decisionRefs ?? {}
  const policyDecisionRef = refs.policyDecision
  const supplyChainDecision = refs.supplyChainDecision
  const executionRequest = refs.executionRequest
  const aiDecision = refs.aiDecision
  const inputSummary = policyDecisionRef?.inputSummary

  const releaseResult = evidence?.releaseResult ?? summary.releaseResult
  const policyDecision = evidence?.policyDecision ?? summary.policyDecision
  const finalAction = evidence?.finalAction ?? summary.finalAction
  const executionMode = evidence?.executionMode ?? summary.executionMode
  const requiresHumanApproval =
    evidence?.requiresHumanApproval ??
    executionRequest?.requiresHumanApproval ??
    summary.requiresHumanApproval
  const safeToRetry = evidence?.safeToRetry ?? summary.safeToRetry
  const allowed = policyDecisionRef?.allowed ?? supplyChainDecision?.allowed ?? inputSummary?.agentActionAllowed
  const requestedAction = policyDecisionRef?.requestedAction ?? executionRequest?.requestedAction ?? finalAction
  const policyDecisionId = evidence?.policyDecisionId ?? policyDecisionRef?.policyDecisionId ?? "-"
  const policyRuntimeResultId = evidence?.policyRuntimeResultId ?? policyDecisionRef?.policyRuntimeResultId ?? "-"
  const matchedRules =
    policyDecisionRef?.matchedRules ??
    evidence?.summary?.matchedPolicyRules ??
    evidence?.matchedPolicyRules ??
    []
  const policyReason = policyDecisionRef?.reason ?? "当前 evidence 中没有提供明确的 policy reason。"
  const agentReason = aiDecision?.agentAction?.reason ?? "当前 evidence 中没有提供 Advisor action reason。"
  const blockingReasons = supplyChainDecision?.blockingReasons ?? []
  const warningReasons = supplyChainDecision?.warningReasons ?? []
  const failedMetricCount = evidence?.summary?.failedMetrics?.length ?? 0

  const metrics: DecisionMetric[] = [
    {
      label: "Policy Decision",
      value: policyDisplay(policyDecision),
      hint: `policyDecisionId=${policyDecisionId}`,
      status: policyDecision,
      icon: Scale,
    },
    {
      label: "Requested Action",
      value: actionDisplay(requestedAction),
      hint: `finalAction=${finalAction}`,
      status: requestedAction,
      icon: Route,
    },
    {
      label: "Allowed",
      value: boolText(allowed),
      hint: "Policy / Supply Chain / Agent action 综合允许状态",
      status: boolText(allowed),
      icon: allowed ? CheckCircle2 : ShieldAlert,
    },
    {
      label: "Human Approval",
      value: approvalText(Boolean(requiresHumanApproval)),
      hint: `requiresHumanApproval=${approvalRaw(Boolean(requiresHumanApproval))}`,
      status: approvalRaw(Boolean(requiresHumanApproval)),
      icon: LockKeyhole,
    },
    {
      label: "Safe To Retry",
      value: boolText(safeToRetry),
      hint: "用于判断是否可以安全重试发布流程",
      status: boolText(safeToRetry),
      icon: safeToRetry ? CheckCircle2 : AlertTriangle,
    },
    {
      label: "SLO Failures",
      value: String(failedMetricCount),
      hint: `releaseResult=${resultDisplay(releaseResult)}`,
      status: failedMetricCount > 0 ? "REQUIRED" : "PASS",
      icon: FileText,
    },
  ]

  return (
    <section className="rounded-2xl border border-[#1f2b3d] bg-[#0b121d] p-5 shadow-sm shadow-black/20">
      <div className="flex flex-col justify-between gap-4 border-b border-[#1f2b3d] pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Policy Explanation View
          </p>
          <h3 className="mt-2 flex items-center gap-2 text-lg font-semibold tracking-tight text-slate-100">
            <ShieldCheck className="h-5 w-5 text-[#5d8fd8]" />
            策略裁决解释与安全边界
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            直接从 release evidence 聚合 Policy Guard、AI action、Supply Chain 和 Execution Request 字段，
            解释本次发布为什么允许、阻断、需要人工审批或保持只读。
          </p>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] px-4 py-3 text-sm">
          <p className="text-xs text-slate-500">Policy Source</p>
          <p className="mt-1 font-semibold text-slate-100">
            {evidenceQuery.isLoading ? "loading" : evidence ? "release evidence" : "release summary fallback"}
          </p>
          <p className="mt-1 font-mono text-xs text-slate-500">releaseId={selected.releaseId}</p>
        </div>
      </div>

      {evidenceQuery.isError ? (
        <div className="mt-4 rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-200">
          Policy Explanation 无法读取 release evidence，已回退到 Release summary。
        </div>
      ) : null}

      <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {metrics.map((metric) => (
          <DecisionMetricCard key={metric.label} metric={metric} />
        ))}
      </div>

      <section className="mt-5 grid gap-4 lg:grid-cols-[0.95fr_1.05fr]">
        <div className="space-y-4">
          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
            <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
              <Scale className="h-4 w-4 text-[#5d8fd8]" />
              Decision Inputs
            </div>
            <KeyValueRows
              rows={[
                ["policyDecisionId", policyDecisionId],
                ["policyRuntimeResultId", policyRuntimeResultId],
                ["releaseResult", releaseResult],
                ["executionMode", executionMode],
                ["requestedAction", requestedAction],
                ["requestStatus", valueOrDash(executionRequest?.requestStatus)],
                ["approvalStatus", valueOrDash(executionRequest?.approvalStatus)],
                ["approved", boolText(executionRequest?.approved)],
                ["willExecute", boolText(executionRequest?.willExecute ?? supplyChainDecision?.willExecute)],
              ]}
            />
          </div>

          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
            <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
              <ShieldCheck className="h-4 w-4 text-[#5d8fd8]" />
              Matched Policy Rules
            </div>
            <RuleChipsPanel rules={matchedRules} />
          </div>
        </div>

        <ReasonPanel
          policyReason={policyReason}
          agentReason={agentReason}
          blockingReasons={blockingReasons}
          warningReasons={warningReasons}
        />
      </section>

      <div className="mt-5 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => onTabChange("Evidence")}
          className="rounded-xl border border-[#243044] bg-[#0b121d] px-4 py-2 text-sm font-semibold text-slate-300 transition hover:border-[#35517a] hover:bg-[#101a29] hover:text-slate-100"
        >
          查看 Evidence
        </button>
        <button
          type="button"
          onClick={() => onTabChange("Action Plan")}
          className="rounded-xl border border-[#243044] bg-[#0b121d] px-4 py-2 text-sm font-semibold text-slate-300 transition hover:border-[#35517a] hover:bg-[#101a29] hover:text-slate-100"
        >
          查看 Action Plan
        </button>
        <button
          type="button"
          onClick={() => onTabChange("Runbook")}
          className="rounded-xl border border-[#243044] bg-[#0b121d] px-4 py-2 text-sm font-semibold text-slate-300 transition hover:border-[#35517a] hover:bg-[#101a29] hover:text-slate-100"
        >
          查看 Runbook
        </button>
      </div>
    </section>
  )
}


