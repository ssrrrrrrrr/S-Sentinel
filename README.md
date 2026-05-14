# SLO Rollout Demo

## 1. 项目简介

本项目是一个基于 Kubernetes、Argo CD、Argo Rollouts、Prometheus 和私有镜像仓库的 **SLO 驱动渐进式发布系统**。

项目目标是解决 Kubernetes 环境中新版本发布风险控制问题：新版本不会直接全量上线，而是先通过 Argo Rollouts 做金丝雀发布，再由 Prometheus 提供 5xx 错误率和 P95 延迟等指标，最后由 AnalysisRun 判断新版本是否健康。

如果新版本错误率或延迟超过阈值，Argo Rollouts 会自动中止发布，避免异常版本继续放量。

---

## 2. 当前实现能力

当前项目已经实现：

1. 基于 Argo Rollouts 的金丝雀发布
2. 基于 Prometheus 的业务指标采集
3. 基于 AnalysisTemplate 的发布健康判断
4. 5xx 错误率和 P95 延迟双指标分析
5. version 级 canary 指标判断，避免稳定版本流量稀释新版本异常
6. 私有 Registry 镜像分发，避免手动导入镜像到各节点
7. release-gitops.sh 脚本化构建、推镜像、更新 GitOps 配置
8. Argo CD 监听 GitHub 仓库并自动同步 deploy 目录
9. 异常版本自动拦截，服务保持稳定版本

---

## 3. 项目架构

```text
开发代码
  ↓
release-gitops.sh
  ↓
Go 编译
  ↓
构建镜像
  ↓
推送到私有 Registry
  ↓
更新 deploy/ 下的 Kubernetes YAML
  ↓
git commit / git push
  ↓
Argo CD 监听 GitHub 仓库变化
  ↓
自动同步 deploy/ 到 Kubernetes
  ↓
Argo Rollouts 执行金丝雀发布
  ↓
Prometheus 采集新版本业务指标
  ↓
AnalysisRun 判断 5xx 错误率和 P95 延迟
  ↓
健康：继续放量
异常：中止发布，保持稳定版本
