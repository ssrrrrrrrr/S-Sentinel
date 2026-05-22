import { useMemo } from "react"
import type { ComponentType } from "react"
import { useQuery, type UseQueryResult } from "@tanstack/react-query"
import {
  Bot,
  Braces,
  CheckCircle2,
  FileSearch,
  Fingerprint,
  GitBranch,
  Network,
  Route,
  ShieldCheck,
  Wrench,
  AlertTriangle,
} from "lucide-react"
import {
  fetchEvidenceStoreObject,
  type EvidenceStoreJson,
} from "@/api/evidenceStore"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import {
  arrayFromPaths,
  asRecord,
  booleanFromPaths,
  parseJsonResource,
  stringFromPaths,
  stringifyValue,
  type JsonRecord,
  valueFromPaths,
} from "@/components/product-views/shared"
import type { ReleaseIndexItem } from "@/types/release"
import {
  actionDisplay,
  policyDisplay,
} from "@/utils/format"

type AgentTracePayload = {
  schemaVersion?: string
  agentTraceId?: string
  traceId?: string
  releaseId?: string
  generatedBy?: string
  generatedAt?: string
  release?: JsonRecord
  correlation?: JsonRecord
  agentRun?: JsonRecord
  policyTrace?: JsonRecord
  signedReleaseGateTrace?: JsonRecord
  toolCallTraces?: unknown[]
  evidenceTrace?: JsonRecord
  guardrails?: JsonRecord
}

type TraceEvidencePayload = {
  releaseId?: string
  traceId?: string
  agentTraceId?: string
  agentRunId?: string
  policyDecisionId?: string
  policyRuntimeResultId?: string
  signedReleaseGateId?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  decisionRefs?: {
    agentTrace?: {
      agentTraceId?: string
      traceId?: string
    }
    agentRun?: {
      agentRunId?: string
      mode?: string
      recommendedAction?: string
      priority?: string
      willExecute?: boolean
    }
    policyDecision?: {
      policyDecisionId?: string
      policyRuntimeResultId?: string
      requestedAction?: string
      allowed?: boolean
      reason?: string
    }
    signedReleaseGate?: {
      signedReleaseGateId?: string
      decision?: string
      allowed?: boolean
    }
  }
}

type TraceMetric = {
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

function shortValue(value: string, max = 56) {
  if (value.length <= max) return value
  return `${value.slice(0, 24)}…${value.slice(-20)}`
}

function statusClass(status: string) {
  const normalized = status.toLowerCase()

  if (
    normalized.includes("fail") ||
    normalized.includes("error") ||
    normalized.includes("missing") ||
    normalized.includes("required") ||
    normalized.includes("false")
  ) {
    return "border-rose-200 bg-rose-50 text-rose-700"
  }

  if (
    normalized.includes("pass") ||
    normalized.includes("linked") ||
    normalized.includes("completed") ||
    normalized.includes("true") ||
    normalized.includes("read-only")
  ) {
    return "border-emerald-200 bg-emerald-50 text-emerald-700"
  }

  return "border-cyan-200 bg-cyan-50 text-cyan-700"
}

function parseRecordCandidate(value: unknown) {
  if (typeof value === "string") {
    try {
      return asRecord(JSON.parse(value))
    } catch {
      return null
    }
  }

  return asRecord(value)
}

function normalizeTracePayload(response?: EvidenceStoreJson) {
  if (!response) return null

  const candidates: unknown[] = [
    response,
    valueFromPaths(response, [["raw"]]),
    valueFromPaths(response, [["rawJson"]]),
    valueFromPaths(response, [["raw_json"]]),
    valueFromPaths(response, [["object", "raw"]]),
    valueFromPaths(response, [["object", "rawJson"]]),
    valueFromPaths(response, [["object", "raw_json"]]),
    valueFromPaths(response, [["data", "raw"]]),
    valueFromPaths(response, [["data", "rawJson"]]),
  ]

  for (const candidate of candidates) {
    const record = parseRecordCandidate(candidate)
    if (!record) continue

    if (
      record.schemaVersion === "agent.trace/v1alpha1" ||
      typeof record.agentTraceId === "string" ||
      Array.isArray(record.toolCallTraces)
    ) {
      return record as AgentTracePayload
    }
  }

  return null
}

function fallbackTraceFromEvidence(
  evidence: TraceEvidencePayload | null,
  selected: ReleaseIndexItem,
): AgentTracePayload {
  const refs = evidence?.decisionRefs ?? {}
  const releaseId = evidence?.releaseId ?? selected.releaseId
  const agentTraceId = evidence?.agentTraceId ?? refs.agentTrace?.agentTraceId ?? `at-${releaseId}`
  const traceId = evidence?.traceId ?? refs.agentTrace?.traceId ?? `trace-${releaseId}`
  const agentRunId = evidence?.agentRunId ?? refs.agentRun?.agentRunId ?? `ar-${releaseId}`

  return {
    schemaVersion: "agent.trace/fallback-from-release-evidence",
    agentTraceId,
    traceId,
    releaseId,
    generatedBy: "portal-fallback",
    generatedAt: "-",
    correlation: {
      releaseId,
      agentRunId,
      policyDecisionId: evidence?.policyDecisionId ?? refs.policyDecision?.policyDecisionId ?? "-",
      policyRuntimeResultId: evidence?.policyRuntimeResultId ?? refs.policyDecision?.policyRuntimeResultId ?? "-",
      signedReleaseGateId: evidence?.signedReleaseGateId ?? refs.signedReleaseGate?.signedReleaseGateId ?? "-",
    },
    agentRun: {
      agentRunId,
      mode: refs.agentRun?.mode ?? "-",
      recommendedAction: refs.agentRun?.recommendedAction ?? evidence?.finalAction ?? selected.summary.finalAction,
      priority: refs.agentRun?.priority ?? selected.summary.riskLevel,
      willExecute: refs.agentRun?.willExecute ?? false,
      status: "FALLBACK",
    },
    policyTrace: {
      policyDecisionId: evidence?.policyDecisionId ?? refs.policyDecision?.policyDecisionId ?? "-",
      policyRuntimeResultId: evidence?.policyRuntimeResultId ?? refs.policyDecision?.policyRuntimeResultId ?? "-",
      policyDecision: evidence?.policyDecision ?? selected.summary.policyDecision,
      finalAction: evidence?.finalAction ?? refs.policyDecision?.requestedAction ?? selected.summary.finalAction,
      reason: refs.policyDecision?.reason ?? "AgentTrace object detail unavailable; using release evidence fallback.",
    },
    signedReleaseGateTrace: {
      signedReleaseGateId: evidence?.signedReleaseGateId ?? refs.signedReleaseGate?.signedReleaseGateId ?? "-",
      decision: refs.signedReleaseGate?.decision ?? "-",
      allowed: refs.signedReleaseGate?.allowed,
    },
    toolCallTraces: [],
    evidenceTrace: {
      releaseEvidence: "loaded",
      agentTraceObject: "fallback",
    },
    guardrails: {
      readOnly: true,
      willExecute: false,
      fallback: true,
      doesNotModifyKubernetes: true,
      doesNotModifyGitOps: true,
    },
  }
}

function TraceMetricCard({ metric }: { metric: TraceMetric }) {
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
            <p className="mt-1 break-all font-semibold text-[#031a41]">{shortValue(metric.value)}</p>
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

function ToolCallTracePanel({ toolCalls }: { toolCalls: unknown[] }) {
  const rows = toolCalls
    .map((item, index) => asRecord(item) ?? { name: `tool_${index + 1}`, value: item })
    .map((row, index) => ({
      key: `${index}-${valueOrDash(row.name ?? row.toolName ?? row.type)}`,
      name: valueOrDash(row.name ?? row.toolName ?? `tool_${index + 1}`),
      type: valueOrDash(row.type ?? row.kind ?? "-"),
      status: valueOrDash(row.status ?? row.result ?? "-"),
      readOnly: valueOrDash(row.readOnly ?? row.read_only ?? "-"),
      willExecute: valueOrDash(row.willExecute ?? row.will_execute ?? "-"),
      source: valueOrDash(row.source ?? row.command ?? row.value ?? "-"),
    }))

  if (rows.length === 0) {
    return (
      <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">
        当前 AgentTrace 没有 toolCallTraces，或对象详情暂不可用。
      </div>
    )
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">Tool Call Traces</h4>
        <p className="mt-1 text-xs text-slate-500">
          这里只展示工具调用轨迹，不提供任何执行入口。
        </p>
      </div>

      <div className="divide-y divide-slate-200">
        {rows.map((row) => (
          <div key={row.key} className="p-4">
            <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
              <div>
                <p className="font-mono text-sm font-semibold text-[#031a41]">{row.name}</p>
                <p className="mt-1 text-xs text-slate-500">{row.type}</p>
              </div>
              <span className={`w-fit rounded-full border px-2.5 py-1 text-[11px] font-semibold ${statusClass(row.status)}`}>
                {row.status}
              </span>
            </div>

            <div className="mt-3 grid gap-2 text-xs md:grid-cols-3">
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
                <p className="text-slate-500">readOnly</p>
                <p className="mt-1 font-mono font-semibold text-[#031a41]">{row.readOnly}</p>
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
                <p className="text-slate-500">willExecute</p>
                <p className="mt-1 font-mono font-semibold text-[#031a41]">{row.willExecute}</p>
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
                <p className="text-slate-500">source</p>
                <p className="mt-1 break-all font-mono font-semibold text-[#031a41]">{shortValue(row.source)}</p>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function ObjectEntriesPanel({
  title,
  description,
  record,
}: {
  title: string
  description: string
  record: JsonRecord | null
}) {
  const entries = Object.entries(record ?? {})

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">{title}</h4>
        <p className="mt-1 text-xs text-slate-500">{description}</p>
      </div>

      <div className="p-4">
        {entries.length === 0 ? (
          <div className="text-sm text-slate-600">暂无字段。</div>
        ) : (
          <div className="flex flex-wrap gap-2">
            {entries.map(([key, value]) => (
              <span
                key={key}
                className="rounded-full border border-cyan-200 bg-cyan-50 px-3 py-1 font-mono text-xs font-semibold text-cyan-800"
              >
                {key}={shortValue(valueOrDash(value), 90)}
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

export function AgentTracePanel({
  selected,
  evidenceQuery,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  onTabChange: (tab: string) => void
}) {
  const evidence = evidenceQuery.data
    ? parseJsonResource<TraceEvidencePayload>(evidenceQuery.data.body)
    : null

  const refs = evidence?.decisionRefs ?? {}
  const releaseId = evidence?.releaseId ?? selected.releaseId
  const fallbackAgentTraceId = evidence?.agentTraceId ?? refs.agentTrace?.agentTraceId ?? `at-${releaseId}`
  const fallbackTrace = useMemo(
    () => fallbackTraceFromEvidence(evidence, selected),
    [evidence, selected],
  )

  const traceQuery = useQuery({
    queryKey: ["evidence-store-agent-trace", selected.releaseId, fallbackAgentTraceId],
    queryFn: () =>
      fetchEvidenceStoreObject({
        objectType: "agentTrace",
        objectId: fallbackAgentTraceId,
        releaseId: selected.releaseId,
        includeRaw: true,
      }),
    enabled: Boolean(selected.releaseId && fallbackAgentTraceId),
    staleTime: 15000,
  })

  const realTrace = useMemo(
    () => normalizeTracePayload(traceQuery.data),
    [traceQuery.data],
  )

  const trace = realTrace ?? fallbackTrace
  const traceSource = realTrace ? "EvidenceStore agentTrace object" : "release evidence fallback"

  const correlation = asRecord(trace.correlation)
  const agentRun = asRecord(trace.agentRun)
  const policyTrace = asRecord(trace.policyTrace)
  const signedGateTrace = asRecord(trace.signedReleaseGateTrace)
  const evidenceTrace = asRecord(trace.evidenceTrace)
  const guardrails = asRecord(trace.guardrails)
  const toolCalls = arrayFromPaths(trace, [["toolCallTraces"]])

  const readOnly = booleanFromPaths(trace, [["guardrails", "readOnly"]])
  const willExecute = booleanFromPaths(trace, [["guardrails", "willExecute"]])
  const policyDecision = stringFromPaths(trace, [["policyTrace", "policyDecision"]])
  const finalAction = stringFromPaths(trace, [["policyTrace", "finalAction"]])
  const signedGateDecision = stringFromPaths(trace, [["signedReleaseGateTrace", "decision"]])
  const agentStatus = stringFromPaths(trace, [["agentRun", "status"]], realTrace ? "linked" : "fallback")

  const metrics: TraceMetric[] = [
    {
      label: "Agent Trace",
      value: stringFromPaths(trace, [["agentTraceId"]], fallbackAgentTraceId),
      hint: `schema=${valueOrDash(trace.schemaVersion)}`,
      status: realTrace ? "linked" : "fallback",
      icon: Fingerprint,
    },
    {
      label: "Trace ID",
      value: stringFromPaths(trace, [["traceId"]]),
      hint: "跨 AgentRun / Policy / Gate 的统一 traceId。",
      status: stringFromPaths(trace, [["traceId"]]) === "-" ? "missing" : "linked",
      icon: Network,
    },
    {
      label: "Agent Run",
      value: stringFromPaths(trace, [["agentRun", "agentRunId"], ["correlation", "agentRunId"]]),
      hint: `status=${agentStatus}`,
      status: agentStatus,
      icon: Bot,
    },
    {
      label: "Policy Trace",
      value: policyDisplay(policyDecision),
      hint: `finalAction=${actionDisplay(finalAction)}`,
      status: policyDecision,
      icon: ShieldCheck,
    },
    {
      label: "Signed Gate Trace",
      value: policyDisplay(signedGateDecision),
      hint: `signedReleaseGateId=${stringFromPaths(trace, [["signedReleaseGateTrace", "signedReleaseGateId"], ["correlation", "signedReleaseGateId"]])}`,
      status: signedGateDecision,
      icon: GitBranch,
    },
    {
      label: "Tool Calls",
      value: String(toolCalls.length),
      hint: "只读工具调用轨迹数量。",
      status: toolCalls.length > 0 ? "linked" : "missing",
      icon: Wrench,
    },
    {
      label: "Read Only",
      value: boolText(readOnly),
      hint: "Agent Trace 必须保持只读分析边界。",
      status: readOnly ? "PASS" : "REQUIRED",
      icon: readOnly ? CheckCircle2 : AlertTriangle,
    },
    {
      label: "Will Execute",
      value: boolText(willExecute),
      hint: "Stage 41 只展示 trace，不执行动作。",
      status: willExecute ? "REQUIRED" : "PASS",
      icon: willExecute ? AlertTriangle : CheckCircle2,
    },
  ]

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-4 border-b border-slate-200 pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Agent Trace View
          </p>
          <h3 className="mt-2 flex items-center gap-2 text-lg font-semibold tracking-tight text-[#031a41]">
            <Braces className="h-5 w-5 text-cyan-700" />
            AI Advisor 可观测链路
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            通过 EvidenceStore 查询 agentTrace 对象，展示 AgentRun、PolicyTrace、SignedReleaseGateTrace、
            ToolCallTraces、EvidenceTrace 和 Guardrails。若对象详情暂不可用，则回退到 release evidence 中的 trace 摘要。
          </p>
        </div>

        <div className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
          <p className="text-xs text-slate-500">Trace Source</p>
          <p className="mt-1 font-semibold text-[#031a41]">{traceSource}</p>
          <p className="mt-1 font-mono text-xs text-slate-500">
            /api/evidence-store/objects/agentTrace/{fallbackAgentTraceId}
          </p>
        </div>
      </div>

      {traceQuery.isError ? (
        <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          AgentTrace 对象详情读取失败，当前使用 release evidence fallback：
          {traceQuery.error instanceof Error ? traceQuery.error.message : "unknown error"}
        </div>
      ) : null}

      <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {metrics.map((metric) => (
          <TraceMetricCard key={metric.label} metric={metric} />
        ))}
      </div>

      <section className="mt-5 grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
          <div className="mb-3 flex items-center gap-2 font-semibold text-[#031a41]">
            <Route className="h-4 w-4 text-cyan-700" />
            Correlation
          </div>
          <KeyValueRows
            rows={[
              ["releaseId", valueOrDash(correlation?.releaseId ?? trace.releaseId)],
              ["agentRunId", valueOrDash(correlation?.agentRunId)],
              ["policyDecisionId", valueOrDash(correlation?.policyDecisionId)],
              ["policyRuntimeResultId", valueOrDash(correlation?.policyRuntimeResultId)],
              ["signedReleaseGateId", valueOrDash(correlation?.signedReleaseGateId)],
              ["generatedBy", valueOrDash(trace.generatedBy)],
              ["generatedAt", valueOrDash(trace.generatedAt)],
            ]}
          />
        </div>

        <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
          <div className="mb-3 flex items-center gap-2 font-semibold text-[#031a41]">
            <Bot className="h-4 w-4 text-cyan-700" />
            Agent Run Snapshot
          </div>
          <KeyValueRows
            rows={[
              ["agentRunId", valueOrDash(agentRun?.agentRunId ?? correlation?.agentRunId)],
              ["mode", valueOrDash(agentRun?.mode)],
              ["recommendedAction", valueOrDash(agentRun?.recommendedAction)],
              ["priority", valueOrDash(agentRun?.priority)],
              ["status", valueOrDash(agentRun?.status)],
              ["willExecute", valueOrDash(agentRun?.willExecute)],
            ]}
          />
        </div>
      </section>

      <section className="mt-5 grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
          <div className="mb-3 flex items-center gap-2 font-semibold text-[#031a41]">
            <ShieldCheck className="h-4 w-4 text-cyan-700" />
            Policy Trace
          </div>
          <KeyValueRows
            rows={[
              ["policyDecisionId", valueOrDash(policyTrace?.policyDecisionId)],
              ["policyRuntimeResultId", valueOrDash(policyTrace?.policyRuntimeResultId)],
              ["policyDecision", policyDisplay(valueOrDash(policyTrace?.policyDecision))],
              ["finalAction", actionDisplay(valueOrDash(policyTrace?.finalAction))],
              ["reason", valueOrDash(policyTrace?.reason)],
            ]}
          />
        </div>

        <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
          <div className="mb-3 flex items-center gap-2 font-semibold text-[#031a41]">
            <GitBranch className="h-4 w-4 text-cyan-700" />
            Signed Release Gate Trace
          </div>
          <KeyValueRows
            rows={[
              ["signedReleaseGateId", valueOrDash(signedGateTrace?.signedReleaseGateId)],
              ["decision", policyDisplay(valueOrDash(signedGateTrace?.decision))],
              ["allowed", valueOrDash(signedGateTrace?.allowed)],
              ["riskLevel", valueOrDash(signedGateTrace?.riskLevel)],
              ["riskScore", valueOrDash(signedGateTrace?.riskScore)],
              ["source", valueOrDash(signedGateTrace?.source)],
            ]}
          />
        </div>
      </section>

      <section className="mt-5">
        <ToolCallTracePanel toolCalls={toolCalls} />
      </section>

      <section className="mt-5 grid gap-4 lg:grid-cols-2">
        <ObjectEntriesPanel
          title="Evidence Trace"
          description="AgentTrace 链接到的 release evidence、AI decision、policy decision 和 gate evidence。"
          record={evidenceTrace}
        />

        <ObjectEntriesPanel
          title="Guardrails"
          description="AgentTrace 的只读安全边界，Stage 41 不允许执行任何动作。"
          record={guardrails}
        />
      </section>

      <section className="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-4">
        <div className="mb-3 flex items-center gap-2 font-semibold text-[#031a41]">
          <FileSearch className="h-4 w-4 text-cyan-700" />
          Raw Agent Trace
        </div>
        <pre className="max-h-[420px] overflow-auto whitespace-pre-wrap rounded-xl bg-[#031a41] p-4 text-xs leading-6 text-cyan-50">
          {JSON.stringify(realTrace ?? traceQuery.data ?? trace, null, 2)}
        </pre>
      </section>

      <div className="mt-5 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => onTabChange("AI Advice")}
          className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
        >
          查看 AI Advice
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
          onClick={() => onTabChange("Intelligence")}
          className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
        >
          查看 Intelligence
        </button>
      </div>
    </section>
  )
}
