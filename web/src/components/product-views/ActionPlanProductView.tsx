import {
  AlertTriangle,
  CheckCircle2,
  Eye,
  FileText,
  LockKeyhole,
  ShieldCheck,
  Sparkles,
  TerminalSquare,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import { ProductMetricCard } from "@/components/common/ProductMetricCard"
import {
  actionDisplay,
  approvalRaw,
  approvalText,
  resultDisplay,
} from "@/utils/format"
import { parseJsonResource } from "./shared"

type CandidateCommand =
  | string
  | {
      name?: string
      command?: string
      type?: string
      willExecute?: boolean
    }

type ActionPlanPayload = {
  schemaVersion?: string
  generatedAt?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  sourceExecutionMode?: string
  willExecute?: boolean
  requiresHumanApproval?: boolean
  target?: {
    namespace?: string
    rollout?: string
    analysisRun?: string
  }
  actionPlan?: {
    action?: string
    blocked?: boolean
    blockReason?: string
    candidateCommands?: CandidateCommand[]
    humanSteps?: string[]
  }
  guardrails?: Record<string, boolean | string | number | null>
}

function boolText(value: boolean) {
  return value ? "true" : "false"
}

function commandTypeLabel(type?: string) {
  if (type === "read_only") return "只读检查"
  if (type === "write_candidate_requires_human_approval") return "写操作候选 / 需人工审批"
  if (type === "write_candidate") return "写操作候选"
  return type || "unknown"
}

function normalizeCommand(command: CandidateCommand, index: number) {
  if (typeof command === "string") {
    return {
      name: `command_${index + 1}`,
      command,
      type: "unknown",
      willExecute: false,
    }
  }

  return {
    name: command.name || `command_${index + 1}`,
    command: command.command || "-",
    type: command.type || "unknown",
    willExecute: Boolean(command.willExecute),
  }
}

function ExecutionSummaryPanel({
  action,
  blocked,
  willExecute,
  requiresApproval,
  executionMode,
  sourceExecutionMode,
}: {
  action: string
  blocked: boolean
  willExecute: boolean
  requiresApproval: boolean
  executionMode?: string
  sourceExecutionMode?: string
}) {
  const message = willExecute
    ? "当前 Action Plan 标记为可执行，请先确认安全边界和人工审批状态。"
    : action === "NOOP"
      ? "当前只需要归档发布记录并继续观察，不会触发任何 Kubernetes 或 GitOps 修改。"
      : "当前仅生成安全建议和候选命令，不会自动执行写操作。需要人工确认后再处理。"

  return (
    <div className="rounded-2xl border border-cyan-100 bg-gradient-to-r from-cyan-50 to-white p-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <Badge value={action} label={actionDisplay(action)} />
            <Badge value={willExecute ? "REQUIRED" : "NOT REQUIRED"} label={willExecute ? "willExecute=true" : "willExecute=false"} />
            <Badge value={requiresApproval ? "REQUIRED" : "NOT REQUIRED"} label={requiresApproval ? "需要人工审批" : "无需人工审批"} />
            <Badge value={blocked ? "REQUIRED" : "NOT REQUIRED"} label={blocked ? "已阻断" : "未阻断"} />
          </div>
          <h4 className="mt-4 text-lg font-semibold text-slate-100">安全执行结论</h4>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-300">{message}</p>
        </div>

        <div className="grid min-w-[260px] gap-2 rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4 text-sm shadow-sm">
          <div className="flex justify-between gap-4">
            <span className="text-slate-500">executionMode</span>
            <span className="font-mono font-semibold text-slate-100">{executionMode || "-"}</span>
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-slate-500">sourceMode</span>
            <span className="font-mono font-semibold text-slate-100">{sourceExecutionMode || "-"}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

function SafetyGateMatrix({
  plan,
  blocked,
  willExecute,
  requiresApproval,
}: {
  plan: ActionPlanPayload
  blocked: boolean
  willExecute: boolean
  requiresApproval: boolean
}) {
  const guardrails = plan.guardrails ?? {}

  const gates = [
    {
      key: "willExecute",
      label: "自动执行开关",
      value: willExecute,
      expectedSafe: false,
      description: "false 表示系统只给建议，不会直接执行命令。",
    },
    {
      key: "requiresHumanApproval",
      label: "人工审批门禁",
      value: requiresApproval,
      expectedSafe: false,
      description: "true 表示存在需要人工确认的高风险动作。",
    },
    {
      key: "blocked",
      label: "动作阻断",
      value: blocked,
      expectedSafe: false,
      description: "true 表示 Action Plan 被策略明确阻断。",
    },
    {
      key: "advisoryOnly",
      label: "只读建议模式",
      value: Boolean(guardrails.advisoryOnly),
      expectedSafe: true,
      description: "true 表示当前阶段只输出建议，不做实际变更。",
    },
    {
      key: "dryRunOnly",
      label: "Dry Run 模式",
      value: Boolean(guardrails.dryRunOnly),
      expectedSafe: true,
      description: "true 表示候选动作只用于演练和审计。",
    },
    {
      key: "doesNotModifyKubernetes",
      label: "不修改 Kubernetes",
      value: Boolean(guardrails.doesNotModifyKubernetes),
      expectedSafe: true,
      description: "true 表示不会 patch/delete/rollback/promote 集群资源。",
    },
    {
      key: "doesNotModifyGitOps",
      label: "不修改 GitOps",
      value: Boolean(guardrails.doesNotModifyGitOps),
      expectedSafe: true,
      description: "true 表示不会 commit、push 或改变 Git 期望状态。",
    },
    {
      key: "doesNotRollback",
      label: "不自动回滚",
      value: Boolean(guardrails.doesNotRollback),
      expectedSafe: true,
      description: "true 表示 rollback 只作为候选建议，不会自动触发。",
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
            <p className={`mt-2 font-mono text-lg font-bold ${isSafe ? "text-emerald-300" : "text-amber-300"}`}>
              {boolText(gate.value)}
            </p>
            <p className={`mt-2 text-xs leading-5 ${isSafe ? "text-emerald-300" : "text-amber-300"}`}>
              {gate.description}
            </p>
          </div>
        )
      })}
    </div>
  )
}

function HumanStepsPanel({ steps }: { steps?: string[] }) {
  const items = steps ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4 text-sm text-slate-400">
        当前 Action Plan 没有人工步骤。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">人工处理步骤</h4>
      </div>
      <div className="divide-y divide-[#1f2b3d]">
        {items.map((step, index) => (
          <div key={`${index}-${step}`} className="flex gap-3 px-4 py-3 text-sm">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[#031a41] text-xs font-semibold text-white">
              {index + 1}
            </span>
            <span className="leading-6 text-slate-300">{step}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function CandidateCommandsPanel({ commands }: { commands?: CandidateCommand[] }) {
  const items = (commands ?? []).map(normalizeCommand)

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-emerald-900/45 bg-emerald-950/20 p-4 text-sm text-emerald-300">
        当前 Action Plan 没有候选命令，说明本次发布无需人工执行命令。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-amber-900/45 bg-amber-950/20 p-4">
      <div className="flex flex-col gap-1 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-sm font-semibold text-amber-200">候选命令</h4>
          <p className="mt-1 text-xs text-amber-300">
            这些命令只作为 Runbook 参考，前端不会执行；写操作候选必须由人工在终端确认。
          </p>
        </div>
        <Badge value="NOT REQUIRED" label={`${items.length} commands`} />
      </div>

      <div className="mt-4 space-y-3">
        {items.map((item) => (
          <div key={`${item.name}-${item.command}`} className="rounded-lg border border-amber-900/45 bg-[#0b121d] p-4">
            <div className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="font-mono text-sm font-semibold text-slate-100">{item.name}</p>
                <p className="mt-1 text-xs text-slate-500">{commandTypeLabel(item.type)}</p>
              </div>
              <Badge
                value={item.willExecute ? "REQUIRED" : "NOT REQUIRED"}
                label={item.willExecute ? "willExecute=true" : "willExecute=false"}
              />
            </div>
            <pre className="mt-3 overflow-auto rounded-lg bg-[#031a41] p-4 text-xs leading-6 text-cyan-50">
              {item.command}
            </pre>
          </div>
        ))}
      </div>
    </div>
  )
}

function RawGuardrailsPanel({ guardrails }: { guardrails?: Record<string, boolean | string | number | null> }) {
  const entries = Object.entries(guardrails ?? {})

  if (entries.length === 0) {
    return (
      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4 text-sm text-slate-400">
        当前 Action Plan 没有 guardrails 字段。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d]">
      <div className="border-b border-[#1f2b3d] bg-[#070b12] px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-100">原始安全护栏字段</h4>
      </div>
      <div className="grid gap-3 p-4 md:grid-cols-2">
        {entries.map(([key, value]) => (
          <div key={key} className="rounded-lg border border-[#1f2b3d] bg-[#070b12] p-3">
            <p className="break-all font-mono text-xs text-slate-500">{key}</p>
            <p className="mt-2 font-mono text-sm font-semibold text-slate-100">{String(value)}</p>
          </div>
        ))}
      </div>
    </div>
  )
}

export function ActionPlanProductView({ body }: { body: string }) {
  const plan = parseJsonResource<ActionPlanPayload>(body)

  if (!plan) {
    return (
      <div className="rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-300">
        Action Plan JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const action = plan.actionPlan?.action ?? plan.finalAction ?? "-"
  const blocked = Boolean(plan.actionPlan?.blocked)
  const willExecute = Boolean(plan.willExecute)
  const requiresApproval = Boolean(plan.requiresHumanApproval)

  return (
    <div className="space-y-5 rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-5">
      <div className="flex flex-col gap-3 border-b border-[#1f2b3d] pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-slate-100">Action Plan 安全执行视图</h4>
          <p className="mt-1 text-sm text-slate-400">
            重点回答：当前建议做什么、是否允许执行、为什么不会自动执行，以及人工应该如何处理。
          </p>
        </div>
        <Badge value={action} label={actionDisplay(action)} />
      </div>

      <ExecutionSummaryPanel
        action={action}
        blocked={blocked}
        willExecute={willExecute}
        requiresApproval={requiresApproval}
        executionMode={plan.executionMode}
        sourceExecutionMode={plan.sourceExecutionMode}
      />

      <section className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="建议动作"
          value={actionDisplay(action)}
          rawValue={action}
          icon={TerminalSquare}
          hint="Action Plan 给出的动作建议"
          statusValue={action}
        />
        <ProductMetricCard
          label="执行状态"
          value={willExecute ? "会执行" : "不会执行"}
          rawValue={`willExecute=${boolText(willExecute)}`}
          icon={LockKeyhole}
          hint="当前阶段前端和 Watcher 都不直接执行写操作"
          statusValue={willExecute ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="人工门禁"
          value={approvalText(requiresApproval)}
          rawValue={approvalRaw(requiresApproval)}
          icon={ShieldCheck}
          hint="是否需要人工确认后再处理"
          statusValue={approvalRaw(requiresApproval)}
        />
        <ProductMetricCard
          label="阻断状态"
          value={blocked ? "已阻断" : "未阻断"}
          rawValue={plan.actionPlan?.blockReason || "NO_BLOCK_REASON"}
          icon={AlertTriangle}
          hint={plan.actionPlan?.blockReason || "当前没有阻断原因"}
          statusValue={blocked ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="执行模式"
          value={plan.executionMode ?? "-"}
          rawValue={plan.sourceExecutionMode}
          icon={Sparkles}
          hint="dry_run / advisory_only 等安全模式"
          statusValue={plan.executionMode ?? "-"}
        />
        <ProductMetricCard
          label="发布结果引用"
          value={resultDisplay(plan.releaseResult ?? "-")}
          rawValue={plan.policyDecision}
          icon={CheckCircle2}
          hint="这里只是引用 Evidence 结论，不作为本页重点"
          statusValue={plan.releaseResult ?? "-"}
        />
      </section>

      <section className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-100">安全门禁矩阵</h4>
        <SafetyGateMatrix
          plan={plan}
          blocked={blocked}
          willExecute={willExecute}
          requiresApproval={requiresApproval}
        />
      </section>

      <section className="grid gap-4 lg:grid-cols-[0.85fr_1.15fr]">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-100">目标对象</h4>
          <KeyValueRows
            rows={[
              ["namespace", plan.target?.namespace ?? "-"],
              ["rollout", plan.target?.rollout ?? "-"],
              ["analysisRun", plan.target?.analysisRun ?? "-"],
              ["generatedAt", plan.generatedAt ?? "-"],
              ["schemaVersion", plan.schemaVersion ?? "-"],
            ]}
          />
        </div>

        <HumanStepsPanel steps={plan.actionPlan?.humanSteps} />
      </section>

      <CandidateCommandsPanel commands={plan.actionPlan?.candidateCommands} />

      <section className="space-y-3">
        <div className="flex items-center gap-2">
          <FileText className="h-4 w-4 text-slate-500" />
          <h4 className="text-sm font-semibold text-slate-100">安全护栏审计</h4>
        </div>
        <RawGuardrailsPanel guardrails={plan.guardrails} />
      </section>

      <div className="rounded-xl border border-[#1f2b3d] bg-[#070b12] p-4 text-sm text-slate-400">
        <div className="flex items-center gap-2 font-semibold text-slate-100">
          <Eye className="h-4 w-4" />
          只读边界说明
        </div>
        <p className="mt-2 leading-6">
          本视图只展示 Action Plan 和候选命令，不提供执行按钮。任何 rollback、abort、promote、patch、delete 或 GitOps 修改，都需要人工离开前端后在受控终端环境中执行。
        </p>
      </div>
    </div>
  )
}

