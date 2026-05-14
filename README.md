# SLO Rollout Demo

## 项目简介

本项目是一个基于 Kubernetes、Argo Rollouts、Prometheus 和私有镜像仓库的 SLO 驱动渐进式发布系统。

项目目标是解决 Kubernetes 环境下新版本发布风险控制问题：新版本不会直接全量发布，而是先进行金丝雀灰度发布，并通过 Prometheus 指标判断新版本是否健康。如果新版本 5xx 错误率或 P95 延迟超过阈值，Argo Rollouts 会中止发布，避免异常版本扩大影响范围。

---

## 核心能力

1. 基于 Argo Rollouts 实现金丝雀发布
2. 基于 Prometheus 采集业务指标
3. 使用 AnalysisTemplate 判断发布健康状态
4. 支持 5xx 错误率和 P95 延迟双指标分析
5. 支持 version 级 canary 指标判断，避免稳定版本流量稀释新版本异常
6. 使用私有 Registry 分发镜像，避免手动导入镜像
7. 使用 release.sh 实现脚本化发布流程

---

## 项目架构

```text
开发代码
  ↓
release.sh
  ↓
Go 编译
  ↓
构建镜像
  ↓
推送到私有 Registry
  ↓
Patch Argo Rollout
  ↓
Argo Rollouts 金丝雀发布
  ↓
Prometheus 采集 5xx / P95 指标
  ↓
AnalysisRun 判断新版本是否健康
  ↓
健康：继续放量
异常：中止发布，回到稳定版本


