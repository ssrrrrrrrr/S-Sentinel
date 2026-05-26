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

type GitopsHandoffBundleRef = {
  gitopsHandoffBundleId?: string
  handoffStatus?: string
  bundleDir?: string
  branchName?: string
  materializedFileCount?: number
  patchEntryCount?: number
  handoffChecklistCount?: number
}

type GitopsAdapterRequestRef = {
  gitopsAdapterRequestId?: string
  requestStatus?: string
  adapterType?: string
  requestedOperation?: string
  branchName?: string
  handoffFileCount?: number
}

type GitopsAdapterResultRef = {
  gitopsAdapterResultId?: string
  deliveryStatus?: string
  adapterType?: string
  requestedOperation?: string
  branchName?: string
  outputFileCount?: number
}

type GitopsAdapterDeliveryRef = {
  gitopsAdapterDeliveryId?: string
  deliveryStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  copiedFileCount?: number
}

type GitopsAdapterRunRef = {
  gitopsAdapterRunId?: string
  runStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  workspaceFileCount?: number
}

type GitopsAdapterPickupRef = {
  gitopsAdapterPickupId?: string
  pickupStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceFileCount?: number
  nextCheckpoint?: string
  nextActor?: string
}

type GitopsAdapterPickupAckRef = {
  gitopsAdapterPickupAckId?: string
  ackStatus?: string
  pickupStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  nextCheckpoint?: string
  assignedActor?: string
}

type GitopsAdapterHandoffStateRef = {
  gitopsAdapterHandoffStateId?: string
  stateStatus?: string
  ackStatus?: string
  pickupStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  currentCheckpoint?: string
  nextCheckpoint?: string
  currentActor?: string
  nextActor?: string
}

type GitopsAdapterPickupEventRef = {
  gitopsAdapterPickupEventId?: string
  eventStatus?: string
  handoffStateStatus?: string
  pickupStatus?: string
  ackStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  currentCheckpoint?: string
  nextCheckpoint?: string
  currentActor?: string
  nextActor?: string
  expectedEvent?: string
  allowedEvents?: string[]
}

type GitopsAdapterPickupTransitionRef = {
  gitopsAdapterPickupTransitionId?: string
  transitionStatus?: string
  eventStatus?: string
  handoffStateStatus?: string
  pickupStatus?: string
  ackStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  requestedEvent?: string
  selectedEvent?: string
  responseSource?: string
  resultingStateStatus?: string
  currentCheckpoint?: string
  nextCheckpoint?: string
  currentActor?: string
  nextActor?: string
  allowedEvents?: string[]
}

type GitopsAdapterHandoffPrepRef = {
  gitopsAdapterHandoffPrepId?: string
  prepStatus?: string
  transitionStatus?: string
  eventStatus?: string
  handoffStateStatus?: string
  resultingStateStatus?: string
  pickupStatus?: string
  ackStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  selectedEvent?: string
  responseSource?: string
  currentCheckpoint?: string
  nextCheckpoint?: string
  currentActor?: string
  nextActor?: string
  preparedArtifactCount?: number
  prepChecklist?: string[]
}

type GitopsAdapterHandoffProgressRef = {
  gitopsAdapterHandoffProgressId?: string
  progressStatus?: string
  prepStatus?: string
  transitionStatus?: string
  eventStatus?: string
  handoffStateStatus?: string
  resultingStateStatus?: string
  pickupStatus?: string
  ackStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  selectedEvent?: string
  selectedAction?: string
  actionSource?: string
  currentCheckpoint?: string
  nextCheckpoint?: string
  currentActor?: string
  nextActor?: string
  workspaceArtifactCount?: number
}

type GitopsAdapterPayloadRef = {
  gitopsAdapterPayloadId?: string
  payloadStatus?: string
  progressStatus?: string
  branchName?: string
  requestedOperation?: string
  workspaceDir?: string
  bundleDir?: string
  patchEntryCount?: number
  handoffFileCount?: number
  workspaceArtifactCount?: number
}

type GitopsAdapterDispatchRef = {
  gitopsAdapterDispatchId?: string
  dispatchStatus?: string
  payloadStatus?: string
  branchName?: string
  requestedOperation?: string
  payloadDir?: string
  payloadManifestPath?: string
  commitPayloadPath?: string
  providerRequestPath?: string
  patchEntryCount?: number
  workspaceArtifactCount?: number
}

type GitopsAdapterProviderRequestRef = {
  gitopsAdapterProviderRequestId?: string
  requestStatus?: string
  providerType?: string
  branchName?: string
  requestedOperation?: string
  payloadManifestPath?: string
  commitPayloadPath?: string
  providerRequestPath?: string
  pullRequestTitle?: string
  patchEntryCount?: number
  workspaceArtifactCount?: number
}

type GitopsAdapterProviderResultRef = {
  gitopsAdapterProviderResultId?: string
  resultStatus?: string
  providerType?: string
  branchName?: string
  requestedOperation?: string
  packageDir?: string
  packageManifestPath?: string
  providerRequestPath?: string
  patchEntryCount?: number
  workspaceArtifactCount?: number
  materializedFileCount?: number
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
    gitopsHandoffBundle?: GitopsHandoffBundleRef
    gitopsAdapterRequest?: GitopsAdapterRequestRef
    gitopsAdapterResult?: GitopsAdapterResultRef
    gitopsAdapterDelivery?: GitopsAdapterDeliveryRef
    gitopsAdapterRun?: GitopsAdapterRunRef
    gitopsAdapterPickup?: GitopsAdapterPickupRef
    gitopsAdapterPickupAck?: GitopsAdapterPickupAckRef
    gitopsAdapterHandoffState?: GitopsAdapterHandoffStateRef
    gitopsAdapterPickupEvent?: GitopsAdapterPickupEventRef
    gitopsAdapterPickupTransition?: GitopsAdapterPickupTransitionRef
    gitopsAdapterHandoffPrep?: GitopsAdapterHandoffPrepRef
    gitopsAdapterHandoffProgress?: GitopsAdapterHandoffProgressRef
    gitopsAdapterPayload?: GitopsAdapterPayloadRef
    gitopsAdapterDispatch?: GitopsAdapterDispatchRef
    gitopsAdapterProviderRequest?: GitopsAdapterProviderRequestRef
    gitopsAdapterProviderResult?: GitopsAdapterProviderResultRef
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
  const gitopsHandoffBundle = refs.gitopsHandoffBundle
  const gitopsAdapterRequest = refs.gitopsAdapterRequest
  const gitopsAdapterResult = refs.gitopsAdapterResult
  const gitopsAdapterDelivery = refs.gitopsAdapterDelivery
  const gitopsAdapterRun = refs.gitopsAdapterRun
  const gitopsAdapterPickup = refs.gitopsAdapterPickup
  const gitopsAdapterPickupAck = refs.gitopsAdapterPickupAck
  const gitopsAdapterHandoffState = refs.gitopsAdapterHandoffState
  const gitopsAdapterPickupEvent = refs.gitopsAdapterPickupEvent
  const gitopsAdapterPickupTransition = refs.gitopsAdapterPickupTransition
  const gitopsAdapterHandoffPrep = refs.gitopsAdapterHandoffPrep
  const gitopsAdapterHandoffProgress = refs.gitopsAdapterHandoffProgress
  const gitopsAdapterPayload = refs.gitopsAdapterPayload
  const gitopsAdapterDispatch = refs.gitopsAdapterDispatch
  const gitopsAdapterProviderRequest = refs.gitopsAdapterProviderRequest
  const gitopsAdapterProviderResult = refs.gitopsAdapterProviderResult
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
  const gitopsHandoffStatus = gitopsHandoffBundle?.handoffStatus ?? gitopsBundleStatus
  const gitopsHandoffFileCount = gitopsHandoffBundle?.materializedFileCount ?? 0
  const gitopsAdapterStatus = gitopsAdapterRequest?.requestStatus ?? gitopsHandoffStatus
  const gitopsDeliveryStatus = gitopsAdapterResult?.deliveryStatus ?? gitopsAdapterStatus
  const gitopsDeliveryFileCount = gitopsAdapterResult?.outputFileCount ?? gitopsHandoffFileCount
  const gitopsWorkspaceStatus = gitopsAdapterDelivery?.deliveryStatus ?? gitopsDeliveryStatus
  const gitopsWorkspaceFileCount = gitopsAdapterDelivery?.copiedFileCount ?? gitopsDeliveryFileCount
  const gitopsRunStatus = gitopsAdapterRun?.runStatus ?? gitopsWorkspaceStatus
  const gitopsRunFileCount = gitopsAdapterRun?.workspaceFileCount ?? gitopsWorkspaceFileCount
  const gitopsPickupStatus = gitopsAdapterPickup?.pickupStatus ?? gitopsRunStatus
  const gitopsPickupFileCount = gitopsAdapterPickup?.workspaceFileCount ?? gitopsRunFileCount
  const gitopsPickupAckStatus = gitopsAdapterPickupAck?.ackStatus ?? gitopsPickupStatus
  const gitopsHandoffStateStatus = gitopsAdapterHandoffState?.stateStatus ?? gitopsPickupAckStatus
  const gitopsPickupEventStatus = gitopsAdapterPickupEvent?.eventStatus ?? gitopsHandoffStateStatus
  const gitopsPickupTransitionStatus = gitopsAdapterPickupTransition?.transitionStatus ?? gitopsPickupEventStatus
  const gitopsHandoffPrepStatus = gitopsAdapterHandoffPrep?.prepStatus ?? gitopsPickupTransitionStatus
  const gitopsHandoffProgressStatus = gitopsAdapterHandoffProgress?.progressStatus ?? gitopsHandoffPrepStatus
  const gitopsPayloadStatus = gitopsAdapterPayload?.payloadStatus ?? gitopsHandoffProgressStatus
  const gitopsDispatchStatus = gitopsAdapterDispatch?.dispatchStatus ?? gitopsPayloadStatus
  const gitopsProviderRequestStatus =
    gitopsAdapterProviderRequest?.requestStatus ?? gitopsDispatchStatus
  const gitopsProviderResultStatus =
    gitopsAdapterProviderResult?.resultStatus ?? gitopsProviderRequestStatus

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
      label: "GitOps Handoff",
      value: valueOrDash(gitopsHandoffBundle?.gitopsHandoffBundleId),
      hint: `files=${gitopsHandoffFileCount}`,
      status: gitopsHandoffStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Adapter",
      value: valueOrDash(gitopsAdapterRequest?.gitopsAdapterRequestId),
      hint: `adapter=${valueOrDash(gitopsAdapterRequest?.adapterType)}`,
      status: gitopsAdapterStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Delivery",
      value: valueOrDash(gitopsAdapterResult?.gitopsAdapterResultId),
      hint: `files=${gitopsDeliveryFileCount}`,
      status: gitopsDeliveryStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Workspace",
      value: valueOrDash(gitopsAdapterDelivery?.gitopsAdapterDeliveryId),
      hint: `copiedFiles=${gitopsWorkspaceFileCount}`,
      status: gitopsWorkspaceStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Run",
      value: valueOrDash(gitopsAdapterRun?.gitopsAdapterRunId),
      hint: `workspaceFiles=${gitopsRunFileCount}`,
      status: gitopsRunStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Pickup",
      value: valueOrDash(gitopsAdapterPickup?.gitopsAdapterPickupId),
      hint: `workspaceFiles=${gitopsPickupFileCount}`,
      status: gitopsPickupStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Pickup Ack",
      value: valueOrDash(gitopsAdapterPickupAck?.gitopsAdapterPickupAckId),
      hint: `nextCheckpoint=${valueOrDash(gitopsAdapterPickupAck?.nextCheckpoint)}`,
      status: gitopsPickupAckStatus,
      icon: UserCheck,
    },
    {
      label: "GitOps Handoff State",
      value: valueOrDash(gitopsAdapterHandoffState?.gitopsAdapterHandoffStateId),
      hint: `nextCheckpoint=${valueOrDash(gitopsAdapterHandoffState?.nextCheckpoint)}`,
      status: gitopsHandoffStateStatus,
      icon: Route,
    },
    {
      label: "GitOps Pickup Event",
      value: valueOrDash(gitopsAdapterPickupEvent?.gitopsAdapterPickupEventId),
      hint: `expectedEvent=${valueOrDash(gitopsAdapterPickupEvent?.expectedEvent)}`,
      status: gitopsPickupEventStatus,
      icon: Route,
    },
    {
      label: "GitOps Pickup Transition",
      value: valueOrDash(gitopsAdapterPickupTransition?.gitopsAdapterPickupTransitionId),
      hint: `selectedEvent=${valueOrDash(gitopsAdapterPickupTransition?.selectedEvent)}`,
      status: gitopsPickupTransitionStatus,
      icon: Route,
    },
    {
      label: "GitOps Handoff Prep",
      value: valueOrDash(gitopsAdapterHandoffPrep?.gitopsAdapterHandoffPrepId),
      hint: `prepStatus=${valueOrDash(gitopsHandoffPrepStatus)}`,
      status: gitopsHandoffPrepStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Handoff Progress",
      value: valueOrDash(gitopsAdapterHandoffProgress?.gitopsAdapterHandoffProgressId),
      hint: `progressStatus=${valueOrDash(gitopsHandoffProgressStatus)}`,
      status: gitopsHandoffProgressStatus,
      icon: Route,
    },
    {
      label: "GitOps Payload",
      value: valueOrDash(gitopsAdapterPayload?.gitopsAdapterPayloadId),
      hint: `payloadStatus=${valueOrDash(gitopsPayloadStatus)}`,
      status: gitopsPayloadStatus,
      icon: FileCheck2,
    },
    {
      label: "GitOps Dispatch",
      value: valueOrDash(gitopsAdapterDispatch?.gitopsAdapterDispatchId),
      hint: `dispatchStatus=${valueOrDash(gitopsDispatchStatus)}`,
      status: gitopsDispatchStatus,
      icon: Route,
    },
    {
      label: "Provider Request",
      value: valueOrDash(gitopsAdapterProviderRequest?.gitopsAdapterProviderRequestId),
      hint: `requestStatus=${valueOrDash(gitopsProviderRequestStatus)}`,
      status: gitopsProviderRequestStatus,
      icon: Route,
    },
    {
      label: "Provider Result",
      value: valueOrDash(gitopsAdapterProviderResult?.gitopsAdapterProviderResultId),
      hint: `resultStatus=${valueOrDash(gitopsProviderResultStatus)}`,
      status: gitopsProviderResultStatus,
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
    {
      title: "GitOps Handoff Bundle",
      description: gitopsHandoffBundle?.gitopsHandoffBundleId
        ? `GitOps handoff 已生成：${gitopsHandoffBundle.gitopsHandoffBundleId}，现在已经落地了可交接文件，但依然不会写仓库或调用外部系统。`
        : "当前 evidence 里还没有 materialized handoff bundle，后续人工接手时还缺少真正的交接材料目录。",
      status: gitopsHandoffBundle?.gitopsHandoffBundleId ? gitopsHandoffStatus : "MISSING",
      icon: FileCheck2,
    },
    {
      title: "GitOps Adapter Request",
      description: gitopsAdapterRequest?.gitopsAdapterRequestId
        ? `GitOps adapter request 已生成：${gitopsAdapterRequest.gitopsAdapterRequestId}，它把 handoff 包收口成了未来 adapter 可直接消费的标准输入。`
        : "当前 evidence 里还没有 adapter-ready request，后续真实 GitOps adapter 还缺少稳定输入对象。",
      status: gitopsAdapterRequest?.gitopsAdapterRequestId ? gitopsAdapterStatus : "MISSING",
      icon: FileCheck2,
    },
    {
      title: "GitOps Delivery Receipt",
      description: gitopsAdapterResult?.gitopsAdapterResultId
        ? `GitOps delivery receipt 已生成：${gitopsAdapterResult.gitopsAdapterResultId}，说明本地 adapter 已接收请求并记录了交付结果，但仍不会外发到 Git 平台。`
        : "当前 evidence 里还没有 adapter delivery receipt，执行器虽然已有输入对象，但还缺少已接单的标准回执。",
      status: gitopsAdapterResult?.gitopsAdapterResultId ? gitopsDeliveryStatus : "MISSING",
      icon: FileCheck2,
    },
    {
      title: "GitOps Delivery Workspace",
      description: gitopsAdapterDelivery?.gitopsAdapterDeliveryId
        ? `GitOps workspace 已生成：${gitopsAdapterDelivery.gitopsAdapterDeliveryId}，说明 adapter 已经准备好本地 pickup 目录，后续可以由人工或受控 adapter 接手。`
        : "当前 evidence 里还没有 delivery workspace，说明 adapter 还没有把 handoff 文件整理成可接手的本地工作区。",
      status: gitopsAdapterDelivery?.gitopsAdapterDeliveryId ? gitopsWorkspaceStatus : "MISSING",
      icon: FileCheck2,
    },
    {
      title: "GitOps Adapter Payload",
      description: gitopsAdapterPayload?.gitopsAdapterPayloadId
        ? `GitOps payload 已生成：${gitopsAdapterPayload.gitopsAdapterPayloadId}，说明进入外部自动化前的 commit-ready 载荷已经收口完成，后续真实 adapter 可以稳定消费它。`
        : "当前 evidence 里还没有 adapter payload，说明进入外部自动化前的最终载荷还没有形成稳定对象。",
      status: gitopsAdapterPayload?.gitopsAdapterPayloadId ? gitopsPayloadStatus : "MISSING",
      icon: FileCheck2,
    },
    {
      title: "External Adapter Stub Dispatch",
      description: gitopsAdapterDispatch?.gitopsAdapterDispatchId
        ? `External adapter stub dispatch 已生成：${gitopsAdapterDispatch.gitopsAdapterDispatchId}，说明平台已经开始产出面向真实 Git provider adapter 的交付回执，但仍然没有真正创建分支或 PR。`
        : "当前 evidence 里还没有 external adapter stub dispatch，说明平台还没有进入面向外部 GitOps adapter 的交付阶段。",
      status: gitopsAdapterDispatch?.gitopsAdapterDispatchId ? gitopsDispatchStatus : "MISSING",
      icon: Route,
    },
    {
      title: "Provider-ready PR Request",
      description: gitopsAdapterProviderRequest?.gitopsAdapterProviderRequestId
        ? `Provider-ready request 已生成：${gitopsAdapterProviderRequest.gitopsAdapterProviderRequestId}，现在已经能把 dispatch 收口成面向 Git provider adapter 的 PR 请求载荷，但仍然没有真正 push 分支或创建 PR。`
        : "当前 evidence 里还没有 provider-ready PR request，说明平台还没有把 dispatch 进一步收口成面向外部 Git provider 的请求对象。",
      status: gitopsAdapterProviderRequest?.gitopsAdapterProviderRequestId
        ? gitopsProviderRequestStatus
        : "MISSING",
      icon: Route,
    },
    {
      title: "Provider-ready PR Result",
      description: gitopsAdapterProviderResult?.gitopsAdapterProviderResultId
        ? `Provider-ready result 已生成：${gitopsAdapterProviderResult.gitopsAdapterProviderResultId}，说明平台已经把 provider request 落成了本地 PR-ready package 和交付回执，后续真实 provider adapter 只需要接手这个结果对象。`
        : "当前 evidence 里还没有 provider-ready result，说明 provider request 之后的本地 PR package 还没有真正落地完成。",
      status: gitopsAdapterProviderResult?.gitopsAdapterProviderResultId
        ? gitopsProviderResultStatus
        : "MISSING",
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
                ["gitopsHandoffBundleId", valueOrDash(gitopsHandoffBundle?.gitopsHandoffBundleId)],
                ["gitopsHandoffStatus", valueOrDash(gitopsHandoffStatus)],
                ["gitopsHandoffDir", valueOrDash(gitopsHandoffBundle?.bundleDir)],
                ["gitopsAdapterRequestId", valueOrDash(gitopsAdapterRequest?.gitopsAdapterRequestId)],
                ["gitopsAdapterStatus", valueOrDash(gitopsAdapterStatus)],
                ["gitopsAdapterType", valueOrDash(gitopsAdapterRequest?.adapterType)],
                ["gitopsAdapterResultId", valueOrDash(gitopsAdapterResult?.gitopsAdapterResultId)],
                ["gitopsDeliveryStatus", valueOrDash(gitopsDeliveryStatus)],
                ["gitopsDeliveryAdapterType", valueOrDash(gitopsAdapterResult?.adapterType)],
                ["gitopsAdapterDeliveryId", valueOrDash(gitopsAdapterDelivery?.gitopsAdapterDeliveryId)],
                ["gitopsWorkspaceStatus", valueOrDash(gitopsWorkspaceStatus)],
                ["gitopsWorkspaceDir", valueOrDash(gitopsAdapterDelivery?.workspaceDir)],
                ["gitopsAdapterRunId", valueOrDash(gitopsAdapterRun?.gitopsAdapterRunId)],
                ["gitopsRunStatus", valueOrDash(gitopsRunStatus)],
                ["gitopsRunWorkspaceDir", valueOrDash(gitopsAdapterRun?.workspaceDir)],
                ["gitopsAdapterPickupId", valueOrDash(gitopsAdapterPickup?.gitopsAdapterPickupId)],
                ["gitopsPickupStatus", valueOrDash(gitopsPickupStatus)],
                ["gitopsPickupCheckpoint", valueOrDash(gitopsAdapterPickup?.nextCheckpoint)],
                ["gitopsPickupActor", valueOrDash(gitopsAdapterPickup?.nextActor)],
                ["gitopsAdapterPickupAckId", valueOrDash(gitopsAdapterPickupAck?.gitopsAdapterPickupAckId)],
                ["gitopsPickupAckStatus", valueOrDash(gitopsPickupAckStatus)],
                ["gitopsPickupAckCheckpoint", valueOrDash(gitopsAdapterPickupAck?.nextCheckpoint)],
                ["gitopsPickupAckActor", valueOrDash(gitopsAdapterPickupAck?.assignedActor)],
                ["gitopsAdapterHandoffStateId", valueOrDash(gitopsAdapterHandoffState?.gitopsAdapterHandoffStateId)],
                ["gitopsHandoffStateStatus", valueOrDash(gitopsHandoffStateStatus)],
                ["gitopsHandoffCurrentCheckpoint", valueOrDash(gitopsAdapterHandoffState?.currentCheckpoint)],
                ["gitopsHandoffNextCheckpoint", valueOrDash(gitopsAdapterHandoffState?.nextCheckpoint)],
                ["gitopsHandoffCurrentActor", valueOrDash(gitopsAdapterHandoffState?.currentActor)],
                ["gitopsHandoffNextActor", valueOrDash(gitopsAdapterHandoffState?.nextActor)],
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
                ["gitopsHandoffBundleId", valueOrDash(gitopsHandoffBundle?.gitopsHandoffBundleId)],
                ["gitopsHandoffStatus", valueOrDash(gitopsHandoffStatus)],
                ["gitopsHandoffDir", valueOrDash(gitopsHandoffBundle?.bundleDir)],
                ["gitopsHandoffFileCount", valueOrDash(gitopsHandoffFileCount)],
                ["gitopsAdapterRequestId", valueOrDash(gitopsAdapterRequest?.gitopsAdapterRequestId)],
                ["gitopsAdapterStatus", valueOrDash(gitopsAdapterStatus)],
                ["gitopsAdapterType", valueOrDash(gitopsAdapterRequest?.adapterType)],
                ["gitopsRequestedOperation", valueOrDash(gitopsAdapterRequest?.requestedOperation)],
                ["gitopsAdapterResultId", valueOrDash(gitopsAdapterResult?.gitopsAdapterResultId)],
                ["gitopsDeliveryStatus", valueOrDash(gitopsDeliveryStatus)],
                ["gitopsDeliveryBranch", valueOrDash(gitopsAdapterResult?.branchName)],
                ["gitopsDeliveryFileCount", valueOrDash(gitopsDeliveryFileCount)],
                ["gitopsAdapterDeliveryId", valueOrDash(gitopsAdapterDelivery?.gitopsAdapterDeliveryId)],
                ["gitopsWorkspaceStatus", valueOrDash(gitopsWorkspaceStatus)],
                ["gitopsWorkspaceDir", valueOrDash(gitopsAdapterDelivery?.workspaceDir)],
                ["gitopsWorkspaceFileCount", valueOrDash(gitopsWorkspaceFileCount)],
                ["gitopsAdapterRunId", valueOrDash(gitopsAdapterRun?.gitopsAdapterRunId)],
                ["gitopsRunStatus", valueOrDash(gitopsRunStatus)],
                ["gitopsRunWorkspaceDir", valueOrDash(gitopsAdapterRun?.workspaceDir)],
                ["gitopsRunFileCount", valueOrDash(gitopsRunFileCount)],
                ["gitopsAdapterPickupId", valueOrDash(gitopsAdapterPickup?.gitopsAdapterPickupId)],
                ["gitopsPickupStatus", valueOrDash(gitopsPickupStatus)],
                ["gitopsPickupCheckpoint", valueOrDash(gitopsAdapterPickup?.nextCheckpoint)],
                ["gitopsPickupActor", valueOrDash(gitopsAdapterPickup?.nextActor)],
                ["gitopsPickupFileCount", valueOrDash(gitopsPickupFileCount)],
                ["gitopsAdapterPickupAckId", valueOrDash(gitopsAdapterPickupAck?.gitopsAdapterPickupAckId)],
                ["gitopsPickupAckStatus", valueOrDash(gitopsPickupAckStatus)],
                ["gitopsPickupAckCheckpoint", valueOrDash(gitopsAdapterPickupAck?.nextCheckpoint)],
                ["gitopsPickupAckActor", valueOrDash(gitopsAdapterPickupAck?.assignedActor)],
                ["gitopsPickupAckWorkspaceDir", valueOrDash(gitopsAdapterPickupAck?.workspaceDir)],
                ["gitopsAdapterHandoffStateId", valueOrDash(gitopsAdapterHandoffState?.gitopsAdapterHandoffStateId)],
                ["gitopsHandoffStateStatus", valueOrDash(gitopsHandoffStateStatus)],
                ["gitopsHandoffCurrentCheckpoint", valueOrDash(gitopsAdapterHandoffState?.currentCheckpoint)],
                ["gitopsHandoffNextCheckpoint", valueOrDash(gitopsAdapterHandoffState?.nextCheckpoint)],
                ["gitopsHandoffCurrentActor", valueOrDash(gitopsAdapterHandoffState?.currentActor)],
                ["gitopsHandoffNextActor", valueOrDash(gitopsAdapterHandoffState?.nextActor)],
                ["gitopsHandoffWorkspaceDir", valueOrDash(gitopsAdapterHandoffState?.workspaceDir)],
                ["gitopsAdapterPickupEventId", valueOrDash(gitopsAdapterPickupEvent?.gitopsAdapterPickupEventId)],
                ["gitopsPickupEventStatus", valueOrDash(gitopsPickupEventStatus)],
                ["gitopsPickupEventExpectedEvent", valueOrDash(gitopsAdapterPickupEvent?.expectedEvent)],
                ["gitopsPickupEventCurrentCheckpoint", valueOrDash(gitopsAdapterPickupEvent?.currentCheckpoint)],
                ["gitopsPickupEventNextCheckpoint", valueOrDash(gitopsAdapterPickupEvent?.nextCheckpoint)],
                ["gitopsPickupEventCurrentActor", valueOrDash(gitopsAdapterPickupEvent?.currentActor)],
                ["gitopsPickupEventNextActor", valueOrDash(gitopsAdapterPickupEvent?.nextActor)],
                ["gitopsPickupEventWorkspaceDir", valueOrDash(gitopsAdapterPickupEvent?.workspaceDir)],
                ["gitopsPickupEventAllowedEvents", valueOrDash((gitopsAdapterPickupEvent?.allowedEvents ?? []).join(", "))],
                ["gitopsAdapterPickupTransitionId", valueOrDash(gitopsAdapterPickupTransition?.gitopsAdapterPickupTransitionId)],
                ["gitopsPickupTransitionStatus", valueOrDash(gitopsPickupTransitionStatus)],
                ["gitopsPickupTransitionRequestedEvent", valueOrDash(gitopsAdapterPickupTransition?.requestedEvent)],
                ["gitopsPickupTransitionSelectedEvent", valueOrDash(gitopsAdapterPickupTransition?.selectedEvent)],
                ["gitopsPickupTransitionResponseSource", valueOrDash(gitopsAdapterPickupTransition?.responseSource)],
                ["gitopsPickupTransitionResultingState", valueOrDash(gitopsAdapterPickupTransition?.resultingStateStatus)],
                ["gitopsPickupTransitionCurrentCheckpoint", valueOrDash(gitopsAdapterPickupTransition?.currentCheckpoint)],
                ["gitopsPickupTransitionNextCheckpoint", valueOrDash(gitopsAdapterPickupTransition?.nextCheckpoint)],
                ["gitopsPickupTransitionCurrentActor", valueOrDash(gitopsAdapterPickupTransition?.currentActor)],
                ["gitopsPickupTransitionNextActor", valueOrDash(gitopsAdapterPickupTransition?.nextActor)],
                ["gitopsPickupTransitionWorkspaceDir", valueOrDash(gitopsAdapterPickupTransition?.workspaceDir)],
                ["gitopsAdapterHandoffPrepId", valueOrDash(gitopsAdapterHandoffPrep?.gitopsAdapterHandoffPrepId)],
                ["gitopsHandoffPrepStatus", valueOrDash(gitopsHandoffPrepStatus)],
                ["gitopsHandoffPrepTransitionStatus", valueOrDash(gitopsAdapterHandoffPrep?.transitionStatus)],
                ["gitopsHandoffPrepResultingState", valueOrDash(gitopsAdapterHandoffPrep?.resultingStateStatus)],
                ["gitopsHandoffPrepCurrentCheckpoint", valueOrDash(gitopsAdapterHandoffPrep?.currentCheckpoint)],
                ["gitopsHandoffPrepNextCheckpoint", valueOrDash(gitopsAdapterHandoffPrep?.nextCheckpoint)],
                ["gitopsHandoffPrepCurrentActor", valueOrDash(gitopsAdapterHandoffPrep?.currentActor)],
                ["gitopsHandoffPrepNextActor", valueOrDash(gitopsAdapterHandoffPrep?.nextActor)],
                ["gitopsHandoffPrepPreparedArtifacts", valueOrDash(gitopsAdapterHandoffPrep?.preparedArtifactCount)],
                ["gitopsHandoffPrepWorkspaceDir", valueOrDash(gitopsAdapterHandoffPrep?.workspaceDir)],
                ["gitopsAdapterHandoffProgressId", valueOrDash(gitopsAdapterHandoffProgress?.gitopsAdapterHandoffProgressId)],
                ["gitopsHandoffProgressStatus", valueOrDash(gitopsHandoffProgressStatus)],
                ["gitopsHandoffProgressSelectedAction", valueOrDash(gitopsAdapterHandoffProgress?.selectedAction)],
                ["gitopsHandoffProgressActionSource", valueOrDash(gitopsAdapterHandoffProgress?.actionSource)],
                ["gitopsHandoffProgressCurrentCheckpoint", valueOrDash(gitopsAdapterHandoffProgress?.currentCheckpoint)],
                ["gitopsHandoffProgressNextCheckpoint", valueOrDash(gitopsAdapterHandoffProgress?.nextCheckpoint)],
                ["gitopsHandoffProgressCurrentActor", valueOrDash(gitopsAdapterHandoffProgress?.currentActor)],
                ["gitopsHandoffProgressNextActor", valueOrDash(gitopsAdapterHandoffProgress?.nextActor)],
                ["gitopsHandoffProgressWorkspaceArtifacts", valueOrDash(gitopsAdapterHandoffProgress?.workspaceArtifactCount)],
                ["gitopsHandoffProgressWorkspaceDir", valueOrDash(gitopsAdapterHandoffProgress?.workspaceDir)],
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
          <h4 className="text-sm font-semibold text-slate-100">GitOps Handoff</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `handoffStatus:${valueOrDash(gitopsHandoffStatus)}`,
                `files:${gitopsHandoffFileCount}`,
                `patchEntries:${valueOrDash(gitopsHandoffBundle?.patchEntryCount ?? gitopsBundlePatchEntryCount)}`,
                gitopsHandoffBundle?.bundleDir
                  ? `bundleDir:${gitopsHandoffBundle.bundleDir}`
                  : "bundleDir:none",
                `checklist:${valueOrDash(gitopsHandoffBundle?.handoffChecklistCount ?? 0)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Adapter</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `requestStatus:${valueOrDash(gitopsAdapterStatus)}`,
                `adapterType:${valueOrDash(gitopsAdapterRequest?.adapterType)}`,
                `operation:${valueOrDash(gitopsAdapterRequest?.requestedOperation)}`,
                gitopsAdapterRequest?.branchName
                  ? `branch:${gitopsAdapterRequest.branchName}`
                  : "branch:none",
                `handoffFiles:${valueOrDash(gitopsAdapterRequest?.handoffFileCount ?? gitopsHandoffFileCount)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Delivery</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `deliveryStatus:${valueOrDash(gitopsDeliveryStatus)}`,
                `adapterType:${valueOrDash(gitopsAdapterResult?.adapterType ?? gitopsAdapterRequest?.adapterType)}`,
                `operation:${valueOrDash(gitopsAdapterResult?.requestedOperation ?? gitopsAdapterRequest?.requestedOperation)}`,
                gitopsAdapterResult?.branchName
                  ? `branch:${gitopsAdapterResult.branchName}`
                  : "branch:none",
                `outputFiles:${valueOrDash(gitopsDeliveryFileCount)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Workspace</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `workspaceStatus:${valueOrDash(gitopsWorkspaceStatus)}`,
                gitopsAdapterDelivery?.workspaceDir
                  ? `workspaceDir:${gitopsAdapterDelivery.workspaceDir}`
                  : "workspaceDir:none",
                gitopsAdapterDelivery?.branchName
                  ? `branch:${gitopsAdapterDelivery.branchName}`
                  : "branch:none",
                `copiedFiles:${valueOrDash(gitopsWorkspaceFileCount)}`,
                `operation:${valueOrDash(gitopsAdapterDelivery?.requestedOperation ?? gitopsAdapterResult?.requestedOperation)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Run</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `runStatus:${valueOrDash(gitopsRunStatus)}`,
                gitopsAdapterRun?.workspaceDir
                  ? `workspaceDir:${gitopsAdapterRun.workspaceDir}`
                  : "workspaceDir:none",
                gitopsAdapterRun?.branchName
                  ? `branch:${gitopsAdapterRun.branchName}`
                  : "branch:none",
                `workspaceFiles:${valueOrDash(gitopsRunFileCount)}`,
                `operation:${valueOrDash(gitopsAdapterRun?.requestedOperation ?? gitopsAdapterDelivery?.requestedOperation)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Pickup</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `pickupStatus:${valueOrDash(gitopsPickupStatus)}`,
                gitopsAdapterPickup?.branchName
                  ? `branch:${gitopsAdapterPickup.branchName}`
                  : "branch:none",
                `workspaceFiles:${valueOrDash(gitopsPickupFileCount)}`,
                gitopsAdapterPickup?.nextCheckpoint
                  ? `nextCheckpoint:${gitopsAdapterPickup.nextCheckpoint}`
                  : "nextCheckpoint:none",
                gitopsAdapterPickup?.nextActor
                  ? `nextActor:${gitopsAdapterPickup.nextActor}`
                  : "nextActor:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Pickup Ack</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `ackStatus:${valueOrDash(gitopsPickupAckStatus)}`,
                gitopsAdapterPickupAck?.branchName
                  ? `branch:${gitopsAdapterPickupAck.branchName}`
                  : "branch:none",
                gitopsAdapterPickupAck?.workspaceDir
                  ? `workspaceDir:${gitopsAdapterPickupAck.workspaceDir}`
                  : "workspaceDir:none",
                gitopsAdapterPickupAck?.nextCheckpoint
                  ? `nextCheckpoint:${gitopsAdapterPickupAck.nextCheckpoint}`
                  : "nextCheckpoint:none",
                gitopsAdapterPickupAck?.assignedActor
                  ? `assignedActor:${gitopsAdapterPickupAck.assignedActor}`
                  : "assignedActor:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Handoff State</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `stateStatus:${valueOrDash(gitopsHandoffStateStatus)}`,
                gitopsAdapterHandoffState?.branchName
                  ? `branch:${gitopsAdapterHandoffState.branchName}`
                  : "branch:none",
                gitopsAdapterHandoffState?.currentCheckpoint
                  ? `currentCheckpoint:${gitopsAdapterHandoffState.currentCheckpoint}`
                  : "currentCheckpoint:none",
                gitopsAdapterHandoffState?.nextCheckpoint
                  ? `nextCheckpoint:${gitopsAdapterHandoffState.nextCheckpoint}`
                  : "nextCheckpoint:none",
                gitopsAdapterHandoffState?.nextActor
                  ? `nextActor:${gitopsAdapterHandoffState.nextActor}`
                  : "nextActor:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Pickup Event</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `eventStatus:${valueOrDash(gitopsPickupEventStatus)}`,
                gitopsAdapterPickupEvent?.expectedEvent
                  ? `expectedEvent:${gitopsAdapterPickupEvent.expectedEvent}`
                  : "expectedEvent:none",
                gitopsAdapterPickupEvent?.currentCheckpoint
                  ? `currentCheckpoint:${gitopsAdapterPickupEvent.currentCheckpoint}`
                  : "currentCheckpoint:none",
                gitopsAdapterPickupEvent?.nextCheckpoint
                  ? `nextCheckpoint:${gitopsAdapterPickupEvent.nextCheckpoint}`
                  : "nextCheckpoint:none",
                (gitopsAdapterPickupEvent?.allowedEvents ?? []).length > 0
                  ? `allowedEvents:${gitopsAdapterPickupEvent?.allowedEvents?.join("|")}`
                  : "allowedEvents:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Pickup Transition</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `transitionStatus:${valueOrDash(gitopsPickupTransitionStatus)}`,
                gitopsAdapterPickupTransition?.requestedEvent
                  ? `requestedEvent:${gitopsAdapterPickupTransition.requestedEvent}`
                  : "requestedEvent:none",
                gitopsAdapterPickupTransition?.selectedEvent
                  ? `selectedEvent:${gitopsAdapterPickupTransition.selectedEvent}`
                  : "selectedEvent:none",
                gitopsAdapterPickupTransition?.resultingStateStatus
                  ? `resultingState:${gitopsAdapterPickupTransition.resultingStateStatus}`
                  : "resultingState:none",
                gitopsAdapterPickupTransition?.responseSource
                  ? `responseSource:${gitopsAdapterPickupTransition.responseSource}`
                  : "responseSource:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Handoff Prep</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `prepStatus:${valueOrDash(gitopsHandoffPrepStatus)}`,
                gitopsAdapterHandoffPrep?.transitionStatus
                  ? `transitionStatus:${gitopsAdapterHandoffPrep.transitionStatus}`
                  : "transitionStatus:none",
                gitopsAdapterHandoffPrep?.resultingStateStatus
                  ? `resultingState:${gitopsAdapterHandoffPrep.resultingStateStatus}`
                  : "resultingState:none",
                `preparedArtifacts:${valueOrDash(gitopsAdapterHandoffPrep?.preparedArtifactCount ?? 0)}`,
                (gitopsAdapterHandoffPrep?.prepChecklist ?? []).length > 0
                  ? `prepChecklist:${gitopsAdapterHandoffPrep?.prepChecklist?.join("|")}`
                  : "prepChecklist:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Handoff Progress</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `progressStatus:${valueOrDash(gitopsHandoffProgressStatus)}`,
                gitopsAdapterHandoffProgress?.selectedAction
                  ? `selectedAction:${gitopsAdapterHandoffProgress.selectedAction}`
                  : "selectedAction:none",
                gitopsAdapterHandoffProgress?.actionSource
                  ? `actionSource:${gitopsAdapterHandoffProgress.actionSource}`
                  : "actionSource:none",
                `workspaceArtifacts:${valueOrDash(gitopsAdapterHandoffProgress?.workspaceArtifactCount ?? 0)}`,
                gitopsAdapterHandoffProgress?.nextCheckpoint
                  ? `nextCheckpoint:${gitopsAdapterHandoffProgress.nextCheckpoint}`
                  : "nextCheckpoint:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Payload</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `payloadStatus:${valueOrDash(gitopsPayloadStatus)}`,
                gitopsAdapterPayload?.branchName
                  ? `branch:${gitopsAdapterPayload.branchName}`
                  : "branch:none",
                gitopsAdapterPayload?.workspaceDir
                  ? `workspaceDir:${gitopsAdapterPayload.workspaceDir}`
                  : "workspaceDir:none",
                `patchEntries:${valueOrDash(gitopsAdapterPayload?.patchEntryCount ?? 0)}`,
                `handoffFiles:${valueOrDash(gitopsAdapterPayload?.handoffFileCount ?? 0)}`,
                `workspaceArtifacts:${valueOrDash(gitopsAdapterPayload?.workspaceArtifactCount ?? 0)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Dispatch</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `dispatchStatus:${valueOrDash(gitopsDispatchStatus)}`,
                gitopsAdapterDispatch?.branchName
                  ? `branch:${gitopsAdapterDispatch.branchName}`
                  : "branch:none",
                gitopsAdapterDispatch?.payloadDir
                  ? `payloadDir:${gitopsAdapterDispatch.payloadDir}`
                  : "payloadDir:none",
                `patchEntries:${valueOrDash(gitopsAdapterDispatch?.patchEntryCount ?? 0)}`,
                `workspaceArtifacts:${valueOrDash(gitopsAdapterDispatch?.workspaceArtifactCount ?? 0)}`,
                gitopsAdapterDispatch?.providerRequestPath
                  ? `providerRequest:${gitopsAdapterDispatch.providerRequestPath}`
                  : "providerRequest:none",
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Provider Request</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `requestStatus:${valueOrDash(gitopsProviderRequestStatus)}`,
                `providerType:${valueOrDash(gitopsAdapterProviderRequest?.providerType)}`,
                gitopsAdapterProviderRequest?.branchName
                  ? `branch:${gitopsAdapterProviderRequest.branchName}`
                  : "branch:none",
                gitopsAdapterProviderRequest?.pullRequestTitle
                  ? `prTitle:${gitopsAdapterProviderRequest.pullRequestTitle}`
                  : "prTitle:none",
                `patchEntries:${valueOrDash(gitopsAdapterProviderRequest?.patchEntryCount ?? 0)}`,
                `workspaceArtifacts:${valueOrDash(gitopsAdapterProviderRequest?.workspaceArtifactCount ?? 0)}`,
              ]}
            />
          </div>
        </div>

        <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
          <h4 className="text-sm font-semibold text-slate-100">GitOps Provider Result</h4>
          <div className="mt-3">
            <RuleChipsPanel
              rules={[
                `resultStatus:${valueOrDash(gitopsProviderResultStatus)}`,
                `providerType:${valueOrDash(gitopsAdapterProviderResult?.providerType)}`,
                gitopsAdapterProviderResult?.branchName
                  ? `branch:${gitopsAdapterProviderResult.branchName}`
                  : "branch:none",
                gitopsAdapterProviderResult?.packageDir
                  ? `packageDir:${gitopsAdapterProviderResult.packageDir}`
                  : "packageDir:none",
                `patchEntries:${valueOrDash(gitopsAdapterProviderResult?.patchEntryCount ?? 0)}`,
                `materializedFiles:${valueOrDash(gitopsAdapterProviderResult?.materializedFileCount ?? 0)}`,
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
        <ActionButton onClick={() => onTabChange("GitOps Handoff")}>查看 GitOps Handoff</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Adapter")}>查看 GitOps Adapter</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Delivery")}>查看 GitOps Delivery</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Workspace")}>查看 GitOps Workspace</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Run")}>查看 GitOps Run</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Pickup")}>查看 GitOps Pickup</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Pickup Ack")}>查看 GitOps Pickup Ack</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Handoff State")}>查看 GitOps Handoff State</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Pickup Event")}>查看 GitOps Pickup Event</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Pickup Transition")}>查看 GitOps Pickup Transition</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Handoff Prep")}>查看 GitOps Handoff Prep</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Handoff Progress")}>查看 GitOps Handoff Progress</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Provider Request")}>查看 GitOps Provider Request</ActionButton>
        <ActionButton onClick={() => onTabChange("GitOps Provider Result")}>查看 GitOps Provider Result</ActionButton>
        <ActionButton onClick={() => onTabChange("Evidence")}>查看 Evidence</ActionButton>
        <ActionButton onClick={() => onTabChange("Runbook")}>查看 Runbook</ActionButton>
      </div>
    </section>
  )
}







