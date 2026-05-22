import type { ComponentType } from "react"
import type { UseQueryResult } from "@tanstack/react-query"
import {
  AlertTriangle,
  CheckCircle2,
  ClipboardCheck,
  FileCheck2,
  LockKeyhole,
  PauseCircle,
  Route,
  ShieldCheck,
  UserCheck,
  XCircle,
} from "lucide-react"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import {
  parseJsonResource,
  RuleChipsPanel,
  stringifyValue,
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
}

type ExecutionRequestRef = {
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

type AgentRunRef = {
  agentRunId?: string
  recommendedAction?: string
  priority?: string
  willExecute?: boolean
}

type PlanRunRef = {
  planRunId?: string
  planType?: string
  priority?: string
  willExecute?: boolean
}

type SupplyChainDecisionRef = {
  supplyChainDecisionId?: string
  decision?: string
  allowed?: boolean
  requiresHumanApproval?: boolean
  willExecute?: boolean
  blockingReasons?: string[]
  warningReasons?: string[]
}

type ApprovalEvidencePayload = {
  releaseId?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  requiresHumanApproval?: boolean
  safeToRetry?: boolean
  policyDecisionId?: string
  planRunId?: string
  executionRequestId?: string
  summary?: {
    matchedPolicyRules?: string[]
    failedMetrics?: unknown[]
  }
  matchedPolicyRules?: string[]
  decisionRefs?: {
    policyDecision?: PolicyDecisionRef
    executionRequest?: ExecutionRequestRef
    agentRun?: AgentRunRef
    planRun?: PlanRunRef
    supplyChainDecision?: SupplyChainDecisionRef
  }
}

type ConsoleMetric = {
  label: string
  value: string
  hint: string
  status: string
  icon: ComponentType<{ className?: string }>
}

type ApprovalStep = {
  title: string
  description: string
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

function statusClass(status: string) {
  const normalized = status.toLowerCase()

  if (
    normalized.includes("fail") ||
    normalized.includes("deny") ||
    normalized.includes("block") ||
    normalized.includes("rejected") ||
    normalized.includes("required") ||
    normalized.includes("pending") ||
    normalized.includes("false")
  ) {
    return "border-rose-200 bg-rose-50 text-rose-700"
  }

  if (
    normalized.includes("pass") ||
    normalized.includes("allow") ||
    normalized.includes("approved") ||
    normalized.includes("not required") ||
    normalized.includes("true") ||
    normalized.includes("read-only")
  ) {
    return "border-emerald-200 bg-emerald-50 text-emerald-700"
  }

  return "border-cyan-200 bg-cyan-50 text-cyan-700"
}

function ConsoleMetricCard({ metric }: { metric: ConsoleMetric }) {
  const Icon = metric.icon

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-cyan-100 bg-cyan-50 text-cyan-700">
            <Icon className="h-4 w-4" />
          </div>
          <div className="min-w-0">
            <p className="text-xs text-slate-500">{metric.label}</p>
            <p className="mt-1 break-all font-semibold text-[#031a41]">{metric.value}</p>
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

function ApprovalStepCard({ step, index }: { step: ApprovalStep; index: number }) {
  const Icon = step.icon

  return (
    <div className="flex gap-3 rounded-xl border border-slate-200 bg-white p-4">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#031a41] text-sm font-semibold text-white">
        {index + 1}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
          <div className="flex min-w-0 items-center gap-2">
            <Icon className="h-4 w-4 shrink-0 text-cyan-700" />
            <h4 className="font-semibold text-[#031a41]">{step.title}</h4>
          </div>
          <span className={`w-fit rounded-full border px-2.5 py-1 text-[11px] font-semibold ${statusClass(step.status)}`}>
            {step.status}
          </span>
        </div>
        <p className="mt-2 text-sm leading-6 text-slate-600">{step.description}</p>
      </div>
    </div>
  )
}

function ApprovalBoundaryPanel({
  requiresHumanApproval,
  approved,
  willExecute,
}: {
  requiresHumanApproval: boolean
  approved: boolean | null | undefined
  willExecute: boolean | null | undefined
}) {
  const gates = [
    {
      key: "requiresHumanApproval",
      label: "人工审批要求",
      value: requiresHumanApproval,
      expectedSafe: false,
      description: "true 表示当前动作需要人工审批；Portal 只展示，不执行审批。",
    },
    {
      key: "approved",
      label: "审批完成状态",
      value: Boolean(approved),
      expectedSafe: false,
      description: "true 表示已有审批记录；false 表示不能进入执行阶段。",
    },
    {
      key: "willExecute",
      label: "执行开关",
      value: Boolean(willExecute),
      expectedSafe: false,
      description: "Stage 41 必须保持 false，任何执行都应进入后续 Policy-bound Executor。",
    },
    {
      key: "portalReadOnly",
      label: "Portal 只读",
      value: true,
      expectedSafe: true,
      description: "当前控制台不提供 approve / reject / execute 按钮。",
    },
  ]

  return (
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
      {gates.map((gate) => {
        const isSafe = gate.value === gate.expectedSafe

        return (
          <div
            key={gate.key}
            className={`rounded-xl border p-4 ${
              isSafe
                ? "border-emerald-200 bg-emerald-50"
                : "border-amber-200 bg-amber-50"
            }`}
          >
            <p className={`text-sm font-semibold ${isSafe ? "text-emerald-900" : "text-amber-900"}`}>
              {gate.label}
            </p>
            <p className={`mt-2 font-mono text-lg font-bold ${isSafe ? "text-emerald-700" : "text-amber-700"}`}>
              {String(gate.value)}
            </p>
            <p className={`mt-2 text-xs leading-5 ${isSafe ? "text-emerald-700" : "text-amber-700"}`}>
              {gate.description}
            </p>
          </div>
        )
      })}
    </div>
  )
}

export function ApprovalConsolePanel({
  selected,
  evidenceQuery,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  onTabChange: (tab: string) => void
}) {
  const evidence = evidenceQuery.data
    ? parseJsonResource<ApprovalEvidencePayload>(evidenceQuery.data.body)
    : null

  const summary = selected.summary
  const refs = evidence?.decisionRefs ?? {}
  const policyDecisionRef = refs.policyDecision
  const executionRequest = refs.executionRequest
  const supplyChainDecision = refs.supplyChainDecision
  const agentRun = refs.agentRun
  const planRun = refs.planRun

  const releaseResult = evidence?.releaseResult ?? summary.releaseResult
  const policyDecision = executionRequest?.policyDecision ?? evidence?.policyDecision ?? summary.policyDecision
  const requestedAction =
    executionRequest?.requestedAction ??
    policyDecisionRef?.requestedAction ??
    agentRun?.recommendedAction ??
    evidence?.finalAction ??
    summary.finalAction
  const executionMode = executionRequest?.mode ?? evidence?.executionMode ?? summary.executionMode
  const requiresHumanApproval =
    executionRequest?.requiresHumanApproval ??
    supplyChainDecision?.requiresHumanApproval ??
    evidence?.requiresHumanApproval ??
    summary.requiresHumanApproval
  const approvalStatus = executionRequest?.approvalStatus ?? (requiresHumanApproval ? "PENDING" : "NOT_REQUIRED")
  const approved = executionRequest?.approved
  const willExecute =
    executionRequest?.willExecute ??
    planRun?.willExecute ??
    agentRun?.willExecute ??
    supplyChainDecision?.willExecute ??
    false
  const requestStatus =
    executionRequest?.requestStatus ??
    (requiresHumanApproval ? "WAITING_FOR_APPROVAL" : "NO_HUMAN_GATE")
  const executionRequestId =
    evidence?.executionRequestId ??
    executionRequest?.executionRequestId ??
    "-"
  const policyDecisionId =
    evidence?.policyDecisionId ??
    policyDecisionRef?.policyDecisionId ??
    "-"
  const planRunId =
    evidence?.planRunId ??
    planRun?.planRunId ??
    executionRequest?.sourcePlanRunId ??
    "-"
  const matchedRules =
    policyDecisionRef?.matchedRules ??
    evidence?.summary?.matchedPolicyRules ??
    evidence?.matchedPolicyRules ??
    []
  const blockingReasons = supplyChainDecision?.blockingReasons ?? []
  const warningReasons = supplyChainDecision?.warningReasons ?? []

  const metrics: ConsoleMetric[] = [
    {
      label: "Execution Request",
      value: executionRequestId,
      hint: `requestStatus=${requestStatus}`,
      status: requestStatus,
      icon: ClipboardCheck,
    },
    {
      label: "Approval Required",
      value: approvalText(Boolean(requiresHumanApproval)),
      hint: `requiresHumanApproval=${approvalRaw(Boolean(requiresHumanApproval))}`,
      status: approvalRaw(Boolean(requiresHumanApproval)),
      icon: LockKeyhole,
    },
    {
      label: "Approval Status",
      value: approvalStatus,
      hint: `approved=${boolText(approved)}`,
      status: approvalStatus,
      icon: approved ? UserCheck : PauseCircle,
    },
    {
      label: "Requested Action",
      value: actionDisplay(requestedAction),
      hint: `raw=${requestedAction}`,
      status: requestedAction,
      icon: Route,
    },
    {
      label: "Policy Decision",
      value: policyDisplay(policyDecision),
      hint: `policyDecisionId=${policyDecisionId}`,
      status: policyDecision,
      icon: ShieldCheck,
    },
    {
      label: "Will Execute",
      value: boolText(willExecute),
      hint: "Stage 41 Portal 不执行任何动作。",
      status: willExecute ? "REQUIRED" : "NOT REQUIRED",
      icon: willExecute ? AlertTriangle : CheckCircle2,
    },
  ]

  const steps: ApprovalStep[] = [
    {
      title: "Policy Decision",
      description: `策略裁决为 ${policyDisplay(policyDecision)}，发布结果为 ${resultDisplay(releaseResult)}。`,
      status: policyDecision,
      icon: ShieldCheck,
    },
    {
      title: "Execution Request",
      description:
        executionRequestId === "-"
          ? "当前 evidence 没有显式 executionRequestId，控制台以 release summary / policy fallback 展示。"
          : `执行申请对象已关联：${executionRequestId}。`,
      status: executionRequestId === "-" ? "MISSING" : requestStatus,
      icon: ClipboardCheck,
    },
    {
      title: "Human Approval Gate",
      description: requiresHumanApproval
        ? "当前动作需要人工审批。Portal 只展示审批状态，不提供审批按钮。"
        : "当前动作不需要人工审批，但仍保持只读，不自动执行。",
      status: approvalRaw(Boolean(requiresHumanApproval)),
      icon: LockKeyhole,
    },
    {
      title: "Approval Record",
      description: approved
        ? "审批状态显示为 approved，但执行仍需要受控执行器和审计证据。"
        : "当前未看到 approved=true，不能进入执行阶段。",
      status: approved ? "APPROVED" : approvalStatus,
      icon: approved ? UserCheck : PauseCircle,
    },
    {
      title: "Execution Boundary",
      description: willExecute
        ? "检测到 willExecute=true，必须视为高风险状态，不能由 Portal 直接执行。"
        : "willExecute=false，符合 Stage 41 只读控制台边界。",
      status: willExecute ? "REQUIRED" : "PASS",
      icon: willExecute ? XCircle : CheckCircle2,
    },
  ]

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-4 border-b border-slate-200 pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Approval Console
          </p>
          <h3 className="mt-2 flex items-center gap-2 text-lg font-semibold tracking-tight text-[#031a41]">
            <UserCheck className="h-5 w-5 text-cyan-700" />
            人工审批与执行申请只读控制台
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            聚合 Execution Request、Policy Decision、Action Plan 和人工审批状态。
            当前阶段只展示审批边界，不提供 approve、reject 或 execute 操作。
          </p>
        </div>

        <div className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
          <p className="text-xs text-slate-500">Console Source</p>
          <p className="mt-1 font-semibold text-[#031a41]">
            {evidenceQuery.isLoading ? "loading" : evidence ? "release evidence" : "release summary fallback"}
          </p>
          <p className="mt-1 font-mono text-xs text-slate-500">releaseId={selected.releaseId}</p>
        </div>
      </div>

      {evidenceQuery.isError ? (
        <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          Approval Console 无法读取 release evidence，已回退到 Release summary。
        </div>
      ) : null}

      <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {metrics.map((metric) => (
          <ConsoleMetricCard key={metric.label} metric={metric} />
        ))}
      </div>

      <section className="mt-5">
        <ApprovalBoundaryPanel
          requiresHumanApproval={Boolean(requiresHumanApproval)}
          approved={approved}
          willExecute={willExecute}
        />
      </section>

      <section className="mt-5 grid gap-4 lg:grid-cols-[0.95fr_1.05fr]">
        <div className="space-y-3">
          {steps.map((step, index) => (
            <ApprovalStepCard key={step.title} step={step} index={index} />
          ))}
        </div>

        <div className="space-y-4">
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
            <div className="mb-3 flex items-center gap-2 font-semibold text-[#031a41]">
              <FileCheck2 className="h-4 w-4 text-cyan-700" />
              Request Detail
            </div>
            <KeyValueRows
              rows={[
                ["executionRequestId", executionRequestId],
                ["sourcePlanRunId", planRunId],
                ["mode", valueOrDash(executionMode)],
                ["requestedAction", requestedAction],
                ["requestStatus", requestStatus],
                ["policyDecision", policyDecision],
                ["approvalStatus", approvalStatus],
                ["approved", boolText(approved)],
                ["willExecute", boolText(willExecute)],
              ]}
            />
          </div>

          <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
            <div className="mb-3 flex items-center gap-2 font-semibold text-[#031a41]">
              <ShieldCheck className="h-4 w-4 text-cyan-700" />
              Policy / Gate Context
            </div>
            <KeyValueRows
              rows={[
                ["releaseResult", resultDisplay(releaseResult)],
                ["policyDecisionId", policyDecisionId],
                ["policyRuntimeResultId", valueOrDash(policyDecisionRef?.policyRuntimeResultId)],
                ["policyAllowed", boolText(policyDecisionRef?.allowed)],
                ["safeToRetry", boolText(evidence?.safeToRetry ?? summary.safeToRetry)],
                ["supplyChainDecision", valueOrDash(supplyChainDecision?.decision)],
                ["supplyChainAllowed", boolText(supplyChainDecision?.allowed)],
              ]}
            />
          </div>
        </div>
      </section>

      <section className="mt-5 grid gap-4 lg:grid-cols-3">
        <div className="rounded-xl border border-slate-200 bg-white p-4">
          <h4 className="text-sm font-semibold text-slate-900">Matched Policy Rules</h4>
          <div className="mt-3">
            <RuleChipsPanel rules={matchedRules} />
          </div>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-4">
          <h4 className="text-sm font-semibold text-slate-900">Blocking Reasons</h4>
          <div className="mt-3">
            <RuleChipsPanel rules={blockingReasons.length > 0 ? blockingReasons : ["none"]} />
          </div>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-4">
          <h4 className="text-sm font-semibold text-slate-900">Warning Reasons</h4>
          <div className="mt-3">
            <RuleChipsPanel rules={warningReasons.length > 0 ? warningReasons : ["none"]} />
          </div>
        </div>
      </section>

      <div className="mt-5 rounded-xl border border-cyan-200 bg-cyan-50 p-4 text-sm text-slate-700">
        <div className="flex items-center gap-2 font-semibold text-[#031a41]">
          <LockKeyhole className="h-4 w-4 text-cyan-700" />
          Approval Console 边界
        </div>
        <p className="mt-2 leading-6">
          当前 Console 只做可观测和审计展示。真正的 approve / reject / execute 应该在后续
          Policy-bound Execution Request 和 Policy-bound Executor 阶段实现，并写入新的 EvidenceRecord。
        </p>
      </div>

      <div className="mt-5 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => onTabChange("Action Plan")}
          className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
        >
          查看 Action Plan
        </button>
        <button
          type="button"
          onClick={() => onTabChange("Evidence")}
          className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
        >
          查看 Evidence
        </button>
        <button
          type="button"
          onClick={() => onTabChange("Runbook")}
          className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
        >
          查看 Runbook
        </button>
      </div>
    </section>
  )
}
