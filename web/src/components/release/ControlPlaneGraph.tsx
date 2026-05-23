import type { ComponentType } from "react"
import type { UseQueryResult } from "@tanstack/react-query"
import {
  Activity,
  ClipboardCheck,
  FileCheck2,
  GitBranch,
  Network,
  PackageCheck,
  ShieldCheck,
} from "lucide-react"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { parseJsonResource } from "@/components/product-views/shared"
import type { ReleaseIndexItem } from "@/types/release"

type EvidenceDecisionRefs = {
  policyDecision?: {
    policyDecisionId?: string
    allowed?: boolean
    reason?: string
    matchedRules?: string[]
  }
  supplyChainDecision?: {
    supplyChainDecisionId?: string
    decision?: string
    allowed?: boolean
    riskLevel?: string
    riskScore?: number
    imageDigest?: string | null
  }
  signedReleaseGate?: {
    signedReleaseGateId?: string
    decision?: string
    allowed?: boolean
  }
  agentRun?: {
    agentRunId?: string
    recommendedAction?: string
    priority?: string
    willExecute?: boolean
  }
  planRun?: {
    planRunId?: string
    planType?: string
    retrievedEvidenceCount?: number
    willExecute?: boolean
  }
  executionRequest?: {
    executionRequestId?: string
    requestedAction?: string
    requestStatus?: string
    approvalStatus?: string
    approved?: boolean
    willExecute?: boolean
  }
  agentTrace?: {
    agentTraceId?: string
    traceId?: string
  }
}

type GraphEvidencePayload = {
  releaseId?: string
  service?: string
  env?: string
  version?: string
  commit?: string
  imageDigest?: string
  sloId?: string
  policyDecisionId?: string
  policyRuntimeResultId?: string
  supplyChainDecisionId?: string
  signedReleaseGateId?: string
  agentRunId?: string
  planRunId?: string
  executionRequestId?: string
  agentTraceId?: string
  traceId?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  release?: {
    service?: string
    env?: string
    version?: string
    commit?: string
    imageDigest?: string
  }
  summary?: {
    failedMetrics?: unknown[]
    matchedPolicyRules?: string[]
  }
  artifacts?: Record<string, string>
  decisionRefs?: EvidenceDecisionRefs
}

type GraphNode = {
  id: string
  title: string
  subtitle: string
  value: string
  status: string
  tab: string
  icon: ComponentType<{ className?: string }>
  fields: Array<[string, string]>
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function shortValue(value: string) {
  if (value.length <= 22) return value
  return `${value.slice(0, 10)}…${value.slice(-8)}`
}

function statusClass(status: string) {
  const normalized = status.toLowerCase()

  if (normalized.includes("fail") || normalized.includes("deny") || normalized.includes("block")) {
    return "border-rose-900/45 bg-rose-950/25 text-rose-200"
  }

  if (normalized.includes("missing") || normalized === "-") {
    return "border-amber-900/45 bg-amber-950/25 text-amber-200"
  }

  if (normalized.includes("pass") || normalized.includes("allow") || normalized.includes("linked")) {
    return "border-emerald-900/45 bg-emerald-950/25 text-emerald-200"
  }

  return "border-[#243044] bg-[#0b121d] text-slate-300"
}

function GraphNodeCard({
  node,
  onTabChange,
}: {
  node: GraphNode
  onTabChange: (tab: string) => void
}) {
  const Icon = node.icon

  return (
    <div className="min-w-0 rounded-2xl border border-[#1f2b3d] bg-[#0f1724] p-4 shadow-sm shadow-black/20">
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[#243044] bg-[#0b121d] text-[#5d8fd8]">
            <Icon className="h-5 w-5" />
          </div>
          <div className="min-w-0">
            <h4 className="truncate font-semibold text-slate-100">{node.title}</h4>
            <p className="mt-1 text-xs text-slate-500">{node.subtitle}</p>
          </div>
        </div>

        <span className={`shrink-0 rounded-full border px-2.5 py-1 text-[11px] font-semibold ${statusClass(node.status)}`}>
          {node.status}
        </span>
      </div>

      <div className="mt-4 rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
        <p className="text-xs text-slate-500">Primary Object</p>
        <p className="mt-1 break-all font-mono text-sm font-semibold text-slate-100" title={node.value}>
          {shortValue(node.value)}
        </p>
      </div>

      <div className="mt-3 grid gap-2">
        {node.fields.map(([key, value]) => (
          <div key={`${node.id}-${key}`} className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 text-xs">
            <span className="text-slate-500">{key}</span>
            <span className="min-w-0 break-all text-right font-mono font-semibold text-slate-300">
              {shortValue(value)}
            </span>
          </div>
        ))}
      </div>

      <button
        type="button"
        onClick={() => onTabChange(node.tab)}
        className="mt-4 w-full rounded-xl border border-[#243044] bg-[#0b121d] px-3 py-2 text-sm font-semibold text-slate-300 transition hover:border-[#35517a] hover:bg-[#101a29] hover:text-slate-100"
      >
        查看 {node.tab}
      </button>
    </div>
  )
}

export function ControlPlaneGraph({
  selected,
  evidenceQuery,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  onTabChange: (tab: string) => void
}) {
  const evidence = evidenceQuery.data
    ? parseJsonResource<GraphEvidencePayload>(evidenceQuery.data.body)
    : null

  const refs = evidence?.decisionRefs ?? {}
  const failedMetricCount = evidence?.summary?.failedMetrics?.length ?? 0
  const matchedRuleCount = evidence?.summary?.matchedPolicyRules?.length ?? 0

  const releaseId = evidence?.releaseId ?? selected.releaseId
  const service = evidence?.service ?? evidence?.release?.service ?? "-"
  const env = evidence?.env ?? evidence?.release?.env ?? "-"
  const version = evidence?.version ?? evidence?.release?.version ?? "-"
  const commit = evidence?.commit ?? evidence?.release?.commit ?? "-"

  const policyDecisionId = evidence?.policyDecisionId ?? refs.policyDecision?.policyDecisionId ?? "-"
  const supplyChainDecisionId = evidence?.supplyChainDecisionId ?? refs.supplyChainDecision?.supplyChainDecisionId ?? "-"
  const signedReleaseGateId = evidence?.signedReleaseGateId ?? refs.signedReleaseGate?.signedReleaseGateId ?? "-"
  const imageDigest = evidence?.imageDigest ?? evidence?.release?.imageDigest ?? refs.supplyChainDecision?.imageDigest ?? "-"
  const agentRunId = evidence?.agentRunId ?? refs.agentRun?.agentRunId ?? "-"
  const planRunId = evidence?.planRunId ?? refs.planRun?.planRunId ?? "-"
  const executionRequestId = evidence?.executionRequestId ?? refs.executionRequest?.executionRequestId ?? "-"
  const agentTraceId = evidence?.agentTraceId ?? refs.agentTrace?.agentTraceId ?? "-"
  const traceId = evidence?.traceId ?? refs.agentTrace?.traceId ?? "-"

  const nodes: GraphNode[] = [
    {
      id: "release",
      title: "Release",
      subtitle: "发布入口对象",
      value: releaseId,
      status: "linked",
      tab: "概览",
      icon: GitBranch,
      fields: [
        ["service", service],
        ["env", env],
        ["version", version],
        ["commit", commit],
      ],
    },
    {
      id: "evidence",
      title: "SLO Evidence",
      subtitle: "SLO 结果和证据包",
      value: evidence?.sloId ?? releaseId,
      status: evidence?.releaseResult ?? selected.summary.releaseResult,
      tab: "Evidence",
      icon: FileCheck2,
      fields: [
        ["releaseResult", valueOrDash(evidence?.releaseResult ?? selected.summary.releaseResult)],
        ["failedMetrics", String(failedMetricCount)],
        ["evidence", evidence ? "parsed" : "fallback"],
      ],
    },
    {
      id: "policy",
      title: "Policy Guard",
      subtitle: "策略裁决对象",
      value: policyDecisionId,
      status: evidence?.policyDecision ?? selected.summary.policyDecision,
      tab: "Evidence",
      icon: ShieldCheck,
      fields: [
        ["policyDecisionId", policyDecisionId],
        ["allowed", valueOrDash(refs.policyDecision?.allowed)],
        ["matchedRules", String(matchedRuleCount)],
      ],
    },
    {
      id: "supply-chain",
      title: "Supply Chain Gate",
      subtitle: "镜像与发布门禁",
      value: signedReleaseGateId !== "-" ? signedReleaseGateId : supplyChainDecisionId,
      status: refs.signedReleaseGate?.decision ?? refs.supplyChainDecision?.decision ?? "linked",
      tab: "Evidence",
      icon: PackageCheck,
      fields: [
        ["supplyChainDecisionId", supplyChainDecisionId],
        ["signedReleaseGateId", signedReleaseGateId],
        ["imageDigest", valueOrDash(imageDigest)],
      ],
    },
    {
      id: "agent",
      title: "Advisor Trace",
      subtitle: "AdvisorRun / PlanRun / Trace",
      value: agentTraceId !== "-" ? agentTraceId : agentRunId,
      status: refs.agentRun?.priority ?? selected.summary.riskLevel,
      tab: "Advisor Trace",
      icon: Activity,
      fields: [
        ["agentRunId", agentRunId],
        ["planRunId", planRunId],
        ["traceId", traceId],
      ],
    },
    {
      id: "execution",
      title: "Execution Request",
      subtitle: "策略约束下的动作申请",
      value: executionRequestId,
      status: refs.executionRequest?.requestStatus ?? (selected.summary.requiresHumanApproval ? "approval-required" : "read-only"),
      tab: "Action Plan",
      icon: ClipboardCheck,
      fields: [
        ["requestedAction", valueOrDash(refs.executionRequest?.requestedAction ?? selected.summary.finalAction)],
        ["approvalStatus", valueOrDash(refs.executionRequest?.approvalStatus)],
        ["willExecute", valueOrDash(refs.executionRequest?.willExecute)],
      ],
    },
  ]

  return (
    <section className="rounded-2xl border border-[#1f2b3d] bg-[#0f1724] p-5 shadow-sm shadow-black/20">
      <div className="flex flex-col justify-between gap-3 border-b border-[#1a2535] pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Release / Evidence Graph
          </p>
          <h3 className="mt-2 flex items-center gap-2 text-lg font-semibold tracking-tight text-slate-100">
            <Network className="h-5 w-5 text-[#5d8fd8]" />
            一次发布的控制平面对象链路
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            基于当前 release evidence 构建只读图谱，把 Release、SLO Evidence、Policy Guard、Supply Chain Gate、
            Advisor 和 Execution Request 串成可观察、可审计的发布链路。
          </p>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] px-4 py-3 text-sm">
          <p className="text-xs text-slate-500">Graph Source</p>
          <p className="mt-1 font-semibold text-slate-100">
            {evidenceQuery.isLoading ? "loading" : evidence ? "release evidence" : "release index fallback"}
          </p>
          <p className="mt-1 font-mono text-xs text-slate-500">releaseId={selected.releaseId}</p>
        </div>
      </div>

      {evidenceQuery.isError ? (
        <div className="mt-4 rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-200">
          Evidence Graph 无法读取 release evidence，已回退到 Release index 摘要。
        </div>
      ) : null}

      <div className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {nodes.map((node) => (
          <div key={node.id} className="min-w-0">
            <GraphNodeCard node={node} onTabChange={onTabChange} />
          </div>
        ))}
      </div>

      <div className="mt-5 rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-400">
          Observability Contract
        </p>
        <div className="mt-3 flex flex-wrap gap-2">
          {[
            "releaseId",
            "service",
            "env",
            "version",
            "commit",
            "imageDigest",
            "sloId",
            "policyDecisionId",
            "signedReleaseGateId",
            "agentRunId",
            "agentTraceId",
            "traceId",
          ].map((field) => (
            <span
              key={field}
              className="rounded-full border border-[#1f2b3d] bg-[#070b12] px-2.5 py-1 font-mono text-[11px] font-semibold text-slate-400"
            >
              {field}
            </span>
          ))}
        </div>
      </div>
    </section>
  )
}



