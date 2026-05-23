export const portalRoutes = [
  {
    id: "Overview",
    title: "Overview",
    description: "release health",
    group: "Platform",
  },
  {
    id: "Releases",
    title: "Releases",
    description: "rollout history",
    group: "Platform",
  },
  {
    id: "Evidence",
    title: "Evidence",
    description: "EvidenceStore 检索与对象详情",
    group: "Workspaces",
  },
  {
    id: "Policy",
    title: "Policy",
    description: "策略裁决解释与安全边界",
    group: "Workspaces",
  },
  {
    id: "Supply Chain",
    title: "Supply Chain",
    description: "镜像可信度与签名发布门禁",
    group: "Workspaces",
  },
  {
    id: "Agent Trace",
    title: "Agent Trace",
    description: "Advisor 可观测链路",
    group: "Workspaces",
  },
  {
    id: "Approval",
    title: "Approval",
    description: "人工审批与执行申请",
    group: "Workspaces",
  },
  {
    id: "Environment",
    title: "Environment",
    description: "环境上下文与多环境证据",
    group: "Workspaces",
  },
] as const

export type PortalRoute = (typeof portalRoutes)[number]["id"]

export const defaultPortalRoute: PortalRoute = "Overview"

export const platformRoutes = portalRoutes.filter((route) => route.group === "Platform")
export const workspaceRoutes = portalRoutes.filter((route) => route.group === "Workspaces")
