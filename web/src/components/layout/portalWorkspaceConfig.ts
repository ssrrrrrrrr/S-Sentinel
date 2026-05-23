export const portalWorkspaces = [
  {
    id: "Evidence",
    title: "Evidence",
    description: "EvidenceStore 检索与对象详情",
  },
  {
    id: "Policy",
    title: "Policy",
    description: "策略裁决解释与安全边界",
  },
  {
    id: "Supply Chain",
    title: "Supply Chain",
    description: "镜像可信度与签名发布门禁",
  },
  {
    id: "Agent Trace",
    title: "Agent Trace",
    description: "AI Advisor 可观测链路",
  },
  {
    id: "Approval",
    title: "Approval",
    description: "人工审批与执行申请",
  },
  {
    id: "Environment",
    title: "Environment",
    description: "环境上下文与多环境证据",
  },
] as const

export type PortalWorkspace = (typeof portalWorkspaces)[number]["id"]

export const defaultPortalWorkspace: PortalWorkspace = "Evidence"
