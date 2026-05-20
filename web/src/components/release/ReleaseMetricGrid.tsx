import {
  AlertTriangle,
  CheckCircle2,
  FileText,
  LockKeyhole,
  ShieldCheck,
  TerminalSquare,
} from "lucide-react"
import { MetricCard } from "@/components/common/MetricCard"
import type { ReleaseIndexItem } from "@/types/release"
import {
  actionDisplay,
  approvalRaw,
  approvalText,
  policyDisplay,
  resultDisplay,
  riskText,
} from "@/utils/format"

export function ReleaseMetricGrid({ selected }: { selected: ReleaseIndexItem }) {
  const selectedSummary = selected.summary

  return (
    <section className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4">
      <MetricCard
        label="最新结果"
        value={resultDisplay(selectedSummary.releaseResult)}
        rawValue={selectedSummary.releaseResult}
        icon={CheckCircle2}
        hint="最近一次 evidence-backed 发布"
      />
      <MetricCard
        label="策略决策"
        value={policyDisplay(selectedSummary.policyDecision)}
        rawValue={selectedSummary.policyDecision}
        icon={ShieldCheck}
        hint="Policy Decision 结果"
      />
      <MetricCard
        label="最终动作"
        value={actionDisplay(selectedSummary.finalAction)}
        rawValue={selectedSummary.finalAction}
        icon={TerminalSquare}
        hint="系统建议的最终动作"
      />
      <MetricCard
        label="风险等级"
        value={riskText(selectedSummary.riskLevel)}
        rawValue={selectedSummary.riskLevel}
        icon={AlertTriangle}
        hint={`Risk Score ${selectedSummary.riskScore}/100`}
      />
      <MetricCard
        label="人工审批"
        value={approvalText(selectedSummary.requiresHumanApproval)}
        rawValue={approvalRaw(selectedSummary.requiresHumanApproval)}
        icon={LockKeyhole}
        hint="人工门禁状态"
      />
      <MetricCard
        label="资源数量"
        value={String(selected.resourceCount)}
        icon={FileText}
        hint="关联发布证据资源"
      />
    </section>
  )
}
