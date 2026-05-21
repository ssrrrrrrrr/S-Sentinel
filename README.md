# S Sentinel

## 1. 项目简介

S Sentinel 是一个面向云原生发布可靠性的 SLO 驱动发布控制平台原型。

项目的核心目标是：在应用发布过程中，不只判断 Pod 是否启动成功，而是结合业务 SLO、渐进式发布策略、运行时证据、策略裁决、AI 分析和人工审批，判断一次发布是否真正安全、可靠、可继续推进。

当前项目已经从最初的 SLO Rollout Demo 演进为一个平台式 Release Control Plane，重点解决以下问题：

- 本次发布是否满足 SLO？
- Canary 是否可以继续放量？
- 发布失败时，失败原因是什么？
- AI 可以给出什么只读分析和调查建议？
- 策略是否允许建议动作进入下一步？
- 供应链、镜像、GitOps 目标状态是否可信？
- 整个发布过程是否可追溯、可审计、可复盘？

S Sentinel 当前默认保持只读安全边界：

```text
readOnly = true
willExecute = false
requiresHumanApprovalForExecution = true
```

也就是说，平台当前只做分析、证据汇聚、策略判断和执行申请，不自动执行 rollback、promote、patch、delete、commit、push 等高风险动作。

---

## 2. 实现功能

### 2.1 SLO-as-Code

项目通过 `configs/services/*.slo.yaml` 定义服务级 SLO 配置，当前 demo-app 包含：

- `request-count`
- `error-rate`
- `p95-latency`

对应 schema 位于 `schemas/slo-config.schema.json`。

### 2.2 Progressive Delivery Strategy

项目通过 `configs/services/*.strategy.yaml` 定义渐进式发布策略，当前支持 Canary 策略描述，包括：

- 流量步骤
- 暂停时间
- SLO 分析指标
- 失败策略
- 人工审批策略

对应 schema 位于 `schemas/progressive-delivery-strategy.schema.json`。

### 2.3 GitOps 发布链路

项目保留 GitHub Actions + GitOps + Argo CD + Argo Rollouts 的发布链路。

`demo-app/release-gitops.sh` 负责生成或更新发布相关 Kubernetes Manifest，并通过 Argo Rollouts 执行 Canary 发布和 Prometheus AnalysisRun 检查。

### 2.4 Release Watcher

`watcher` 用于感知 Rollout 和 AnalysisRun 状态变化，并生成发布上下文与证据。

它会输出：

- Release Context
- Release Event Archive
- Release Result
- Risk Score
- Recommended Action

### 2.5 Evidence Control Plane

项目已经形成发布证据控制平面，核心对象包括：

- `ReleaseContext`
- `ReleaseEvidence`
- `EvidenceRecord`
- `ReleaseTimeline`
- `ReleaseSummary`
- `ReleaseMemory`
- `ReleaseIntelligence`

这些对象用于把一次发布从触发、观测、判断、建议、策略裁决到人工审批的过程串成完整证据链。

### 2.6 Policy Guard

项目通过 `scripts/evaluate-agent-decision.sh` 和 `policy/release-policy.yaml` 实现策略守卫。

Policy Guard 会根据发布结果、AI 建议动作、渐进式发布策略和安全规则进行二次裁决，决定动作是：

- 允许观察
- 要求人工审批
- 拒绝执行

### 2.7 Read-only AI Release Agent

项目已经引入只读 AI Release Agent。

Agent 只负责读取证据、总结风险、生成建议，不直接修改 Kubernetes、GitOps、镜像或代码仓库。

对应对象包括：

- `AgentRun`
- `PlanRun`
- `ExecutionRequest`

### 2.8 Agent Planning + RAG

项目支持基于历史发布记忆的轻量 RAG 规划。

`PlanRun` 会从 Release Memory 中检索相似发布记录，为当前失败发布生成调查步骤和候选后续动作。

当前实现是规则检索版本，适合作为后续语义检索和向量化 RAG 的安全基线。

### 2.9 Policy-bound Execution Request

项目将“建议动作”和“真实执行”拆开。

`ExecutionRequest` 只生成策略约束下的执行申请，记录请求动作、请求原因、策略绑定、审批状态、证据引用和安全边界。

当前所有执行申请都保持：

```text
mode = request_only
willExecute = false
```

### 2.10 Supply Chain Safety

项目通过 `SupplyChainDecision` 对发布对象做只读供应链检查，包括：

- release version 是否存在
- commit 是否存在
- image reference 是否存在
- image digest 是否存在
- 是否使用 mutable tag
- GitOps 目标版本是否和 release version 对齐

对应 schema 位于 `schemas/supply-chain-decision.schema.json`。

### 2.11 Multi-env & Packaging

项目已经引入多环境配置：

- `configs/environments/dev.yaml`
- `configs/environments/staging.yaml`
- `configs/environments/prod.yaml`

环境配置包含 cluster、namespace、GitOps overlay、policy profile、supply chain 默认规则和安全默认值。

### 2.12 Release Portal

`web` 是 S Sentinel 的前端控制台，用于展示一次发布关联的控制平面对象。

当前 Portal 已经支持：

- 发布列表
- 发布详情
- Evidence 展示
- Release Summary
- Intelligence
- Action Plan
- AI Advice
- Timeline
- Runbook
- RCA
- Environment-aware View
- Control-plane Object Cards

Portal 当前也是只读入口，不提供直接执行入口。

---

## 3. 项目架构

### 3.1 总体链路

```text
SLOConfig / ProgressiveDeliveryStrategy / EnvironmentConfig
  -> GitOps Release Pipeline
  -> Argo CD
  -> Argo Rollouts
  -> Prometheus AnalysisRun
  -> Release Watcher
  -> Release Context
  -> AI Decision
  -> Policy Decision
  -> Release Evidence
  -> Evidence Record
  -> Agent Run / Plan Run / Execution Request / Supply Chain Decision
  -> Release Portal
```

### 3.2 目录结构

| 目录 | 说明 |
|---|---|
| `.github/workflows` | GitHub Actions 发布与契约测试 |
| `configs/environments` | dev、staging、prod 多环境配置 |
| `configs/services` | 服务级 SLO 和渐进式发布策略 |
| `demo-app` | 示例业务应用与 GitOps 发布脚本 |
| `deploy` | Kubernetes、Argo Rollouts、Prometheus、Grafana 相关 Manifest |
| `docs` | 项目文档与 Release Portal API 文档 |
| `policy` | 发布策略与安全规则 |
| `schemas` | S Sentinel 控制面对象 JSON Schema |
| `scripts` | 证据生成、AI 分析、策略裁决、测试与校验脚本 |
| `tests` | 发布契约测试 fixtures |
| `watcher` | Release Watcher 与 Release Portal API |
| `web` | S Sentinel Release Portal 前端 |

### 3.3 控制面对象

S Sentinel 当前围绕以下控制面对象组织发布可靠性能力：

| 对象 | 作用 |
|---|---|
| `SLOConfig` | 定义服务发布健康标准 |
| `ProgressiveDeliveryStrategy` | 定义 Canary 放量和失败处理策略 |
| `EnvironmentConfig` | 定义环境、集群、命名空间、GitOps overlay 和安全默认值 |
| `ReleaseContext` | 记录一次发布的运行时上下文 |
| `ReleaseEvidence` | 汇总一次发布的证据索引 |
| `EvidenceRecord` | 面向控制平面的证据记录 |
| `AIDecision` | AI 发布分析结果 |
| `PolicyDecision` | 策略裁决结果 |
| `AgentRun` | 只读 AI Agent 运行记录 |
| `PlanRun` | 基于证据和历史记忆生成的调查计划 |
| `ExecutionRequest` | 策略约束下的执行申请 |
| `SupplyChainDecision` | 发布对象供应链安全判断 |

### 3.4 安全边界

S Sentinel 当前定位为只读发布可靠性控制平面。

系统可以：

- 读取发布状态
- 汇聚发布证据
- 分析失败原因
- 生成调查计划
- 生成执行申请
- 记录人工审批
- 展示 Portal 视图

系统不会自动：

- rollback
- promote
- patch Kubernetes 资源
- delete Kubernetes 资源
- 修改 GitOps Manifest
- 构建或推送镜像
- commit 或 push 代码
