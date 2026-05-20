import {
  AlertTriangle,
  CheckCircle2,
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
    candidateCommands?: string[]
    humanSteps?: string[]
  }
  guardrails?: Record<string, boolean | string | number | null>
}



function GuardrailGrid({ guardrails }: { guardrails?: Record<string, boolean | string | number | null> }) {
  const entries = Object.entries(guardrails ?? {})

  if (entries.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Action Plan 没有 guardrails 字段。
      </div>
    )
  }

  return (
    <div className="grid gap-3 md:grid-cols-2">
      {entries.map(([key, value]) => {
        const isBoolean = typeof value === "boolean"
        const valueText = String(value)
        return (
          <div key={key} className="rounded-xl border border-slate-200 bg-white p-4">
            <p className="break-all font-mono text-xs text-slate-500">{key}</p>
            <div className="mt-2">
              <span
                className={`inline-flex rounded-full border px-2.5 py-1 font-mono text-xs font-semibold ${
                  isBoolean && value === true
                    ? "border-emerald-200 bg-emerald-50 text-emerald-700"
                    : isBoolean && value === false
                      ? "border-amber-200 bg-amber-50 text-amber-700"
                      : "border-slate-200 bg-slate-50 text-slate-700"
                }`}
              >
                {valueText}
              </span>
            </div>
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
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Action Plan 没有人工步骤。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">人工处理步骤</h4>
      </div>
      <div className="divide-y divide-slate-200">
        {items.map((step, index) => (
          <div key={`${index}-${step}`} className="flex gap-3 px-4 py-3 text-sm">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[#031a41] text-xs font-semibold text-white">
              {index + 1}
            </span>
            <span className="leading-6 text-slate-700">{step}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function CandidateCommandsPanel({ commands }: { commands?: string[] }) {
  const items = commands ?? []

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        当前 Action Plan 没有候选命令，说明本次发布无需人工执行命令。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-amber-200 bg-amber-50 p-4">
      <h4 className="text-sm font-semibold text-amber-900">候选命令</h4>
      <p className="mt-1 text-xs text-amber-700">这些命令仅作为建议展示，前端不会执行。</p>
      <pre className="mt-3 overflow-auto rounded-lg bg-[#031a41] p-4 text-xs leading-6 text-cyan-50">
        {items.join("\n")}
      </pre>
    </div>
  )
}

export function ActionPlanProductView({ body }: { body: string }) {
  const plan = parseJsonResource<ActionPlanPayload>(body)

  if (!plan) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
        Action Plan JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const action = plan.actionPlan?.action ?? plan.finalAction ?? "-"
  const blocked = Boolean(plan.actionPlan?.blocked)
  const willExecute = Boolean(plan.willExecute)
  const requiresApproval = Boolean(plan.requiresHumanApproval)

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Action Plan 决策视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            将原始 action-plan JSON 提炼为 SRE 可以快速判断的执行、安全和人工门禁信息。
          </p>
        </div>
        <Badge value={action} label={actionDisplay(action)} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="最终动作"
          value={actionDisplay(action)}
          rawValue={action}
          icon={TerminalSquare}
          hint="Action Plan 建议的最终动作"
          statusValue={action}
        />
        <ProductMetricCard
          label="阻断状态"
          value={blocked ? "已阻断" : "未阻断"}
          rawValue={String(blocked)}
          icon={AlertTriangle}
          hint={plan.actionPlan?.blockReason || "当前没有阻断原因"}
          statusValue={blocked ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="是否执行"
          value={willExecute ? "会执行" : "不会执行"}
          rawValue={String(willExecute)}
          icon={LockKeyhole}
          hint="前端只读展示，不触发 Kubernetes 修改"
          statusValue={willExecute ? "REQUIRED" : "NOT REQUIRED"}
        />
        <ProductMetricCard
          label="人工审批"
          value={approvalText(requiresApproval)}
          rawValue={approvalRaw(requiresApproval)}
          icon={ShieldCheck}
          hint="Human Gate 状态"
          statusValue={approvalRaw(requiresApproval)}
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
          label="发布结果"
          value={resultDisplay(plan.releaseResult ?? "-")}
          rawValue={plan.policyDecision}
          icon={CheckCircle2}
          hint="来自 release evidence 的最终结论"
          statusValue={plan.releaseResult ?? "-"}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">目标对象</h4>
          <KeyValueRows
            rows={[
              ["namespace", plan.target?.namespace ?? "-"],
              ["rollout", plan.target?.rollout ?? "-"],
              ["analysisRun", plan.target?.analysisRun ?? "-"],
              ["generatedAt", plan.generatedAt ?? "-"],
            ]}
          />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">人工步骤</h4>
          <HumanStepsPanel steps={plan.actionPlan?.humanSteps} />
        </div>
      </section>

      <section className="space-y-3">
        <h4 className="text-sm font-semibold text-slate-900">安全护栏</h4>
        <GuardrailGrid guardrails={plan.guardrails} />
      </section>

      <CandidateCommandsPanel commands={plan.actionPlan?.candidateCommands} />
    </div>
  )
}

