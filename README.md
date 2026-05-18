# SLO Rollout Demo

## 1. 项目简介

SLO Rollout Demo 是一个基于 Kubernetes 的云原生发布可靠性项目。

项目最初的目标是：在应用发布过程中，不只判断 Pod 是否启动成功，而是通过业务指标判断新版本是否真正健康，并在异常时自动中止发布。

随着功能持续演进，项目已经从一个：

> 基于 GitOps 的 SLO 灰度发布 Demo

逐步升级为一个：

> 具备云原生部署形态的发布可靠性智能分析平台雏形

项目当前主链路如下：

```text
GitHub Actions 手动触发发布
↓
release-gitops.sh 构建镜像并生成 GitOps Manifest
↓
Git Repository 更新 deploy/base 下的目标状态
↓
Argo CD 从 Git 拉取并同步到 Kubernetes
↓
Argo Rollouts 执行 Canary 发布
↓
Prometheus 采集业务指标并执行 AnalysisRun
↓
异常版本自动中止，正常版本继续放量
↓
Release Watcher 感知 Rollout / AnalysisRun 状态
↓
生成 ChangeContext / Release Report
↓
AI Release Advisor 生成结构化发布判断
↓
Policy-as-Code Guardrails 执行安全裁决
↓
Release Evidence 汇总证据链
↓
Failure Evidence 生成失败诊断证据
↓
Dry-run Action Plan 生成可审计动作计划
```

项目目标已经不再只是“把应用发布出去”，而是在发布过程中逐步具备：

- 变更感知能力
- 风险判断能力
- 发布过程结构化记录能力
- 发布观测值回填能力
- 智能分析与辅助决策能力
- 策略化安全边界能力
- 失败诊断证据沉淀能力
- dry-run 动作计划生成能力

从而向一个面向云原生变更可靠性的长期平台演进。

---

## 2. 实现能力

### 2.1 GitOps 发布能力

项目支持通过 GitHub Actions 手动触发发布。

发布参数当前支持：

- `image_tag`
- `app_version`
- `fault_rate`
- `latency_ms`
- `slo_error_rate_threshold`
- `slo_p95_seconds_threshold`
- `slo_min_request_count`

GitHub Actions 会根据输入参数执行发布脚本，构建镜像、推送镜像，并渲染新的 GitOps Manifest 到仓库中。Argo CD 会感知 Git 变化并同步 Kubernetes 目标状态。

### 2.2 Canary 灰度发布能力

项目使用 Argo Rollouts 实现 Canary 发布，而不是直接使用原生 Deployment 全量替换。

当前发布流程中：

- 新版本先按 Canary 步进进入集群
- 每个阶段会经过 AnalysisRun 检查
- 指标达标才继续放量
- 指标异常则中止或停留在当前阶段

这样可以把“发版”从一次性替换升级为可观测、可中止、可回退的渐进式发布过程。

### 2.3 SLO 发布门禁能力

项目当前已实现基于业务指标的发布门禁，核心指标包括：

- `request-count`
- `error-rate`
- `p95-latency`

其中：

- `request-count` 用于避免低流量样本不足造成误判
- `error-rate` 用于判断新版本是否出现异常错误
- `p95-latency` 用于判断新版本是否出现性能退化

这些门禁阈值已经支持参数化输入，不再完全写死在发布脚本里。

### 2.4 应用级故障注入与实验能力

`demo-app` 当前支持发布级别的可控实验参数：

- `FAULT_RATE`
- `LATENCY_MS`

这使项目不仅能验证正常发布，还可以主动制造：

- 高错误率版本
- 高延迟版本
- 多 SLO 同时失败版本

从而演示发布门禁、Rollout 中止和后续报告生成是否正常工作。

### 2.5 可观测能力

项目当前接入了完整的观测链路：

- Prometheus
- Grafana
- Alertmanager

Grafana 可用于观察：

- 各版本请求量
- 各版本错误率
- 各版本延迟情况

Alertmanager 可用于接收发布异常告警。

这意味着发布不再只是看 `kubectl rollout status`，而是有完整的业务指标支持。

### 2.6 Dashboard as Code

Grafana Dashboard 已经纳入仓库，以配置文件形式进行管理，并通过 GitOps 同步到集群。

这样可以保证：

- Dashboard 可版本化管理
- 观测面板可跟随环境自动恢复
- Grafana 重建后面板不丢失
- 发布平台的观测层也具备 IaC / GitOps 能力

### 2.7 Release Watcher 能力

项目已经具备独立的 Release Watcher 组件。

Watcher 当前职责包括：

- 感知 Rollout 状态变化
- 感知 AnalysisRun 结果
- 汇总发布上下文
- 生成发布报告相关产物
- 将结果落盘到持久化目录
- 暴露自身指标供 Prometheus 采集

当前线上 watcher 镜像版本为：

```text
192.168.30.11:5000/release-rollout-watcher:v1.19
```

Watcher 当前运行在 `watch-only` 模式，不直接执行 Rollback、Promote、Patch、Delete 等高风险动作。

### 2.8 ChangeContext 生成能力

项目已支持生成 ChangeContext，用于描述一次发布的结构化变更上下文。

当前可覆盖的信息包括：

- 镜像是否变化
- 环境变量是否变化
- SLO 门禁参数是否变化
- 风险级别
- 风险提示
- 发布前后上下文摘要

这为后续做 Release Memory、AI 决策结构化输出和 Controller 化演进提供了基础。

### 2.9 Release Report 自动生成能力

项目当前可以自动生成标准化 Release Report。

报告中可写入的信息包括：

- `release_id`
- `image_tag`
- `app_version`
- `namespace`
- `rollout_name`
- SLO 输入参数
- 发布观测值
- 发布结果字段
- 原因字段

这意味着发布期间的关键信息不再散落在日志与终端中，而是被统一沉淀为结构化报告。

### 2.10 发布观测值自动写入能力

项目已经实现将 Prometheus 观测值自动写入 Release Report。

当前已回填的核心指标包括：

- `request_count_1m`
- `error_rate_percent`
- `p95_latency_seconds`

这使报告从“描述性文档”升级为“带真实观测数据的发布事实记录”。

### 2.11 发布结果阶段化写入能力

项目当前已经开始将发布结果写入报告中的 `result` 和 `reason` 字段。

目前支持的典型结果包括：

- `IN_PROGRESS`
- `PASS`
- `FAIL_BY_ERROR_RATE`
- `FAIL_BY_P95_LATENCY`
- `FAIL_BY_MULTIPLE_SLO`

这说明项目已经从“记录发布现象”进一步迈向“表达发布判断”。

### 2.12 AI Release Advisor

项目已接入 AI Release Advisor 分析链路，用于对发布报告和变更上下文做进一步解释。

当前 AI Advisor 的定位是：

- 读取发布报告
- 读取变更上下文
- 输出辅助分析结论
- 提供建议动作
- 生成结构化 AI Decision

目前 AI 只提供分析与建议，不直接对集群执行高风险写操作。

### 2.13 Policy-as-Code Guardrails

项目已经引入 Policy-as-Code 安全策略层。

策略文件位于：

```text
policy/release-policy.yaml
```

它用于约束 Agent 或 AI Advisor 的动作边界。

当前策略重点包括：

- 默认 `advisory_only`
- 禁止自动执行高风险动作
- 禁止自动 Rollback
- 禁止自动 Promote
- 禁止自动 Patch Kubernetes
- 禁止自动 Delete 资源
- 所有高风险动作需要人工确认

即使 AI Decision 中建议了危险动作，Policy Evaluator 也会进行二次裁决。

### 2.14 Release Evidence 证据包

项目当前可以生成 Release Evidence 证据包。

Release Evidence 用于汇总一次发布的核心证据链，包括：

- Release Context
- Release Report
- AI Advice
- AI Decision
- Policy Decision
- Release Summary
- Failure Evidence
- Action Plan

它的定位是一次发布的总索引，使发布分析、审计和复盘都可以从一个入口展开。

### 2.15 Failure Evidence 失败诊断证据

项目当前支持在失败场景自动生成 Failure Evidence。

Failure Evidence 会沉淀：

- 是否失败
- 失败的 SLO 指标
- 风险等级
- 风险分数
- ReleaseContext 快照
- 可选 K8s 现场证据
- 下一步建议
- 安全边界说明

默认情况下，K8s 现场采集保持关闭，避免对集群造成额外影响。

### 2.16 Agent Tool Router

项目已经引入统一的 Agent 工具入口：

```text
scripts/agent-tool-router.sh
```

当前支持的安全工具包括：

- `list-tools`
- `get-latest-release-summary`
- `get-latest-release-evidence`
- `get-latest-failure-evidence`
- `collect-failure-evidence`
- `evaluate-change-risk`
- `build-action-plan`
- `run-offline-eval`

这个 Router 的意义是：Agent 不直接调用分散脚本，而是通过受控工具入口调用白名单能力。

### 2.17 Dry-run Action Plan

项目已经支持生成 dry-run 动作计划。

Action Plan 会根据 Release Evidence 生成：

- 建议动作
- 是否被策略阻断
- 是否需要人工审批
- 候选命令
- 人工处理步骤
- 安全边界

所有 Action Plan 都保持：

```text
executionMode = dry_run
willExecute = false
```

即使出现类似：

```text
kubectl argo rollouts abort demo-app -n slo-rollout
```

也只是候选命令，不会自动执行。

---

## 3. 项目架构

### 3.1 整体架构

```text
Developer / SRE
↓
GitHub Actions
↓
release-gitops.sh
↓
Git Repository
↓
Argo CD
↓
Kubernetes Cluster
↓
Argo Rollouts
↓
demo-app Canary Release
↓
Prometheus SLO Analysis
↓
Abort / Continue Decision
↓
Release Watcher
↓
ChangeContext / Release Report
↓
AI Release Advisor
↓
Policy Evaluator
↓
Release Evidence
↓
Failure Evidence
↓
Dry-run Action Plan
```

观测与分析链路如下：

```text
demo-app metrics
↓
Prometheus
↓
Grafana Dashboard
↓
Alertmanager
↓
Release Watcher
↓
ChangeContext JSON
↓
Release Report
↓
AI Release Advisor
↓
Policy-as-Code
↓
Release Evidence
↓
Action Plan
```

### 3.2 组件职责

| 组件 | 职责 |
|---|---|
| GitHub Actions | 发布入口，负责接收参数并启动发布流程 |
| release-gitops.sh | 构建镜像、生成 Manifest、触发报告链路 |
| Git Repository | 保存应用目标状态与发布配置 |
| Argo CD | 监听 Git 仓库并同步 Kubernetes 资源 |
| Argo Rollouts | 执行 Canary 发布与发布中止 |
| Prometheus | 采集业务指标并提供查询能力 |
| AnalysisRun | 根据业务指标判断新版本是否健康 |
| Grafana | 展示发布过程中的请求量、错误率和延迟 |
| Alertmanager | 接收发布异常告警 |
| Release Watcher | 感知发布状态并生成上下文与报告 |
| ChangeContext | 描述一次发布的结构化变更信息 |
| Release Report | 收敛发布期间的观测值与判断结果 |
| AI Release Advisor | 基于发布报告和上下文生成分析建议 |
| Policy Evaluator | 根据 Policy-as-Code 裁决 Agent 建议动作 |
| Release Evidence | 汇总一次发布的完整证据链 |
| Failure Evidence | 生成失败诊断证据 |
| Agent Tool Router | 提供受控 Agent 工具入口 |
| Dry-run Action Plan | 生成可审计、不可自动执行的动作计划 |

---

## 4. 当前安全边界

当前项目仍保持安全优先：

- 不自动 Rollback
- 不自动 Promote
- 不自动 Patch Kubernetes
- 不自动 Delete 资源
- 不自动修改 GitOps
- 不自动执行 Action Plan
- 所有动作计划均为 dry-run
- 高风险动作需要人工确认

项目中的 Agent / AI 能力定位为：

> 辅助分析、生成证据、提供建议、形成 dry-run 动作计划，而不是直接替代人工执行生产操作。

---

## 5. 当前版本状态

当前 Release Watcher 线上版本：

```text
192.168.30.11:5000/release-rollout-watcher:v1.19
```

v1.19 主要包含：

- Policy-as-Code Guardrails
- Failure Evidence 自动生成
- Release Evidence 总索引
- Agent Tool Router
- Dry-run Action Plan
- Action Plan 接入 AI Advisor 主链路
- watcher v1.19 线上运行验证

---

## 6. 项目定位

这个项目当前更接近：

> Agentic Release Reliability Platform Prototype

也就是一个面向云原生发布可靠性的智能分析平台雏形。

它不是简单的“发布脚本”，而是在逐步具备：

- 变更上下文理解
- 发布风险判断
- SLO 门禁判断
- 失败证据采集
- AI 辅助解释
- Policy 安全治理
- Agent 工具契约
- dry-run 执行计划

最终目标是形成一个安全、可审计、可演进的云原生发布可靠性平台。
