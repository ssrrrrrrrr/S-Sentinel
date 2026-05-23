import type { UseQueryResult } from "@tanstack/react-query"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { PortalInformationArchitecture } from "@/components/layout/PortalInformationArchitecture"
import { RoutePageHeader, type RouteHeaderBadgeTone } from "@/components/layout/RoutePageHeader"
import { StageBanner } from "@/components/layout/StageBanner"
import type { PortalRoute } from "@/components/layout/portalRoutes"
import { AgentTracePanel } from "@/components/release/AgentTracePanel"
import { ApprovalConsolePanel } from "@/components/release/ApprovalConsolePanel"
import { ControlPlaneGraph } from "@/components/release/ControlPlaneGraph"
import { ControlPlaneObjectCards } from "@/components/release/ControlPlaneObjectCards"
import { EnvironmentAwarePortalPanel } from "@/components/release/EnvironmentAwarePortalPanel"
import { EvidenceStorePanel } from "@/components/release/EvidenceStorePanel"
import { PolicyExplanationPanel } from "@/components/release/PolicyExplanationPanel"
import { ReleaseDetailWorkspace } from "@/components/release/ReleaseDetailWorkspace"
import { ReleaseMetricGrid } from "@/components/release/ReleaseMetricGrid"
import { SupplyChainGatePanel } from "@/components/release/SupplyChainGatePanel"
import type { LatestReleaseResponse, ReleaseIndexItem } from "@/types/release"

function resultTone(value: string): RouteHeaderBadgeTone {
  const normalized = value.toLowerCase()

  if (normalized.includes("pass") || normalized.includes("allow") || normalized.includes("success")) {
    return "success"
  }

  if (normalized.includes("fail") || normalized.includes("deny") || normalized.includes("block")) {
    return "danger"
  }

  if (normalized.includes("pending") || normalized.includes("required") || normalized.includes("warn")) {
    return "warning"
  }

  return "neutral"
}

function boolTone(value: boolean): RouteHeaderBadgeTone {
  return value ? "warning" : "success"
}

function RouteHeader({
  activeRoute,
  selected,
  releaseCount,
}: {
  activeRoute: PortalRoute
  selected: ReleaseIndexItem
  releaseCount: number
}) {
  const summary = selected.summary

  const routeCopy: Record<PortalRoute, { eyebrow: string; title: string; description: string }> = {
    Overview: {
      eyebrow: "Overview",
      title: "Release Control Room",
      description: "一眼判断当前发布是否安全，并快速跳转到 Evidence、Policy、Supply Chain、Advisor Trace 或 Approval 页面。",
    },
    Releases: {
      eyebrow: "Releases",
      title: "Release History & Detail",
      description: "查看发布历史、选中发布详情、资源摘要、时间线、Runbook、RCA 和原始审计内容。",
    },
    Evidence: {
      eyebrow: "Evidence",
      title: "Evidence Objects & Release Graph",
      description: "查看当前发布关联的 Evidence Object、控制平面对象链路和 EvidenceStore 检索结果。",
    },
    Policy: {
      eyebrow: "Policy",
      title: "Policy Decision Explanation",
      description: "解释本次发布为什么允许、阻断、需要人工审批或保持只读边界。",
    },
    "Supply Chain": {
      eyebrow: "Supply Chain",
      title: "Signed Gate & Image Trust",
      description: "检查镜像摘要、GitOps 发布标签、Signed Release Gate、SupplyChainDecision 和供应链阻断原因。",
    },
    "Agent Trace": {
      eyebrow: "Advisor Trace",
      title: "Advisor Runtime Observability",
      description: "展示只读 Advisor 的 AgentRun、PolicyTrace、ToolCallTrace、EvidenceTrace 和 Guardrails。",
    },
    Approval: {
      eyebrow: "Approval",
      title: "Approval Boundary & Execution Request",
      description: "展示执行申请、人工审批状态、策略边界和只读执行约束，不提供直接执行入口。",
    },
    Environment: {
      eyebrow: "Environment",
      title: "Environment & Packaging Context",
      description: "展示当前发布的环境、集群、namespace、GitOps overlay、policy profile 和环境配置快照。",
    },
  }

  const copy = routeCopy[activeRoute]

  return (
    <RoutePageHeader
      eyebrow={copy.eyebrow}
      title={copy.title}
      description={copy.description}
      badges={[
        { label: "release", value: selected.releaseId, tone: "info" },
        { label: "result", value: summary.releaseResult, tone: resultTone(summary.releaseResult) },
        { label: "approval", value: String(summary.requiresHumanApproval), tone: boolTone(Boolean(summary.requiresHumanApproval)) },
        { label: "records", value: String(releaseCount), tone: "neutral" },
      ]}
    />
  )
}

export function PortalRouteRenderer({
  activeRoute,
  releases,
  selected,
  totalCount,
  onSelect,
  onRefresh,
  tabs,
  activeTab,
  onTabChange,
  onRouteChange,
  latest,
  resourceKind,
  resourceQuery,
  evidenceQuery,
  releaseCount,
}: {
  activeRoute: PortalRoute
  releases: ReleaseIndexItem[]
  selected: ReleaseIndexItem
  totalCount: number
  onSelect: (releaseId: string) => void
  onRefresh: () => void
  tabs: string[]
  activeTab: string
  onTabChange: (tab: string) => void
  onRouteChange: (route: PortalRoute) => void
  latest?: LatestReleaseResponse
  resourceKind: string
  resourceQuery: UseQueryResult<ReleaseResourceContent, Error>
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  releaseCount: number
}) {
  function routeForTab(tab: string): PortalRoute | null {
    switch (tab) {
      case "Evidence":
        return "Evidence"
      case "Context":
        return "Environment"
      case "AI Advice":
      case "Intelligence":
        return "Agent Trace"
      case "Action Plan":
        return "Approval"
      case "Runbook":
      case "RCA":
      case "Timeline":
      case "概览":
        return "Releases"
      default:
        return null
    }
  }

  function handleRouteAwareTabChange(tab: string) {
    onTabChange(tab)

    const nextRoute = routeForTab(tab)
    if (nextRoute) {
      onRouteChange(nextRoute)
    }
  }

  const pageHeader = (
    <RouteHeader
      activeRoute={activeRoute}
      selected={selected}
      releaseCount={releaseCount}
    />
  )

  switch (activeRoute) {
    case "Overview":
      return (
        <>
          {pageHeader}

          <StageBanner latest={latest} />

          <PortalInformationArchitecture
            latest={latest}
            releaseCount={releaseCount}
            activeTab={activeTab}
            onTabChange={handleRouteAwareTabChange}
          />

          <ReleaseMetricGrid selected={selected} />
        </>
      )

    case "Releases":
      return (
        <>
          {pageHeader}

          <ReleaseDetailWorkspace
            releases={releases}
            selected={selected}
            totalCount={totalCount}
            onSelect={onSelect}
            onRefresh={onRefresh}
            tabs={tabs}
            activeTab={activeTab}
            onTabChange={onTabChange}
            latest={latest}
            resourceKind={resourceKind}
            resourceQuery={resourceQuery}
          />
        </>
      )

    case "Evidence":
      return (
        <>
          {pageHeader}

          <ControlPlaneObjectCards
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={handleRouteAwareTabChange}
          />

          <ControlPlaneGraph
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={handleRouteAwareTabChange}
          />

          <EvidenceStorePanel
            selected={selected}
            onTabChange={handleRouteAwareTabChange}
          />
        </>
      )

    case "Policy":
      return (
        <>
          {pageHeader}

          <PolicyExplanationPanel
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={handleRouteAwareTabChange}
          />
        </>
      )

    case "Supply Chain":
      return (
        <>
          {pageHeader}

          <SupplyChainGatePanel
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={handleRouteAwareTabChange}
          />
        </>
      )

    case "Agent Trace":
      return (
        <>
          {pageHeader}

          <AgentTracePanel
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={handleRouteAwareTabChange}
          />
        </>
      )

    case "Approval":
      return (
        <>
          {pageHeader}

          <ApprovalConsolePanel
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={handleRouteAwareTabChange}
          />
        </>
      )

    case "Environment":
      return (
        <>
          {pageHeader}

          <EnvironmentAwarePortalPanel
            selected={selected}
            evidenceQuery={evidenceQuery}
            onTabChange={handleRouteAwareTabChange}
          />
        </>
      )

    default:
      return null
  }
}

