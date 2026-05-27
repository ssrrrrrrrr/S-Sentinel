# Runtime Action 合同审计

## 结论

pause、resume、promote、abort、rollback 五类 runtime action 主链路已经基本闭环。

当前阶段不再继续补动作，而是进入统一收口和上线前硬化。

## 当前统一链路

Recommendation
-> Request
-> Preflight
-> ExecutionResult
-> PostActionVerification
-> EvidenceStore / EvidenceRecord / Portal

## 当前已有统一区域

- action
- writeGate
- postActionVerification
- result
- receipt
- guardrails
- evidenceRefs

## 当前主要差异

目前仍然依赖动作专属字段：

- didPause / pauseVerified
- didResume / resumeVerified
- didPromote / promoteVerified
- didAbort / abortVerified
- didRollback / rollbackVerified

这些字段先保留，避免破坏已有 EvidenceStore、Portal 和测试。

## 下一步统一方向

优先新增统一摘要字段，不删除旧字段：

- executionSummary
- gateSummary
- verificationSummary
- riskSummary

## Stage 4 原则

先兼容式新增，再逐步迁移 Portal 和 Evidence 消费逻辑。

目标是从“五条动作分别能跑”，升级为“一套统一、可信、可审计的 runtime action 子系统”。
