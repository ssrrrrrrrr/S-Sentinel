import {
  Activity,
  CheckCircle2,
  GitBranch,
  ShieldCheck,
  Sparkles,
  TerminalSquare,
} from "lucide-react"
import { Badge } from "@/components/common/Badge"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import { ProductMetricCard } from "@/components/common/ProductMetricCard"
import { ResourceMetadataPanel } from "@/components/release/ResourceMetadataPanel"
import type { LatestReleaseResponse, ReleaseIndexItem } from "@/types/release"
import {
  actionDisplay,
  normalize,
  policyDisplay,
  resultDisplay,
  riskText,
} from "@/utils/format"
import {
  markdownValue,
  RuleChipsPanel,
} from "./shared"
function markdownCodeValues(body: string) {
  return Array.from(body.matchAll(/`([^`]+)`/g)).map((match) => match[1]?.trim() ?? "")
}

function markdownRuleValues(body: string) {
  return body
    .split(/\r?\n/)
    .map((line) => line.trim().match(/^-\s*`([^`]+)`/)?.[1]?.trim())
    .filter((value): value is string => Boolean(value))
    .filter((value) => value.includes("_") && !value.includes("/") && !value.includes(".json") && !value.includes(".md"))
}

export function OverviewProductView({
  body,
  selected,
  latest,
}: {
  body: string
  selected: ReleaseIndexItem
  latest?: LatestReleaseResponse
}) {
  const values = markdownCodeValues(body)
  const summary = selected.summary

  const releaseResult = summary.releaseResult || values[0] || "-"
  const policyDecision = summary.policyDecision || values[1] || "-"
  const finalAction = summary.finalAction || values[2] || "-"
  const executionMode = summary.executionMode || values[3] || "-"
  const requiresHumanApproval = summary.requiresHumanApproval
  const safeToRetry = summary.safeToRetry

  const rolloutPhase = values[6] || "-"
  const rolloutAbort = values[7] || "-"
  const analysisRunPhase = values[8] || "-"

  const runtimeRiskLevel = summary.riskLevel || values[9] || "-"
  const runtimeRiskScore = Number.isFinite(summary.riskScore) ? summary.riskScore : Number(values[10] ?? 0)
  const changeRiskLevel = values[11] || "-"
  const changeRiskScore = Number(values[12] ?? 0)

  const rules = markdownRuleValues(body)
  const recommendedNextAction =
    markdownValue(body, "Recommended Next Action") !== "-"
      ? markdownValue(body, "Recommended Next Action")
      : finalAction === "NOOP"
        ? "archive_release_record"
        : finalAction

  return (
    <div className="space-y-5 rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h4 className="text-base font-semibold text-[#031a41]">Release 综合摘要</h4>
          <p className="mt-1 text-sm text-slate-600">
            汇总发布结论、策略裁决、Rollout / AnalysisRun 状态、风险、SLO 门禁和资源索引。
          </p>
        </div>
        <Badge value={releaseResult} label={resultDisplay(releaseResult)} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <ProductMetricCard
          label="最终结论"
          value={resultDisplay(releaseResult)}
          rawValue={releaseResult}
          icon={CheckCircle2}
          hint="本次发布最终结果"
          statusValue={releaseResult}
        />
        <ProductMetricCard
          label="策略裁决"
          value={policyDisplay(policyDecision)}
          rawValue={policyDecision}
          icon={ShieldCheck}
          hint="Policy Evaluator 输出"
          statusValue={policyDecision}
        />
        <ProductMetricCard
          label="最终动作"
          value={actionDisplay(finalAction)}
          rawValue={finalAction}
          icon={TerminalSquare}
          hint="系统建议动作"
          statusValue={finalAction}
        />
        <ProductMetricCard
          label="Rollout"
          value={rolloutPhase}
          rawValue={`abort=${rolloutAbort}`}
          icon={GitBranch}
          hint="Rollout 发布状态"
          statusValue={rolloutPhase}
        />
        <ProductMetricCard
          label="AnalysisRun"
          value={analysisRunPhase}
          icon={Activity}
          hint="SLO AnalysisRun 状态"
          statusValue={analysisRunPhase}
        />
        <ProductMetricCard
          label="推荐下一步"
          value={recommendedNextAction}
          icon={Sparkles}
          hint="综合摘要推荐动作"
          statusValue={recommendedNextAction.includes("archive") ? "PASS" : recommendedNextAction}
        />
      </div>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">风险摘要</h4>
          <KeyValueRows
            rows={[
              ["runtimeRiskLevel", riskText(runtimeRiskLevel)],
              ["runtimeRiskScore", String(runtimeRiskScore)],
              ["changeRiskLevel", riskText(changeRiskLevel)],
              ["changeRiskScore", String(changeRiskScore)],
              ["executionMode", executionMode],
              ["safeToRetry", String(safeToRetry)],
            ]}
          />
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">安全边界</h4>
          <KeyValueRows
            rows={[
              ["requiresHumanApproval", String(requiresHumanApproval)],
              ["readOnly", String(latest?.safety?.readOnly ?? true)],
              ["willExecute", String(latest?.safety?.willExecute ?? false)],
              ["supportsRollback", String(latest?.safety?.supportsRollback ?? false)],
              ["supportsPromote", String(latest?.safety?.supportsPromote ?? false)],
              ["supportsDelete", String(latest?.safety?.supportsDelete ?? false)],
            ]}
          />
        </div>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">SLO 门禁结果</h4>
          {normalize(releaseResult).includes("FAIL") ? (
            <div className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
              当前发布存在失败门禁，请查看 Evidence / Intelligence / Action Plan。
            </div>
          ) : (
            <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">
              当前发布通过 SLO 门禁，未发现失败指标。
            </div>
          )}
        </div>

        <div className="space-y-3">
          <h4 className="text-sm font-semibold text-slate-900">命中的策略规则</h4>
          <RuleChipsPanel rules={rules} />
        </div>
      </section>

      <ResourceMetadataPanel selected={selected} />
    </div>
  )
}

