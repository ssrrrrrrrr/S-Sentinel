import { ActionButton } from "@/components/common/ActionButton"
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
  lifecycleStage?: string
  policyDecision?: string
  requiresHumanApproval?: boolean
  approvalStatus?: string
  approved?: boolean
  approvalDecision?: string
  approver?: string
  readyToExecute?: boolean
  willExecute?: boolean
}

type ExecutionEligibilityRef = {
  eligibilityDecisionId?: string
  finalStatus?: string
  readyToExecute?: boolean
  requestedAction?: string
  requestStatus?: string
  lifecycleStage?: string
  approvalStatus?: string
  approvalDecision?: string
  approver?: string
  supplyChainDecision?: string
  signedReleaseGateDecision?: string
  blockingReasons?: string[]
  approvalReasons?: string[]
  missingInputs?: string[]
}

type ExecutionPreviewRef = {
  executionPreviewId?: string
  previewStatus?: string
  readyToExecute?: boolean
  requestedAction?: string
  plannedActionCount?: number
  blockedActionCount?: number
  humanCheckpointCount?: number
  gitopsChangeCount?: number
  renderedReleasePlan?: string
}

type ExecutionResultRef = {
  executionResultId?: string
  executionStatus?: string
  readyForExecution?: boolean
  requestedAction?: string
  executedActionCount?: number
  blockedActionCount?: number
  executorAdapter?: string
}

type GitopsPatchProposalRef = {
  gitopsPatchProposalId?: string
  proposalStatus?: string
  requestedAction?: string
  overlayPath?: string
  patchCount?: number
  blockedChangeCount?: number
  repositoryRoot?: string
  outputDir?: string
}

type GitopsPRBundleRef = {
  gitopsPRBundleId?: string
  bundleStatus?: string
  branchName?: string
  commitMessage?: string
  pullRequestTitle?: string
  patchEntryCount?: number
  handoffChecklistCount?: number
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
    executionEligibility?: ExecutionEligibilityRef
    executionPreview?: ExecutionPreviewRef
    executionResult?: ExecutionResultRef
    gitopsPatchProposal?: GitopsPatchProposalRef
    gitopsPRBundle?: GitopsPRBundleRef
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
    return "border-rose-900/45 bg-rose-950/20 text-rose-200"
  }

  if (
    normalized.includes("pass") ||
    normalized.includes("allow") ||
    normalized.includes("approved") ||
    normalized.includes("not required") ||
    normalized.includes("true") ||
    normalized.includes("read-only")
  ) {
    return "border-emerald-900/45 bg-emerald-950/20 text-emerald-200"
  }

  return "border-[#35517a] bg-[#101a29] text-[#5d8fd8]"
}

function ConsoleMetricCard({ metric }: { metric: ConsoleMetric }) {
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
            <p className="mt-1 break-all font-semibold text-slate-100">{metric.value}</p>
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
    <div className="flex gap-3 rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#14233a] text-sm font-semibold text-slate-50">
        {index + 1}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
          <div className="flex min-w-0 items-center gap-2">
            <Icon className="h-4 w-4 shrink-0 text-[#5d8fd8]" />
            <h4 className="font-semibold text-slate-100">{step.title}</h4>
          </div>
          <span className={`w-fit rounded-full border px-2.5 py-1 text-[11px] font-semibold ${statusClass(step.status)}`}>
            {step.status}
          </span>
        </div>
        <p className="mt-2 text-sm leading-6 text-slate-400">{step.description}</p>
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
      description: "当前控制台必须保持 false，任何执行都应进入后续 Policy-bound Executor。",
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
                ? "border-emerald-900/45 bg-emerald-950/20"
                : "border-amber-900/45 bg-amber-950/20"
            }`}
          >
            <p className={`text-sm font-semibold ${isSafe ? "text-emerald-200" : "text-amber-200"}`}>
              {gate.label}
            </p>
            <p className={`mt-2 font-mono text-lg font-bold ${isSafe ? "text-emerald-200" : "text-amber-200"}`}>
              {String(gate.value)}
            </p>
            <p className={`mt-2 text-xs leading-5 ${isSafe ? "text-emerald-200" : "text-amber-200"}`}>
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
  const executionEligibility = refs.executionEligibility
  const executionPreview = refs.executionPreview
  const executionResult = refs.executionResult
  const gitopsPatchProposal = refs.gitopsPatchProposal
  const gitopsPRBundle = refs.gitopsPRBundle
  const supplyChainDecision = refs.supplyChainDecision
  const agentRun = refs.agentRun
  const planRun = refs.planRun

  const releaseResult = evidence?.releaseResult ?? summary.releaseResult
  const policyDecision = executionRequest?.policyDecision ?? evidence?.policyDecision ?? summary.policyDecision
  const requestedAction =
    executionPreview?.requestedAction ??
    executionEligibility?.requestedAction ??
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
  const approvalStatus =
    executionEligibility?.approvalStatus ??
    executionRequest?.approvalStatus ??
    (requiresHumanApproval ? "PENDING" : "NOT_REQUIRED")
  const approved = executionRequest?.approved
  const willExecute =
    executionRequest?.willExecute ??
    planRun?.willExecute ??
    agentRun?.willExecute ??
    supplyChainDecision?.willExecute ??
    false
  const requestStatus =
    executionEligibility?.requestStatus ??
    executionRequest?.requestStatus ??
    (requiresHumanApproval ? "WAITING_FOR_APPROVAL" : "NO_HUMAN_GATE")
  const lifecycleStage =
    executionEligibility?.lifecycleStage ??
    executionRequest?.lifecycleStage ??
    (requiresHumanApproval ? "WAITING_APPROVAL" : "POLICY_CHECKED")
  const eligibilityStatus = executionEligibility?.finalStatus ?? lifecycleStage
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
  const readyToExecute =
    executionPreview?.readyToExecute ??
    executionEligibility?.readyToExecute ??
    executionRequest?.readyToExecute ??
    false
  const previewStatus = executionPreview?.previewStatus ?? eligibilityStatus
  const plannedActionCount = executionPreview?.plannedActionCount ?? 0
  const blockedActionCount = executionPreview?.blockedActionCount ?? 0
  const humanCheckpointCount = executionPreview?.humanCheckpointCount ?? 0
  const gitopsChangeCount = executionPreview?.gitopsChangeCount ?? 0
  const executionStatus = executionResult?.executionStatus ?? "NOT_EXECUTED"
  const executedActionCount = executionResult?.executedActionCount ?? 0
  const executorAdapter = executionResult?.executorAdapter ?? "noop-executor"
  const gitopsProposalStatus = gitopsPatchProposal?.proposalStatus ?? previewStatus
  const gitopsPatchCount = gitopsPatchProposal?.patchCount ?? gitopsChangeCount
  const gitopsBlockedChangeCount = gitopsPatchProposal?.blockedChangeCount ?? blockedActionCount
  const gitopsBundleStatus = gitopsPRBundle?.bundleStatus ?? gitopsProposalStatus
  const gitopsBundlePatchEntryCount = gitopsPRBundle?.patchEntryCount ?? gitopsPatchCount

  const metrics: ConsoleMetric[] = [
    {
      label: "Execution Request",
      value: executionRequestId,
      hint: `requestStatus=${requestStatus}`,
      status: eligibilityStatus,
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
      label: "Lifecycle Stage",
      value: eligibilityStatus,
      hint: `readyToExecute=${boolText(readyToExecute)}`,
      status: eligibilityStatus,
      icon: readyToExecute ? CheckCircle2 : PauseCircle,
    },
    {
      label: "Execution Preview",
      value: valueOrDash(executionPreview?.executionPreviewId),
      hint: `plannedActions=${plannedActionCount}`,
      status: previewStatus,
      icon: FileCheck2,
    },
    {
      label: "Execution Result",
      value: valueOrDash(executionResult?.executionResultId),
      hint: `executedActions=${executedActionCount}`,
      status: executionStatus,
      icon: ClipboardCheck,
    },
    {
      label: "GitOps Proposal",
      value: valueOrDash(gitopsPatchProposal?.gitopsPatchProposalId),
      hint: `patchCount=${gitopsPatchCount}`,
      status: gitopsProposalStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Bundle",
      value: valueOrDash(gitopsPRBundle?.gitopsPRBundleId),
      hint: `patchEntries=${gitopsBundlePatchEntryCount}`,
      status: gitopsBundleStatus,
      icon: FileCheck2,
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
      hint: "Portal 不执行任何动作。",
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
      status: executionRequestId === "-" ? "MISSING" : eligibilityStatus,
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
      status: executionEligibility?.finalStatus ?? (approved ? "APPROVED" : approvalStatus),
      icon: approved ? UserCheck : PauseCircle,
    },
    {
      title: "Execution Boundary",
      description: willExecute
        ? "检测到 willExecute=true，必须视为高风险状态，不能由 Portal 直接执行。"
        : "willExecute=false，符合只读控制台边界。",
      status: willExecute ? "REQUIRED" : "PASS",
      icon: willExecute ? XCircle : CheckCircle2,
    },
    {
      title: "Dry-run Preview",
      description: executionPreview?.executionPreviewId
        ? `Dry-run preview 已生成：${executionPreview.executionPreviewId}，说明受控执行器将会如何处理这次 release。`
        : "当前 evidence 里还没有 execution preview，对执行影响面仍缺少显式预演对象。",
      status: executionPreview?.executionPreviewId ? previewStatus : "MISSING",
      icon: FileCheck2,
    },
    {
      title: "Executor Result",
      description: executionResult?.executionResultId
        ? `执行结果对象已生成：${executionResult.executionResultId}，当前由 ${executorAdapter} 记录 preview-only 执行证据。`
        : "当前 evidence 里还没有 execution result，对后续执行审计仍缺少标准化输出。",
      status: executionResult?.executionResultId ? executionStatus : "MISSING",
      icon: ClipboardCheck,
    },
    {
      title: "GitOps Patch Proposal",
      description: gitopsPatchProposal?.gitopsPatchProposalId
        ? `GitOps proposal 已生成：${gitopsPatchProposal.gitopsPatchProposalId}，当前只用于 review，不会提交 PR 或修改仓库。`
        : "当前 evidence 里还没有 GitOps patch proposal，后续 PR / patch adapter 还缺少标准提案对象。",
      status: gitopsPatchProposal?.gitopsPatchProposalId ? gitopsProposalStatus : "MISSING",
      icon: FileCheck2,
    },
    {
      title: "GitOps PR Bundle",
      description: gitopsPRBundle?.gitopsPRBundleId
        ? `GitOps bundle 已生成：${gitopsPRBundle.gitopsPRBundleId}，已经整理了 branch、commit message 和 PR 文案，但仍然不会 push 或开 PR。`
        : "当前 evidence 里还没有 GitOps PR bundle，后续人工 review / adapter handoff 还缺少可直接交付的 PR-ready 对象。",
      status: gitopsPRBundle?.gitopsPRBundleId ? gitopsBundleStatus : "MISSING",
      icon: FileCheck2,
    },
  ]

  return (
    <section className="rounded-2xl border border-[#1f2b3d] bg-[#0b121d] p-5 shadow-sm shadow-black/20">
      <div className="flex flex-col justify-between gap-4 border-b border-[#1f2b3d] pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Approval Console
          </p>
          <h3 className="mt-2 flex items-center gap-2 text-lg font-semibold tracking-tight text-slate-100">
            <UserCheck className="h-5 w-5 text-[#5d8fd8]" />
            人工审批与执行申请只读控制台
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            聚合 Execution Request、Policy Decision、Action Plan 和人工审批状态。
            当前阶段只展示审批边界，不提供 approve、reject 或 execute 操作。
          </p>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] px-4 py-3 text-sm">
          <p className="text-xs text-slate-500">Console Source</p>
          <p className="mt-1 font-semibold text-slate-100">
            {evidenceQuery.isLoading ? "loading" : evidence ? "release evidence" : "release summary fallback"}
          </p>
          <p className="mt-1 font-mono text-xs text-slate-500">releaseId={selected.releaseId}</p>
        </div>
      </div>

      {evidenceQuery.isError ? (
        <div className="mt-4 rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-200">
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
          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
            <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
              <FileCheck2 className="h-4 w-4 text-[#5d8fd8]" />
              Request Detail
            </div>
            <KeyValueRows
              rows={[
                ["executionRequestId", executionRequestId],
                ["sourcePlanRunId", planRunId],
                ["mode", valueOrDash(executionMode)],
                ["requestedAction", requestedAction],
                ["requestStatus", requestStatus],
                ["lifecycleStage", lifecycleStage],
                ["eligibilityStatus", eligibilityStatus],
                ["executionPreviewId", valueOrDash(executionPreview?.executionPreviewId)],
                ["previewStatus", valueOrDash(previewStatus)],
                ["executionResultId", valueOrDash(executionResult?.executionResultId)],
                ["executionStatus", valueOrDash(executionStatus)],
                ["executorAdapter", valueOrDash(executorAdapter)],
                ["gitopsPatchProposalId", valueOrDash(gitopsPatchProposal?.gitopsPatchProposalId)],
                ["gitopsProposalStatus", valueOrDash(gitopsProposalStatus)],
                ["gitopsOverlayPath", valueOrDash(gitopsPatchProposal?.overlayPath)],
                ["gitopsPRBundleId", valueOrDash(gitopsPRBundle?.gitopsPRBundleId)],
                ["gitopsBundleStatus", valueOrDash(gitopsBundleStatus)],
                ["gitopsBranchName", valueOrDash(gitopsPRBundle?.branchName)],
                ["policyDecision", policyDecision],
                ["approvalStatus", approvalStatus],
                ["approvalDecision", valueOrDash(executionEligibility?.approvalDecision ?? executionRequest?.approvalDecision)],
                ["approver", valueOrDash(executionEligibility?.approver ?? executionRequest?.approver)],
                ["approved", boolText(approved)],
                ["readyToExecute", boolText(readyToExecute)],
                ["willExecute", boolText(willExecute)],
              ]}
            />
          </div>

          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
            <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
              <ShieldCheck className="h-4 w-4 text-[#5d8fd8]" />
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
                ["eligibilityDecisionId", valueOrDash(executionEligibility?.eligibilityDecisionId)],
                ["executionPreviewId", valueOrDash(executionPreview?.executionPreviewId)],
                ["executionResultId", valueOrDash(executionResult?.executionResultId)],
                ["executionStatus", valueOrDash(executionStatus)],
                ["executedActionCount", valueOrDash(executedActionCount)],
                ["gitopsPatchProposalId", valueOrDash(gitopsPatchProposal?.gitopsPatchProposalId)],
                ["gitopsProposalStatus", valueOrDash(gitopsProposalStatus)],
                ["gitopsPatchCount", valueOrDash(gitopsPatchCount)],
                ["gitopsBlockedChangeCount", valueOrDash(gitopsBlockedChangeCount)],
                ["gitopsOverlayPath", valueOrDash(gitopsPatchProposal?.overlayPath)],
                ["gitopsPRBundleId", valueOrDash(gitopsPRBundle?.gitopsPRBundleId)],
                ["gitopsBundleStatus", valueOrDash(gitopsBundleStatus)],
                ["gitopsBranchName", valueOrDash(gitopsPRBundle?.branchName)],
                ["gitopsCommitMessage", valueOrDash(gitopsPRBundle?.commitMessage)],
                ["gitopsPRTitle", valueOrDash(gitopsPRBundle?.pullRequestTitle)],
                ["gitopsPatchEntryCount", valueOrDash(gitopsBundlePatchEntryCount)],
                ["plannedActionCount", valueOrDash(plannedActionCount)],
                ["blockedActionCount", valueOrDash(blockedActionCount)],
                ["humanCheckpointCount", valueOrDash(humanCheckpointCount)],
                ["gitopsChangeCount", valueOrDash(gitopsChangeCount)],
                ["signedReleaseGateDecision", valueOrDash(executionEligibility?.signedReleaseGateDecision)],
              ]}
            />
          </div>
        </div>
      </section>

      <section className="mt-5 grid gap-4 lg:grid-cols-4">
        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">Execution Preview</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `previewStatus:${valueOrDash(previewStatus)}`,
                `plannedActions:${plannedActionCount}`,
                `blockedActions:${blockedActionCount}`,
                `humanCheckpoints:${humanCheckpointCount}`,
                `gitopsChanges:${gitopsChangeCount}`,
                executionPreview?.renderedReleasePlan
                  ? `renderedPlan:${executionPreview.renderedReleasePlan}`
                  : "renderedPlan:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">Execution Result</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `executionStatus:${valueOrDash(executionStatus)}`,
                `executedActions:${executedActionCount}`,
                `blockedActions:${executionResult?.blockedActionCount ?? blockedActionCount}`,
                `readyForExecution:${boolText(executionResult?.readyForExecution)}`,
                `executor:${valueOrDash(executorAdapter)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Proposal</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `proposalStatus:${valueOrDash(gitopsProposalStatus)}`,
                `patchCount:${gitopsPatchCount}`,
                `blockedChanges:${gitopsBlockedChangeCount}`,
                gitopsPatchProposal?.overlayPath
                  ? `overlay:${gitopsPatchProposal.overlayPath}`
                  : "overlay:none",
                gitopsPatchProposal?.outputDir
                  ? `outputDir:${gitopsPatchProposal.outputDir}`
                  : "outputDir:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Bundle</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `bundleStatus:${valueOrDash(gitopsBundleStatus)}`,
                `patchEntries:${gitopsBundlePatchEntryCount}`,
                gitopsPRBundle?.branchName
                  ? `branch:${gitopsPRBundle.branchName}`
                  : "branch:none",
                gitopsPRBundle?.pullRequestTitle
                  ? `prTitle:${gitopsPRBundle.pullRequestTitle}`
                  : "prTitle:none",
                `handoffChecklist:${valueOrDash(gitopsPRBundle?.handoffChecklistCount ?? 0)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">Matched Policy Rules</h4>
          <div className="mt-3">
            <RuleChipsPanel rules={matchedRules} />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">Blocking Reasons</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={
                executionEligibility?.blockingReasons && executionEligibility.blockingReasons.length > 0
                  ? executionEligibility.blockingReasons
                  : blockingReasons.length > 0
                    ? blockingReasons
                    : ["none"]
              }
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">Approval / Missing Inputs</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={
                [
                  ...(executionEligibility?.approvalReasons ?? []),
                  ...(executionEligibility?.missingInputs ?? []),
                  ...warningReasons,
                ].length > 0
                  ? [
                      ...(executionEligibility?.approvalReasons ?? []),
                      ...(executionEligibility?.missingInputs ?? []),
                      ...warningReasons,
                    ]
                  : ["none"]
              }
            />
          </div>
        </div>
      </section>

      <div className="mt-5 rounded-xl border border-[#35517a] bg-[#101a29] p-4 text-sm text-slate-300">
        <div className="flex items-center gap-2 font-semibold text-slate-100">
          <LockKeyhole className="h-4 w-4 text-[#5d8fd8]" />
          Approval Console 边界
        </div>
        <p className="mt-2 leading-6">
          当前 Console 只做可观测和审计展示。现在已经开始记录 execution result，但它仍然是 preview-only evidence。
          真正的 approve / reject / execute 应该在后续 Policy-bound Executor 阶段实现，并写入新的 Execution Evidence。
        </p>
      </div>

      <div className="mt-5 flex flex-wrap gap-2">
        <ActionButton onClick={() => onTabChange("Action Plan")}>查看 Action Plan</ActionButton>
        <ActionButton onClick={() => onTabChange("Execution")}>查看 Execution</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Proposal")}>查看 GitOps Proposal</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Bundle")}>查看 GitOps Bundle</ActionButton>
        <ActionButton onClick={() => onTabChange("Evidence")}>查看 Evidence</ActionButton>
        <ActionButton onClick={() => onTabChange("Runbook")}>查看 Runbook</ActionButton>
      </div>
    </section>
  )
}







