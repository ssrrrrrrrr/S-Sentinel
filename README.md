# SLO Rollout Demo

## 1. 项目简介

SLO Rollout Demo 是一个基于 Kubernetes 的云原生发布可靠性项目。

项目早期目标是：在应用发布过程中，不只判断 Pod 是否运行成功，而是通过业务指标判断新版本是否真的健康，并在异常时自动中止发布。

随着功能演进，项目已经从一个：

- 基于 GitOps 的 SLO 灰度发布 Demo

逐步升级为一个：

- 具备云原生部署形态的发布可靠性智能分析平台雏形

项目当前主链路如下：

```text
GitHub Actions 发布新版本
↓
GitOps Manifest 更新
↓
Argo CD 同步到 Kubernetes
↓
Argo Rollouts 执行 Canary 发布
↓
Prometheus 采集业务指标
↓
AnalysisRun 判断 SLO 是否达标
↓
异常版本自动中止发布
↓
Release Watcher 感知发布状态
↓
ChangeContext / Release Report / AI Advisor 生成
```

整体目标不再只是“把应用发布出去”，而是逐步建设一套：

- 能感知变更
- 能判断风险
- 能沉淀上下文
- 能辅助决策

的云原生发布可靠性平台。

---

## 2. 实现能力

### 2.1 GitOps 发布能力

项目支持通过 GitHub Actions 手动触发发布。

发布时可以指定：

- 镜像版本
- 应用版本
- 故障率
- 延迟参数
- SLO 错误率阈值
- SLO P95 延迟阈值
- SLO 最小请求量阈值

GitHub Actions 会根据输入参数生成新的 Kubernetes YAML，并提交到 Git 仓库。Argo CD 监听 Git 仓库变化后，将期望状态同步到 Kubernetes 集群。

---

### 2.2 Canary 灰度发布能力

项目使用 Argo Rollouts 代替普通 Deployment，实现 Canary 发布。

新版本不会一次性替换所有 Pod，而是先进入灰度阶段。只有当新版本通过 SLO 检查后，才继续放量。

如果新版本指标异常，Rollout 会自动中止发布，并保留稳定版本。

---

### 2.3 SLO 发布门禁能力

项目使用 Prometheus 指标作为发布质量判断依据。

当前主要有三个发布门禁：

- `request-count`：最小请求量门禁，避免样本量不足时误判
- `error-rate`：5xx 错误率门禁，用于判断新版本是否产生大量错误
- `p95-latency`：P95 延迟门禁，用于判断新版本是否存在明显性能劣化

这些门禁阈值已经支持参数化，不再完全写死在脚本中。

---

### 2.4 可观测能力

项目接入了 Prometheus、Grafana 和 Alertmanager。

Grafana Dashboard 展示：

- 各版本请求量
- 各版本 5xx 错误率
- 各版本 P95 延迟

Alertmanager 用于接收发布异常告警，例如 Canary 版本错误率过高、延迟过高等。

---

### 2.5 Dashboard as Code

Grafana Dashboard 不再只通过页面手动创建，而是以 JSON 文件形式存放在 Git 仓库中，并通过 ConfigMap 由 Argo CD 同步到集群。

这样可以保证：

- Dashboard 可以版本化管理
- Grafana 重启后 Dashboard 不丢失
- 换环境后可以自动恢复观测面板

---

### 2.6 Release Watcher 能力

项目提供独立的 Release Watcher 组件，用于感知发布过程中的 Rollout、AnalysisRun 和相关状态变化。

Watcher 当前承担的职责包括：

- 感知发布阶段变化
- 采集发布上下文
- 生成发布报告相关产物
- 将产物落盘到 NFS / 持久化目录
- 暴露自身指标供 Prometheus 采集

这使项目从“只会发版”升级到“能持续跟踪发布过程”。

---

### 2.7 ChangeContext 生成能力

项目已经具备生成 `ChangeContext` 的能力，用于描述一次发布的结构化上下文。

当前可覆盖的信息包括：

- 镜像是否变化
- 环境变量是否变化
- SLO 门禁参数是否变化
- 风险级别与风险提示
- 发布前后上下文摘要

这为后续的 AI 分析、Release Memory 和控制器化演进打下了基础。

---

### 2.8 Release Report 自动生成能力

项目提供标准化的 Release Report 生成能力。

报告中当前可以写入：

- `release_id`
- `image_tag`
- `app_version`
- `namespace`
- `rollout_name`
- SLO 输入参数
- 观测指标值
- 发布结果字段
- 原因字段

这样发布过程中的关键信息不再只是散落在日志、kubectl 命令和 Prometheus 图表中，而是被统一收敛成结构化报告。

---

### 2.9 发布观测值自动写入能力

项目已经实现将 Prometheus 观测值自动写入 Release Report。

当前已写入的核心指标包括：

- `request_count_1m`
- `error_rate_percent`
- `p95_latency_seconds`

这意味着报告已经不再只是描述性文档，而是开始承载发布时的真实数据事实。

---

### 2.10 发布结果阶段化写入能力

项目已经开始将发布结果写入报告中的 `result` 和 `reason` 字段。

当前能力是：

- 可以写入阶段性结果，例如 `IN_PROGRESS`
- 可以写入阶段性原因，例如 `Rollout phase not available yet`

这说明项目已经从“只输出观测值”演进到“开始输出发布判断结果”。

---

### 2.11 AI Release Advisor

项目接入本地 AI 分析链路，用于对 Release Report 做进一步解释和建议生成。

AI Advisor 当前定位是：

- 读取发布报告
- 读取变更上下文
- 输出辅助分析结论
- 提供建议动作

当前 AI 只做只读分析，不直接执行回滚、删 Pod 或修改集群状态。

---

## 3. 项目架构

### 3.1 整体架构

```text
Developer / SRE
↓
GitHub Actions
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
ChangeContext / Release Report / AI Advisor
```

观测与分析链路：

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
```

---

### 3.2 组件职责

| 组件 | 职责 |
|---|---|
| GitHub Actions | 发布入口，负责构建和生成 GitOps Manifest |
| Git Repository | 保存应用期望状态和配置 |
| Argo CD | 监听 Git 仓库并同步 Kubernetes 资源 |
| Argo Rollouts | 执行 Canary 发布和发布中止 |
| Prometheus | 采集业务指标并提供查询能力 |
| AnalysisRun | 根据 Prometheus 指标判断新版本是否健康 |
| Grafana | 展示发布过程中的请求量、错误率和延迟 |
| Alertmanager | 接收发布异常告警 |
| Release Watcher | 感知发布状态并生成上下文与报告 |
| ChangeContext | 描述一次发布的结构化变更信息 |
| Release Report | 收敛发布期间的观测值与判断结果 |
| AI Release Advisor | 基于发布报告生成分析建议 |
