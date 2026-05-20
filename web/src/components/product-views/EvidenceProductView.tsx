import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  FileText,
  GitBranch,
  ShieldCheck,
  TerminalSquare,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import { ProductMetricCard } from "@/components/common/ProductMetricCard"
import {
  actionDisplay,
  policyDisplay,
  resultDisplay,
  riskText,
} from "@/utils/format"
import {
  FailedMetricsPanel,
  parseJsonResource,
  RuleChipsPanel,
} from "./shared"

type EvidencePayload = {
  schemaVersion?: string
  generatedBy?: string
  generatedAt?: string
  releaseResult?: string
  policyDecision?: string
  finalAction?: string
  executionMode?: string
  requiresHumanApproval?: boolean
  safeToRetry?: boolean
  summary?: {
    rolloutPhase?: string
    rolloutAbort?: boolean
    analysisRunPhase?: string
    riskLevel?: string
    riskScore?: number
    changeRiskLevel?: string
    changeRiskScore?: number | null
    failedMetrics?: unknown[]
    matchedPolicyRules?: string[]
  }
  artifacts?: Record<string, string>
  decisionRefs?: {
    aiDecision?: {
      decisionSource?: string
      confidence?: string
      agentAction?: {
        type?: string
        allowed?: boolean
        requiresApproval?: boolean
        reason?: string
      }
      policyHints?: string[]
      nextSteps?: string[]
    }
    policyDecision?: {
      reason?: string
      inputSummary?: {
        releaseResult?: string
        agentActionType?: string
        agentActionAllowed?: boolean
        agentActionRequiresApproval?: boolean
        autoExecute?: boolean
      }
    }
  }
  failureEvidenceRef?: {
    generated?: boolean
    json?: string
    markdown?: string
  }
  actionPlanRef?: {
    generated?: boolean
    json?: string
    markdown?: string
    executionMode?: string
    willExecute?: boolean
  }
  releaseIntelligenceRef?: {
    generated?: boolean
    json?: string
    markdown?: string
    readOnlyAnalysis?: boolean
  }
  failedMetrics?: unknown[]
  matchedPolicyRules?: string[]
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function EvidenceVerdictPanel({
  releaseResult,
  failedMetricCount,
  policyReason,
  safeToRetry,
}: {
  releaseResult: string
  failedMetricCount: number
  policyReason?: string
  safeToRetry?: boolean
}) {
  const isPass = releaseResult === "PASS"

  return (
    <div className={`rounded-2xl border p-5 ${
      isPass
        ? "border-emerald-200 bg-emerald-50"
        : "border-rose-200 bg-rose-50"
    }`}>
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="flex flex-wrap gap-2">
            <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
            <Badge
              value={failedMetricCount > 0 ? "REQUIRED" : "NOT REQUIRED"}
              label={`${failedMetricCount} failed SLO`}
            />
            <Badge
              value={safeToRetry ? "ALLOW" : "REQUIRED"}
              label={safeToRetry ? "safeToRetry=true" : "safeToRetry=false"}
            />
          </div>

          <h4 className={`mt-4 text-lg font-semibold ${isPass ? "text-emerald-950" : "text-rose-950"}`}>
            {isPass ? "证据链结论：发布通过 SLO 门禁" : "证据链结论：发布未通过 SLO 门禁"}
          </h4>
          <p className={`mt-2 max-w-4xl text-sm leading-6 ${isPass ? "text-emerald-800" : "text-rose-800"}`}>
            {policyReason || (isPass ? "当前没有失败指标，策略允许记录本次发布结果。" : "当前存在失败指标，需要进入人工排查和修复流程。")}
          </p>
        </div>

        <div className={`rounded-xl border bg-white/80 p-4 text-sm shadow-sm ${
          isPass ? "border-emerald-100" : "border-rose-100"
        }`}>
          <p className="text-slate-500">Evidence 视图职责</p>
          <p className="mt-2 max-w-xs text-slate-700">
            这里重点展示系统为什么做出 PASS / FAIL 判断，而不是负责执行动作。
          </p>
        </div>
      </div>
    </div>
  )
}

function ReleaseStateEvidencePanel({
  rolloutPhase,
  rolloutAbort,
  analysisRunPhase,
  executionMode,
  requiresHumanApproval,
}: {
  rolloutPhase: string
  rolloutAbort?: boolean
  analysisRunPhase: string
  executionMode?: string
  requiresHumanApproval?: boolean
}) {
  return (
    <div className="space-y-3">
      <h4 className="text-sm font-semibold text-slate-900">Rollout / AnalysisRun 证据</h4>
      <KeyValueRows
        rows={[
          ["rolloutPhase", rolloutPhase],
          ["rolloutAbort", String(rolloutAbort ?? false)],
          ["analysisRunPhase", analysisRunPhase],
          ["executionMode", executionMode ?? "-"],
          ["requiresHumanApproval", String(requiresHumanApproval ?? "-")],
        ]}
      />
    </div>
  )
}

function RiskEvidencePanel({
  riskLevel,
  riskScore,
  changeRiskLevel,
  changeRiskScore,
  safeToRetry,
}: {
  riskLevel: string
  riskScore: number
  changeRiskLevel: string
  changeRiskScore?: number | null
  safeToRetry?: boolean
}) {
  return (
    <div className="space-y-3">
      <h4 className="text-sm font-semibold text-slate-900">风险证据</h4>
      <KeyValueRows
        rows={[
          ["runtimeRiskLevel", riskText(riskLevel)],
          ["runtimeRiskScore", String(riskScore)],
          ["changeRiskLevel", riskText(changeRiskLevel)],
          ["changeRiskScore", valueOrDash(changeRiskScore)],
          ["safeToRetry", String(safeToRetry ?? "-")],
        ]}
      />
    </div>
  )
}

function DecisionTracePanel({ evidence }: { evidence: EvidencePayload }) {
  const aiDecision = evidence.decisionRefs?.aiDecision
  const policyDecision = evidence.decisionRefs?.policyDecision
  const agentAction = aiDecision?.agentAction
  const inputSummary = policyDecision?.inputSummary

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">决策链路</h4>
        <p className="mt-1 text-xs text-slate-500">
          从 deterministic / AI decision 到 policy decision 的判断依据。
        </p>
      </div>

      <div className="grid gap-4 p-4 lg:grid-cols-2">
        <KeyValueRows
          rows={[
            ["decisionSource", aiDecision?.decisionSource ?? "-"],
            ["confidence", aiDecision?.confidence ?? "-"],
            ["agentActionType", agentAction?.type ?? "-"],
            ["agentActionAllowed", String(agentAction?.allowed ?? "-")],
            ["agentActionRequiresApproval", String(agentAction?.requiresApproval ?? "-")],
            ["agentActionReason", agentAction?.reason ?? "-"],
          ]}
        />

        <KeyValueRows
          rows={[
            ["policyReason", policyDecision?.reason ?? "-"],
            ["releaseResult", inputSummary?.releaseResult ?? "-"],
            ["agentActionType", inputSummary?.agentActionType ?? "-"],
            ["agentActionAllowed", String(inputSummary?.agentActionAllowed ?? "-")],
            ["agentActionRequiresApproval", String(inputSummary?.agentActionRequiresApproval ?? "-")],
            ["autoExecute", String(inputSummary?.autoExecute ?? "-")],
          ]}
        />
      </div>

      <div className="grid gap-4 border-t border-slate-200 p-4 lg:grid-cols-2">
        <div>
          <h5 className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Policy Hints</h5>
          <div className="mt-3">
            <RuleChipsPanel rules={aiDecision?.policyHints ?? []} />
          </div>
        </div>
        <div>
          <h5 className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Next Steps</h5>
          <div className="mt-3">
            <RuleChipsPanel rules={aiDecision?.nextSteps ?? []} />
          </div>
        </div>
      </div>
    </div>
  )
}

function ArtifactTracePanel({ evidence }: { evidence: EvidencePayload }) {
  const artifactEntries = Object.entries(evidence.artifacts ?? {})

  return (
    <div className="rounded-xl border border-slate-200 bg-white">
      <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
        <h4 className="text-sm font-semibold text-slate-900">证据资源索引</h4>
        <p className="mt-1 text-xs text-slate-500">
          Evidence bundle 关联的上下文、报告、策略、Action Plan 和历史智能文件。
        </p>
      </div>

      <div className="divide-y divide-slate-200">
        {artifactEntries.length === 0 ? (
          <div className="px-4 py-3 text-sm text-slate-600">当前 Evidence 没有关联 artifacts。</div>
        ) : (
          artifactEntries.map(([key, value]) => (
            <div key={key} className="grid gap-2 px-4 py-3 text-sm md:grid-cols-[190px_1fr]">
              <span className="font-mono text-xs text-slate-500">{key}</span>
              <span className="break-all font-mono text-[#031a41]">{value}</span>
            </div>
          ))
        )}
      </div>

      <div className="grid gap-3 border-t border-slate-200 p-4 md:grid-cols-3">
        <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
          <p className="text-xs text-slate-500">failureEvidence</p>
          <p className="mt-2 font-mono text-sm font-semibold text-[#031a41]">
            {String(evidence.failureEvidenceRef?.generated ?? false)}
          </p>
        </div>
        <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
          <p className="text-xs text-slate-500">actionPlan</p>
          <p className="mt-2 font-mono text-sm font-semibold text-[#031a41]">
            generated={String(evidence.actionPlanRef?.generated ?? false)}
          </p>
          <p className="mt-1 font-mono text-xs text-slate-500">
            willExecute={String(evidence.actionPlanRef?.willExecute ?? false)}
          </p>
        </div>
        <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
          <p className="text-xs text-slate-500">releaseIntelligence</p>
          <p className="mt-2 font-mono text-sm font-semibold text-[#031a41]">
            generated={String(evidence.releaseIntelligenceRef?.generated ?? false)}
          </p>
          <p className="mt-1 font-mono text-xs text-slate-500">
            readOnly={String(evidence.releaseIntelligenceRef?.readOnlyAnalysis ?? true)}
          </p>
        </div>
      </div>
    </div>
  )
}

export function EvidenceProductView({ body }: { body: string }) {
  const evidence = parseJsonResource<EvidencePayload>(body)

  if (!evidence) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
        Evidence JSON 解析失败，已保留下方原始内容用于审计。
      </div>
    )
  }

  const summary = evidence.summary ?? {}
  const failedMetrics = Array.isArray(summary.failedMetrics)
    ? summary.failedMetrics
    : Array.isArray(evidence.failedMetrics)
      ? evidence.failedMetrics
      : []

  const matchedPolicyRules = Array.isArray(summary.matchedPolicyRules)
    ? summary.matchedPolicyRules
    : Array.isArray(evidence.matchedPolicyRules)
      ? evidence.matchedPolicyRules
      : []

  const releaseResult = evidence.releaseResult ?? "-"
  const policyDecision = evidence.policyDecision ?? "-"
  const finalAction = evidence.finalAction ?? "-"
  const rolloutPhase = summary.rolloutPhase ?? "-"
  const analysisRunPhase = summary.analysisRunPhase ?? "-"
  const riskLevel = summary.riskLevel ?? "-"
  const riskScore = summary.riskScore ?? 0
  const changeRiskLevel = summary.changeRiskLevel ?? "-"
  const changeRiskScore = summary.changeRiskScore

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Evidence 证据链路视图</h4>
          <p className="mt-1 text-sm text-slate-600">
            重点回答：系统依据哪些 Rollout、AnalysisRun、SLO、Policy 和 Artifact 证据判断本次发布。
          </p>
        </div>
        <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
      </div>

      <EvidenceVerdictPanel
        releaseResult={releaseResult}
        failedMetricCount={failedMetrics.length}
        policyReason={evidence.decisionRefs?.policyDecision?.reason}
        safeToRetry={evidence.safeToRetry}
      />

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="SLO 门禁"
          value={failedMetrics.length > 0 ? "存在失败" : "全部通过"}
          rawValue={`${failedMetrics.length} failed`}
          icon={failedMetrics.length > 0 ? AlertTriangle : CheckCircle2}
          hint="Evidence 中的 failedMetrics"
          statusValue={failedMetrics.length > 0 ? "REQUIRED" : "PASS"}
        />
        <ProductMetricCard
          label="Rollout 证据"
          value={rolloutPhase}
          rawValue={`abort=${String(summary.rolloutAbort ?? false)}`}
          icon={GitBranch}
          hint="Rollout phase / abort"
          statusValue={rolloutPhase}
        />
        <ProductMetricCard
          label="AnalysisRun 证据"
          value={analysisRunPhase}
          icon={Activity}
          hint="AnalysisRun phase"
          statusValue={analysisRunPhase}
        />
        <ProductMetricCard
          label="Policy 证据"
          value={policyDisplay(policyDecision)}
          rawValue={policyDecision}
          icon={ShieldCheck}
          hint={`${matchedPolicyRules.length} matched rules`}
          statusValue={policyDecision}
        />
        <ProductMetricCard
          label="Action 引用"
          value={actionDisplay(finalAction)}
          rawValue={finalAction}
          icon={TerminalSquare}
          hint="Evidence 引用最终动作，不负责执行"
          statusValue={finalAction}
        />
        <ProductMetricCard
          label="Artifact 数量"
          value={String(Object.keys(evidence.artifacts ?? {}).length)}
          icon={FileText}
          hint="Evidence bundle 关联资源"
          statusValue="PASS"
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <ReleaseStateEvidencePanel
          rolloutPhase={rolloutPhase}
          rolloutAbort={summary.rolloutAbort}
          analysisRunPhase={analysisRunPhase}
          executionMode={evidence.executionMode}
          requiresHumanApproval={evidence.requiresHumanApproval}
        />

        <RiskEvidencePanel
          riskLevel={riskLevel}
          riskScore={riskScore}
          changeRiskLevel={changeRiskLevel}
          changeRiskScore={changeRiskScore}
          safeToRetry={evidence.safeToRetry}
        />
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">SLO 门禁证据</h4>
          <FailedMetricsPanel metrics={failedMetrics} />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">命中的 Policy Rules</h4>
          <RuleChipsPanel rules={matchedPolicyRules} />
        </div>
      </section>

      <DecisionTracePanel evidence={evidence} />

      <ArtifactTracePanel evidence={evidence} />
    </div>
  )
}
