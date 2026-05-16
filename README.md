# SLO Rollout Demo

## 1. 项目简介

SLO Rollout Demo 是一个基于 Kubernetes 的灰度发布治理项目。

项目核心目标是：在应用发布过程中，不只判断 Pod 是否运行成功，而是通过业务指标判断新版本是否真的健康。

项目通过 GitHub Actions 触发发布，Argo CD 负责 GitOps 同步，Argo Rollouts 执行 Canary 灰度发布，Prometheus 提供 SLO 指标判断，Grafana 展示发布过程，Alertmanager 提供告警能力，并通过本地大模型生成发布分析报告。

整体流程如下：

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
Grafana / Alertmanager / AI Advisor 辅助观测与分析
```


---

## 2. 实现能力

### 2.1 GitOps 发布能力

项目支持通过 GitHub Actions 手动触发发布。

发布时可以指定：

- 镜像版本
- 应用版本
- 故障率
- 延迟参数

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

- `request-count`：最小请求量门禁，避免样本量不足时误判。
- `error-rate`：5xx 错误率门禁，用于判断新版本是否产生大量错误。
- `p95-latency`：P95 延迟门禁，用于判断新版本是否存在明显性能劣化。

当新版本错误率过高或延迟超过阈值时，Argo Rollouts 会自动中止发布。

---

### 2.4 可观测能力

项目接入了 Prometheus、Grafana 和 Alertmanager。

Grafana Dashboard 展示：

- 各版本 QPS
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

### 2.6 Release Report 自动采集

项目提供 `collect-release-report.sh` 脚本，用于自动采集一次发布相关上下文。

采集内容包括：

- Rollout 状态
- AnalysisRun 结果
- Pod 版本分布
- Kubernetes Events
- Argo CD Application 状态
- Git commit
- Prometheus 请求量、错误率、P95 延迟指标

这样发布失败后，不需要手动一条条查询命令，可以直接生成一份发布分析报告。

---

### 2.7 AI Release Advisor

项目接入本地 Ollama 大模型作为发布分析助手。

AI Advisor 会读取 Release Report，并生成分析结果，包括：

- 当前发布是否成功
- 失败指标是什么
- 影响范围是什么
- 可能原因是什么
- 建议处理动作是什么

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
Rollback / Abort Decision
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
| Grafana | 展示发布过程中的 QPS、错误率和延迟 |
| Alertmanager | 接收发布异常告警 |
| Release Report | 自动采集发布失败上下文 |
| Ollama / AI Advisor | 基于发布报告生成分析建议 |

