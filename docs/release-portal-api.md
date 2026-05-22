# Release Portal API

## 1. 功能定位

Release Portal API 是 Release Watcher 提供的只读发布查询接口。

它的目标是把 `docs/release-reports` 或线上挂载目录中的发布证据统一暴露为 HTTP API，使一次发布的证据链可以被查询、追溯和审计。

它主要解决三个问题：

- 查询最近一次发布的证据和分析结果。
- 查询历史某一次发布的完整资源索引。
- 直接读取某一次发布对应的 evidence、summary、action-plan、intelligence 等内容。

Release Portal API 当前只负责读取已有报告文件，不执行任何 Kubernetes、GitOps、镜像构建或回滚动作。

---

## 2. API 列表

### 2.1 健康检查

```text
GET /healthz
GET /readyz
```

### 2.2 发布列表与 latest 索引

```text
GET /api/releases
GET /api/releases/latest
```

说明：

- `/api/releases` 返回按 `releaseId` 聚合后的发布列表。
- `/api/releases/latest` 返回 latest 资源索引，包括 evidence、summary、action-plan、intelligence 等是否存在。

### 2.3 latest 资源内容

```text
GET /api/releases/latest/evidence
GET /api/releases/latest/summary
GET /api/releases/latest/action-plan
GET /api/releases/latest/intelligence
GET /api/releases/latest/approval
GET /api/releases/latest/failure-evidence
GET /api/releases/latest/advice
GET /api/releases/latest/memory
```

说明：

- JSON 资源返回 `application/json`。
- Markdown 资源返回 `text/markdown`。
- 如果对应 latest 文件不存在，返回 404。

### 2.4 历史发布详情

```text
GET /api/releases/{releaseId}
```

示例：

```text
GET /api/releases/20260519-193458
```

返回内容包括：

- `releaseId`
- `summary`
- `resources`
- `resourceCount`
- `safety`

### 2.5 历史发布资源内容

```text
GET /api/releases/{releaseId}/evidence
GET /api/releases/{releaseId}/summary
GET /api/releases/{releaseId}/action-plan
GET /api/releases/{releaseId}/intelligence
GET /api/releases/{releaseId}/failure-evidence
GET /api/releases/{releaseId}/advice
GET /api/releases/{releaseId}/approval
GET /api/releases/{releaseId}/ai-decision
GET /api/releases/{releaseId}/policy-decision
GET /api/releases/{releaseId}/context
```

示例：

```text
GET /api/releases/20260519-193458/action-plan
GET /api/releases/20260519-193458/intelligence
```

如果资源不存在，接口会返回 404，并给出当前 release 可用的 `availableResources`。

---

## 3. 返回字段说明

### 3.1 `/api/releases`

核心字段：

```text
schemaVersion
generatedAt
reportDir
count
items
```

每个 `items[]` 表示一次 evidence-backed 发布。

常见字段：

```text
releaseId
generatedAt
modifiedAt
resourceCount
summary
resources
```

`summary` 会聚合常用发布结论字段：

```text
releaseResult
policyDecision
finalAction
executionMode
requiresHumanApproval
safeToRetry
riskLevel
riskScore
```

`resources` 会列出本次发布关联的资源文件，例如：

```text
releaseEvidence
releaseSummary
actionPlan
releaseIntelligence
failureEvidence
aiAdvice
aiDecision
policyDecision
releaseContext
approvalRecord
```

### 3.2 `/api/releases/{releaseId}`

该接口返回单次发布的完整索引。

核心字段：

```text
schemaVersion
generatedAt
reportDir
release
safety
```

其中 `release.resources` 只包含索引信息，不直接嵌入大体积报告内容。需要读取正文时，应访问：

```text
/api/releases/{releaseId}/{resource}
```

### 3.3 资源内容接口

资源内容接口直接返回原始文件内容。

例如：

```text
/api/releases/{releaseId}/action-plan
```

会返回对应的 `action-plan-*.json` 内容。

响应头会包含：

```text
X-Release-Portal-Release-ID
X-Release-Portal-Resource
X-Release-Portal-File
```

用于确认本次响应来自哪个发布、哪个资源、哪个底层文件。

---

## 4. 安全边界

Release Portal API 是只读接口。

当前安全约束：

```text
readOnly = true
willExecute = false
supportsRollback = false
supportsPromote = false
supportsPatch = false
supportsDelete = false
```

它不会执行以下动作：

```text
不会 rollback
不会 promote
不会 patch Kubernetes 资源
不会 delete Kubernetes 资源
不会修改 GitOps manifest
不会构建镜像
不会 commit 或 push
```

Action Plan 中即使出现候选命令，也保持：

```text
executionMode = dry_run
willExecute = false
```

该 API 的定位是发布证据查询、审计和人工分析入口，而不是自动执行入口。

---

## 5. 验证方式

### 5.1 本地验证

先启动 watcher 本地测试进程，然后执行：

```bash
scripts/validate-release-portal-api.sh http://127.0.0.1:18088
```

验证脚本会检查：

```text
/healthz
/api/releases
/api/releases/latest
/api/releases/{releaseId}
/api/releases/{releaseId}/evidence
/api/releases/{releaseId}/summary
/api/releases/{releaseId}/action-plan
/api/releases/{releaseId}/intelligence
/api/releases/{releaseId}/advice
/api/releases/{releaseId}/context
/api/releases/{releaseId}/not-a-resource
/api/releases/not-exist-release
```

成功时输出：

```text
VALIDATION_RESULT=PASS
```

### 5.2 线上验证

当前阶段如果尚未构建并上线新 watcher 镜像，则线上 Deployment 仍不会暴露这些新接口。

当后续统一构建并上线 watcher v1.21 后，可以通过 port-forward 验证：

```bash
kubectl -n slo-rollout port-forward deployment/release-rollout-watcher 18088:8080
scripts/validate-release-portal-api.sh http://127.0.0.1:18088
```

### 5.3 当前阶段说明

Stage 37 当前只推进源码和文档，暂不构建或上线新的 watcher 镜像。

默认不做：

```text
podman build
podman push
kubectl set image
修改 watcher-deployment.yaml
GitOps 同步
```

等 Stage 37 Evidence API / Evidence Store 完整收口后，再统一决定是否构建 watcher 镜像并做线上验收。

---

## 6. Stage 37 EvidenceStore API 扩展

Stage 37 新增只读 EvidenceStore 查询入口，不替换原有 /api/releases。

新增接口：

- GET /api/evidence-store/releases
- GET /api/evidence-store/releases/{releaseId}
- GET /api/evidence-store/objects/{objectType}/{objectId}?releaseId={releaseId}

返回 schema：

- evidence.store.releaseList/v1alpha1
- evidence.store.release/v1alpha1
- evidence.store.object/v1alpha1

阶段级验收脚本：

- scripts/test-stage37-evidence-store.sh

