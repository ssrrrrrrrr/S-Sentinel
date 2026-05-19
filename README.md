# SLO Rollout Demo

## 1. 项目简介

SLO Rollout Demo 是一个基于 Kubernetes 的云原生发布可靠性项目。

项目最初目标是：在应用发布过程中，不只判断 Pod 是否启动成功，而是通过业务指标判断新版本是否真正健康，并在异常时自动中止发布。

随着功能持续演进，项目已经从一个简单的 GitOps 灰度发布 Demo，升级为一个面向云原生发布可靠性的 SLO 驱动智能分析平台原型。

当前项目围绕以下核心问题展开：

- 发布是否真的成功？
- 新版本是否满足业务 SLO？
- 发布失败时失败原因是什么？
- 系统应该建议什么动作？
- 历史上是否出现过类似失败？
- 人工最终如何审批和留痕？
- 整个发布过程是否可追溯、可审计？

项目当前已经完成 watcher v1.20 版本验收，具备健康发布、故障发布、历史智能分析和人工审批记录的完整闭环。

---

## 2. 实现功能

### 2.1 GitOps 发布

项目支持通过 GitHub Actions 手动触发发布。

发布参数包括：

- `image_tag`
- `app_version`
- `fault_rate`
- `latency_ms`
- `slo_error_rate_threshold`
- `slo_p95_seconds_threshold`
- `slo_min_request_count`

发布流程会构建应用镜像，更新 GitOps Manifest，并由 Argo CD 将目标状态同步到 Kubernetes 集群。

### 2.2 Canary 灰度发布

项目使用 Argo Rollouts 实现 Canary 发布。

新版本不会一次性全量替换，而是逐步放量，并在发布过程中执行 AnalysisRun 检查业务指标。

当指标达标时继续放量；当指标异常时停止发布或进入降级状态。

### 2.3 SLO 发布门禁

项目通过 Prometheus 指标判断新版本是否健康。

当前核心 SLO 指标包括：

- `request-count`
- `error-rate`
- `p95-latency`

典型发布结果包括：

- `PASS`
- `FAIL_BY_ERROR_RATE`
- `FAIL_BY_P95_LATENCY`
- `FAIL_BY_MULTIPLE_SLO`

其中 `request-count` 用于避免低流量误判，`error-rate` 和 `p95-latency` 用于判断新版本是否出现错误率升高或性能退化。

### 2.4 故障注入

`demo-app` 支持通过发布参数注入故障：

- `FAULT_RATE`
- `LATENCY_MS`

因此项目可以主动验证：

- 正常健康发布
- 高错误率发布
- 高延迟发布
- 多 SLO 同时失败发布

这使项目不仅能演示成功发布，也能演示异常发布时的自动分析、证据生成和审批链路。

### 2.5 可观测能力

项目接入了完整观测链路：

- Prometheus
- Grafana
- Alertmanager

Grafana Dashboard 已经纳入仓库管理，具备 Dashboard as Code 能力。

发布判断不只依赖 Kubernetes 资源状态，而是结合真实业务指标进行分析。

### 2.6 Release Watcher

项目包含独立的 Release Watcher 组件，用于感知 Rollout 和 AnalysisRun 状态变化，并生成发布相关证据。

当前线上 watcher 镜像版本为：

```text
192.168.30.11:5000/release-rollout-watcher:v1.20
```

Watcher 当前保持安全模式：

```text
watch-only
advisory_only
dry_run
approval_record_only
```

它不会自动执行 Rollback、Promote、Patch、Delete 等高风险操作。

### 2.7 Release Evidence

Release Evidence 是一次发布的证据总索引。

它会关联：

- Release Context
- Release Report
- AI Advice
- AI Decision
- Policy Decision
- Release Summary
- Failure Evidence
- Action Plan
- Release Memory
- Release Intelligence
- Approval Record

通过 Release Evidence，可以追溯一次发布从触发、分析、判断、建议动作到人工审批的完整过程。

### 2.8 AI Release Advisor

AI Release Advisor 用于读取发布报告和变更上下文，并生成辅助分析结论。

它会输出：

- 发布结论
- 风险判断
- 失败指标
- 建议动作
- 下一步处理建议

AI Advisor 当前只负责分析和建议，不直接执行集群写操作。

### 2.9 Policy-as-Code Guardrails

项目引入了 Policy-as-Code 安全策略层。

策略文件位于：

```text
policy/release-policy.yaml
```

策略层用于限制高风险动作，确保系统默认保持 advisory-only。

即使 AI 建议执行高风险动作，Policy Evaluator 也会进行二次裁决，避免自动化误操作扩大故障。

### 2.10 Failure Evidence

当发布失败时，系统会生成 Failure Evidence。

Failure Evidence 会记录：

- 是否失败
- 失败指标
- 风险等级
- 风险分数
- Rollout 状态
- AnalysisRun 状态
- 可选 Kubernetes 现场证据
- 安全边界说明

它的作用是把失败现场沉淀为结构化证据，便于后续排查和复盘。

### 2.11 Dry-run Action Plan

Action Plan 用于把发布判断转化为可审计动作计划。

例如多 SLO 失败时，Action Plan 会给出：

- 查看 Rollout 的只读命令
- 查看 AnalysisRun 的只读命令
- 候选 abort 命令

但所有动作都保持：

```text
executionMode = dry_run
willExecute = false
```

也就是说，Action Plan 只生成建议，不自动执行。

### 2.12 Release Memory

Release Memory 用于沉淀历史发布记录。

核心产物包括：

```text
release-memory.jsonl
release-memory-latest.json
```

它可以记录历史上的成功发布、失败发布、失败指标、最终动作和相关证据。

### 2.13 Release Intelligence

Release Intelligence 基于 Release Evidence 和 Release Memory，对当前发布进行历史相似风险判断。

典型风险模式包括：

- `healthy_release`
- `new_slo_failure_pattern`
- `similar_slo_failure_pattern`
- `repeated_slo_failure_pattern`

它可以判断当前失败是否和历史失败相似，并将结论写入 Release Summary 和 AI Advice。

### 2.14 Human Approval Record

项目支持人工审批记录能力。

审批状态包括：

- `APPROVED`
- `REJECTED`
- `DEFERRED`
- `NEEDS_MORE_EVIDENCE`

审批记录会写回 Release Evidence，并同步汇入 Release Summary 和 AI Advice。

即使人工审批为 `APPROVED`，系统仍然不会自动执行动作：

```text
executionMode = approval_record_only
willExecute = false
```

### 2.15 v1.20 真实验收结果

watcher v1.20 已完成真实环境验收。

健康发布验收结果：

```text
releaseResult = PASS
policyDecision = ALLOW
finalAction = NOOP
actionPlan.executionMode = dry_run
actionPlan.willExecute = false
releaseIntelligence.riskPattern = healthy_release
```

多 SLO 失败发布验收结果：

```text
releaseResult = FAIL_BY_MULTIPLE_SLO
policyDecision = ALLOW_ADVISORY_ONLY
finalAction = STOP_PROMOTION
requiresHumanApproval = true
failureEvidence.isFailure = true
actionPlan.executionMode = dry_run
actionPlan.willExecute = false
releaseIntelligence.riskPattern = repeated_slo_failure_pattern
```

人工审批链路验收结果：

```text
approvalDecision = APPROVED
approvedAction = STOP_PROMOTION
executionMode = approval_record_only
willExecute = false
approvalRef.generated = true
summary_has_approval = true
advice_has_approval = true
```

---

## 3. 项目架构

### 3.1 发布主链路

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
Prometheus AnalysisRun
↓
PASS / FAIL 判断
```

### 3.2 分析与证据链路

```text
Rollout / AnalysisRun 状态变化
↓
Release Watcher
↓
ChangeContext
↓
Release Report
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
↓
Release Memory
↓
Release Intelligence
↓
Release Summary / AI Advice
↓
Human Approval Record
```

### 3.3 组件职责

| 组件 | 职责 |
|---|---|
| GitHub Actions | 手动发布入口，接收发布参数 |
| release-gitops.sh | 构建镜像、生成 GitOps Manifest |
| Git Repository | 保存 Kubernetes 目标状态 |
| Argo CD | 将 Git 中的目标状态同步到集群 |
| Argo Rollouts | 执行 Canary 灰度发布 |
| Prometheus | 采集业务指标并提供查询 |
| AnalysisRun | 根据 SLO 指标判断新版本健康状态 |
| Grafana | 展示请求量、错误率、延迟等指标 |
| Alertmanager | 接收发布异常告警 |
| Release Watcher | 感知发布状态并生成证据链 |
| AI Release Advisor | 生成发布分析和建议动作 |
| Policy Evaluator | 根据策略裁决建议动作是否安全 |
| Release Evidence | 汇总一次发布的完整证据索引 |
| Failure Evidence | 记录失败诊断证据 |
| Action Plan | 生成 dry-run 动作计划 |
| Release Memory | 记录历史发布记忆 |
| Release Intelligence | 判断历史相似风险 |
| Human Approval Record | 记录人工审批结果 |
| Agent Tool Router | 提供受控工具入口 |


