import type { UseQueryResult } from "@tanstack/react-query"
import {
  Bot,
  Boxes,
  ClipboardCheck,
  FileCheck2,
  GitBranch,
  ShieldCheck,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { parseJsonResource } from "@/components/product-views/shared"
import type { ReleaseIndexItem, ReleaseResourceRef } from "@/types/release"
import {
  actionDisplay,
  policyDisplay,
  resultDisplay,
  riskText,
} from "@/utils/format"

type EvidenceDecisionRefs = {
  aiDecision?: {
    decisionSource?: string
    confidence?: string
    agentAction?: {
      type?: string
      allowed?: boolean
      requiresApproval?: boolean
      reason?: string
    }
  }
  policyDecision?: {
    policyDecisionId?: string
    requestedAction?: string
    allowed?: boolean
    reason?: string
    matchedRules?: string[]
  }
  supplyChainDecision?: {
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
  agentRun?: {
    agentRunId?: string
    mode?: string
    recommendedAction?: string
    priority?: string
    willExecute?: boolean
  }
  planRun?: {
    planRunId?: string
    sourceAgentRunId?: string
    mode?: string
    planType?: string
    priority?: string
    retrievedEvidenceCount?: number
    willExecute?: boolean
  }
  executionRequest?: {
    executionRequestId?: string
    sourcePlanRunId?: string
    mode?: string
    requestedAction?: string
    requestStatus?: string
    policyDecision?: string
    requiresHumanApproval?: boolean
    approvalStatus?: string
    approved?: boolean
    willExecute?: boolean
  }
}

type ControlPlaneEvidencePayload = {
  env?: string
  namespace?: string
  environmentProfile?: string
  clusterName?: string
  environmentConfigRef?: string
  gitopsOverlayPath?: string
  policyProfile?: string
  policyDecisionId?: string
  supplyChainDecisionId?: string
  agentRunId?: string
  planRunId?: string
  executionRequestId?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  summary?: {
    rolloutPhase?: string
    analysisRunPhase?: string
    failedMetrics?: unknown[]
    matchedPolicyRules?: string[]
  }
  artifacts?: Record<string, string>
  decisionRefs?: EvidenceDecisionRefs
}

type ControlPlaneCard = {
  title: string
  subtitle: string
  value: string
  rawValue?: string
  objectId?: string
  resource?: ReleaseResourceRef
  resourceKey?: string
  artifactRef?: string
  icon: typeof GitBranch
  focusTab: string
  statusValue: string
  details?: Array<[string, string]>
}

function normalizeKey(value: string) {
  return value.replace(/[-_\s]/g, "").toLowerCase()
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function findResource(
  resources: Record<string, ReleaseResourceRef> | undefined,
  candidates: string[],
) {
  const entries = Object.entries(resources ?? {})
  const normalizedCandidates = candidates.map(normalizeKey)

  for (const [key, resource] of entries) {
    const normalizedKey = normalizeKey(key)
    if (normalizedCandidates.some((candidate) => normalizedKey.includes(candidate))) {
      return { key, resource }
    }
  }

  return null
}

function resourceLabel(resource?: ReleaseResourceRef, artifactRef?: string) {
  if (artifactRef) return artifactRef
  if (!resource) return "missing"
  if (resource.exists === false) return "missing"
  return resource.baseName ?? resource.name ?? resource.file ?? resource.resourceId ?? "available"
}

function resourceExists(resource?: ReleaseResourceRef) {
  if (!resource) return false
  return resource.exists !== false
}

function MetaRow({
  label,
  value,
  truncate = false,
}: {
  label: string
  value: string
  truncate?: boolean
}) {
  return (
    <div className="grid grid-cols-[120px_minmax(0,1fr)] items-start gap-3 text-xs">
      <span className="text-slate-500">{label}</span>
      <span
        className={
          truncate
            ? "min-w-0 truncate text-right font-mono font-semibold text-slate-700"
            : "min-w-0 break-all text-right font-mono font-semibold text-slate-700"
        }
        title={value}
      >
        {value}
      </span>
    </div>
  )
}

function ControlPlaneObjectCard({
  card,
  onTabChange,
}: {
  card: ControlPlaneCard
  onTabChange: (tab: string) => void
}) {
  const Icon = card.icon
  const linked = Boolean(card.objectId || card.artifactRef || resourceExists(card.resource))

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-cyan-100 bg-cyan-50 text-cyan-700">
            <Icon className="h-5 w-5" />
          </div>
          <div>
            <h4 className="font-semibold text-[#031a41]">{card.title}</h4>
            <p className="mt-1 text-xs text-slate-500">{card.subtitle}</p>
          </div>
        </div>

        <Badge
          value={linked ? card.statusValue : "MISSING"}
          label={linked ? "linked" : "missing"}
        />
      </div>

      <div className="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-3">
        <p className="text-xs text-slate-500">Control-plane signal</p>
        <p className="mt-1 font-semibold text-[#031a41]">{card.value}</p>
        {card.rawValue ? (
          <p className="mt-1 break-all font-mono text-xs text-slate-500">{card.rawValue}</p>
        ) : null}
      </div>

      <div className="mt-3 grid gap-2">
        <MetaRow label="objectId" value={card.objectId ?? "-"} />
        <MetaRow label="resourceKey" value={card.resourceKey ?? "-"} />
        <MetaRow
          label="artifact"
          value={resourceLabel(card.resource, card.artifactRef)}
          truncate
        />
      </div>

      {card.details && card.details.length > 0 ? (
        <div className="mt-3 rounded-xl border border-slate-200 bg-slate-50 p-3">
          <div className="grid gap-2">
            {card.details.map(([key, value]) => (
              <MetaRow key={key} label={key} value={value} />
            ))}
          </div>
        </div>
      ) : null}

      <button
        type="button"
        onClick={() => onTabChange(card.focusTab)}
        className="mt-4 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
      >
        查看 {card.focusTab}
      </button>
    </div>
  )
}

export function ControlPlaneObjectCards({
  selected,
  evidenceQuery,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  evidenceQuery?: UseQueryResult<ReleaseResourceContent, Error>
  onTabChange: (tab: string) => void
}) {
  const summary = selected.summary
  const evidencePayload = evidenceQuery?.data
    ? parseJsonResource<ControlPlaneEvidencePayload>(evidenceQuery.data.body)
    : null

  const artifacts = evidencePayload?.artifacts ?? {}
  const refs = evidencePayload?.decisionRefs ?? {}

  const environment = findResource(selected.resources, ["environment", "context", "releasecontext"])
  const evidence = findResource(selected.resources, ["evidence", "releaseevidence"])
  const policy = findResource(selected.resources, ["policy", "policydecision"])
  const advisor = findResource(selected.resources, ["advice", "aidecision", "intelligence"])
  const actionPlan = findResource(selected.resources, ["actionplan"])
  const supplyChain = findResource(selected.resources, ["supplychain", "supplychaindecision"])

  const failedMetricCount = evidencePayload?.summary?.failedMetrics?.length ?? 0
  const matchedRuleCount = evidencePayload?.summary?.matchedPolicyRules?.length ?? 0
  const agentRun = refs.agentRun
  const planRun = refs.planRun
  const executionRequest = refs.executionRequest
  const supplyChainDecision = refs.supplyChainDecision
  const policyDecision = refs.policyDecision
  const aiDecision = refs.aiDecision

  const cards: ControlPlaneCard[] = [
    {
      title: "Environment & Packaging",
      subtitle: "环境配置、GitOps overlay 与发布上下文。",
      value: `${valueOrDash(evidencePayload?.env)} · ${valueOrDash(evidencePayload?.clusterName)}`,
      rawValue: `namespace=${valueOrDash(evidencePayload?.namespace)} · overlay=${valueOrDash(evidencePayload?.gitopsOverlayPath)}`,
      objectId: evidencePayload?.environmentProfile ?? evidencePayload?.env,
      resource: environment?.resource,
      resourceKey: environment?.key,
      artifactRef: artifacts.environmentConfig ?? evidencePayload?.environmentConfigRef,
      icon: Boxes,
      focusTab: "Context",
      statusValue: "PASS",
      details: [
        ["policyProfile", valueOrDash(evidencePayload?.policyProfile)],
        ["configRef", valueOrDash(evidencePayload?.environmentConfigRef)],
      ],
    },
    {
      title: "SLO / Evidence",
      subtitle: "运行时 SLO 结果和 evidence bundle。",
      value: resultDisplay(evidencePayload?.releaseResult ?? summary.releaseResult),
      rawValue: evidencePayload?.releaseResult ?? summary.releaseResult,
      resource: evidence?.resource,
      resourceKey: evidence?.key,
      artifactRef: artifacts.releaseEvidence,
      icon: FileCheck2,
      focusTab: "Evidence",
      statusValue: evidencePayload?.releaseResult ?? summary.releaseResult,
      details: [
        ["failedMetrics", String(failedMetricCount)],
        ["rolloutPhase", valueOrDash(evidencePayload?.summary?.rolloutPhase)],
        ["analysisRunPhase", valueOrDash(evidencePayload?.summary?.analysisRunPhase)],
      ],
    },
    {
      title: "Policy Guard",
      subtitle: "策略裁决、人工门禁和最终动作。",
      value: policyDisplay(evidencePayload?.policyDecision ?? summary.policyDecision),
      rawValue: `${valueOrDash(evidencePayload?.policyDecision ?? summary.policyDecision)} · ${actionDisplay(evidencePayload?.finalAction ?? summary.finalAction)}`,
      objectId: evidencePayload?.policyDecisionId ?? policyDecision?.policyDecisionId,
      resource: policy?.resource,
      resourceKey: policy?.key,
      artifactRef: artifacts.policyDecision,
      icon: ShieldCheck,
      focusTab: "Evidence",
      statusValue: evidencePayload?.policyDecision ?? summary.policyDecision,
      details: [
        ["requestedAction", valueOrDash(policyDecision?.requestedAction)],
        ["allowed", valueOrDash(policyDecision?.allowed)],
        ["matchedRules", String(matchedRuleCount)],
      ],
    },
    {
      title: "AI Advisor / Plan Run",
      subtitle: "只读智能分析、建议、RAG 规划和风险解释。",
      value: agentRun?.recommendedAction ?? aiDecision?.agentAction?.type ?? riskText(summary.riskLevel),
      rawValue: `agent=${valueOrDash(evidencePayload?.agentRunId ?? agentRun?.agentRunId)} · plan=${valueOrDash(evidencePayload?.planRunId ?? planRun?.planRunId)}`,
      objectId: evidencePayload?.agentRunId ?? agentRun?.agentRunId,
      resource: advisor?.resource,
      resourceKey: advisor?.key,
      artifactRef: artifacts.agentRun ?? artifacts.planRun ?? artifacts.aiDecision,
      icon: Bot,
      focusTab: "AI Advice",
      statusValue: agentRun?.priority ?? summary.riskLevel,
      details: [
        ["planRunId", valueOrDash(evidencePayload?.planRunId ?? planRun?.planRunId)],
        ["planType", valueOrDash(planRun?.planType)],
        ["retrievedEvidence", valueOrDash(planRun?.retrievedEvidenceCount)],
      ],
    },
    {
      title: "Execution Request",
      subtitle: "策略约束下的动作申请，不代表真实执行。",
      value: executionRequest?.requestStatus ?? (summary.requiresHumanApproval ? "Human approval required" : "No human gate"),
      rawValue: `requestedAction=${valueOrDash(executionRequest?.requestedAction ?? summary.finalAction)}`,
      objectId: evidencePayload?.executionRequestId ?? executionRequest?.executionRequestId,
      resource: actionPlan?.resource,
      resourceKey: actionPlan?.key,
      artifactRef: artifacts.executionRequest ?? artifacts.actionPlan,
      icon: ClipboardCheck,
      focusTab: "Action Plan",
      statusValue: executionRequest?.requestStatus ?? (summary.requiresHumanApproval ? "REQUIRED" : "PASS"),
      details: [
        ["approvalStatus", valueOrDash(executionRequest?.approvalStatus)],
        ["approved", valueOrDash(executionRequest?.approved)],
        ["willExecute", valueOrDash(executionRequest?.willExecute)],
      ],
    },
    {
      title: "Supply Chain",
      subtitle: "发布对象可信度、镜像和 GitOps 追溯。",
      value: supplyChainDecision?.decision ?? (supplyChain ? "Supply chain decision linked" : "Decision not indexed"),
      rawValue: `risk=${valueOrDash(supplyChainDecision?.riskLevel)} · score=${valueOrDash(supplyChainDecision?.riskScore)}`,
      objectId: evidencePayload?.supplyChainDecisionId ?? supplyChainDecision?.supplyChainDecisionId,
      resource: supplyChain?.resource,
      resourceKey: supplyChain?.key,
      artifactRef: artifacts.supplyChainDecision,
      icon: GitBranch,
      focusTab: "Evidence",
      statusValue: supplyChainDecision?.decision ?? (supplyChain ? "PASS" : "MISSING"),
      details: [
        ["gitopsTag", valueOrDash(supplyChainDecision?.gitopsReleaseTag)],
        ["imageTag", valueOrDash(supplyChainDecision?.imageTag)],
        ["blockingReasons", String(supplyChainDecision?.blockingReasons?.length ?? 0)],
      ],
    },
  ]

  return (
    <section className="rounded-2xl border border-slate-200 bg-slate-50 p-5 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Release Detail Consolidation
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-[#031a41]">
            一次发布关联的控制平面对象
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            将 SLO、Policy、AI Advisor、Plan Run、Execution Request、Supply Chain 和 Environment 从 evidence 中收口到发布详情顶部。
          </p>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm">
          <p className="text-xs text-slate-500">Release ID</p>
          <p className="mt-1 font-mono font-semibold text-[#031a41]">{selected.releaseId}</p>
          <p className="mt-1 text-xs text-slate-500">
            evidence={evidenceQuery?.isLoading ? "loading" : evidencePayload ? "parsed" : "fallback"}
          </p>
        </div>
      </div>

      {evidenceQuery?.isError ? (
        <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          控制平面对象深度信息读取失败，已回退到 Release resource index。
        </div>
      ) : null}

      <div className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {cards.map((card) => (
          <ControlPlaneObjectCard
            key={card.title}
            card={card}
            onTabChange={onTabChange}
          />
        ))}
      </div>
    </section>
  )
}
