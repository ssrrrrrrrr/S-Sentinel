import type { UseQueryResult } from "@tanstack/react-query"
import { Activity, LockKeyhole } from "lucide-react"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { isMarkdownContent } from "@/api/releaseResources"
import { RawResourceViewer } from "@/components/common/RawResourceViewer"
import {
  ActionPlanProductView,
  AIAdviceProductView,
  ContextProductView,
  EvidenceProductView,
  IntelligenceProductView,
  OverviewProductView,
  RCAProductView,
  RunbookProductView,
  TimelineProductView,
} from "@/components/product-views/ProductViews"
import type { LatestReleaseResponse, ReleaseIndexItem } from "@/types/release"
import { SafetyPanel } from "./SafetyPanel"

export function ReleaseResourcePanel({
  activeTab,
  selected,
  latest,
  resourceKind,
  resourceQuery,
}: {
  activeTab: string
  selected: ReleaseIndexItem
  latest?: LatestReleaseResponse
  resourceKind: string
  resourceQuery: UseQueryResult<ReleaseResourceContent, Error>
}) {
  return (
    <div className="space-y-5">
      {activeTab === "Action Plan" ? (
        <div className="rounded-xl border border-[#35517a] bg-[#101a29] p-4">
          <div className="flex items-center gap-2 font-semibold text-slate-100">
            <LockKeyhole className="h-4 w-4 text-amber-300" />
            Action Plan 安全边界
          </div>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            当前系统处于只读观察模式。Release Portal 返回的 Action Plan 仅用于辅助判断，不会修改 Kubernetes 资源。
          </p>
        </div>
      ) : null}

      {activeTab === "Execution" ? (
        <div className="rounded-xl border border-[#35517a] bg-[#101a29] p-4">
          <div className="flex items-center gap-2 font-semibold text-slate-100">
            <LockKeyhole className="h-4 w-4 text-amber-300" />
            Execution Result 边界
          </div>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            当前阶段只生成 Noop Executor 的执行证据，不会修改 Kubernetes、GitOps 或 rollout 状态。
          </p>
        </div>
      ) : null}

      {activeTab === "GitOps Proposal" ? (
        <div className="rounded-xl border border-[#35517a] bg-[#101a29] p-4">
          <div className="flex items-center gap-2 font-semibold text-slate-100">
            <LockKeyhole className="h-4 w-4 text-amber-300" />
            GitOps Proposal 边界
          </div>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            当前阶段只生成 review-only GitOps patch proposal，用来说明后续 PR / patch adapter 应该提交什么，不会修改仓库或创建 PR。
          </p>
        </div>
      ) : null}

      {activeTab === "GitOps Bundle" ? (
        <div className="rounded-xl border border-[#35517a] bg-[#101a29] p-4">
          <div className="flex items-center gap-2 font-semibold text-slate-100">
            <LockKeyhole className="h-4 w-4 text-amber-300" />
            GitOps Bundle 边界
          </div>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            当前阶段只整理 branch、commit message 和 PR 文案，不会提交 commit、push 分支或创建 Pull Request。
          </p>
        </div>
      ) : null}

      {activeTab === "GitOps Handoff" ? (
        <div className="rounded-xl border border-[#35517a] bg-[#101a29] p-4">
          <div className="flex items-center gap-2 font-semibold text-slate-100">
            <LockKeyhole className="h-4 w-4 text-amber-300" />
            GitOps Handoff 边界
          </div>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            当前阶段只落地 handoff 文件和审查材料，不会写 Git 仓库、不会 push 分支，也不会调用外部 PR 平台。
          </p>
        </div>
      ) : null}

      {activeTab === "Action Plan" ? <SafetyPanel latest={latest} /> : null}
      {activeTab === "Execution" ? <SafetyPanel latest={latest} /> : null}
      {activeTab === "GitOps Proposal" ? <SafetyPanel latest={latest} /> : null}
      {activeTab === "GitOps Bundle" ? <SafetyPanel latest={latest} /> : null}
      {activeTab === "GitOps Handoff" ? <SafetyPanel latest={latest} /> : null}

      <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-5">
        <div className="flex flex-col gap-3 border-b border-[#1a2535] pb-4 md:flex-row md:items-start md:justify-between">
          <div>
            <div className="flex items-center gap-2 font-semibold text-slate-100">
              <Activity className="h-4 w-4 text-[#5d8fd8]" />
              {activeTab === "Advisor Trace" ? "Advisor Trace" : activeTab}
            </div>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
              正在读取 <span className="font-mono text-slate-200">/api/releases/{selected.releaseId}/{resourceKind}</span>
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <span className="rounded-full border border-[#1f2b3d] bg-[#070b12] px-3 py-1 text-xs font-semibold text-slate-400">
              {resourceQuery.data?.contentType ?? "loading"}
            </span>
            <span className="rounded-full border border-[#1f2b3d] bg-[#070b12] px-3 py-1 text-xs font-semibold text-slate-400">
              {resourceKind}
            </span>
          </div>
        </div>

        {resourceQuery.isLoading ? (
          <div className="mt-4 rounded-lg border border-[#1f2b3d] bg-[#0f1724] p-4 text-sm text-slate-400">
            正在加载资源内容...
          </div>
        ) : resourceQuery.isError && activeTab !== "Timeline" ? (
          <div className="mt-4 rounded-lg border border-rose-900/45 bg-rose-950/20 p-4 text-sm text-rose-200">
            资源读取失败：{resourceQuery.error instanceof Error ? resourceQuery.error.message : "unknown error"}
          </div>
        ) : resourceQuery.isError && activeTab === "Timeline" ? (
          <div className="mt-4 space-y-5">
            <div className="rounded-lg border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-200">
              Timeline 资源读取失败，已回退到 Release Portal metadata：
              {resourceQuery.error instanceof Error ? resourceQuery.error.message : "unknown error"}
            </div>
            <TimelineProductView selected={selected} />
          </div>
        ) : resourceQuery.data ? (
          <div className="mt-4 space-y-5">
            {activeTab === "Timeline" ? (
              <TimelineProductView selected={selected} body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "Action Plan" && !isMarkdownContent(resourceQuery.data.contentType) ? (
              <ActionPlanProductView body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "Evidence" && !isMarkdownContent(resourceQuery.data.contentType) ? (
              <EvidenceProductView body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "Intelligence" && !isMarkdownContent(resourceQuery.data.contentType) ? (
              <IntelligenceProductView body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "Advisor Trace" && isMarkdownContent(resourceQuery.data.contentType) ? (
              <AIAdviceProductView body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "Runbook" && isMarkdownContent(resourceQuery.data.contentType) ? (
              <RunbookProductView body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "RCA" && isMarkdownContent(resourceQuery.data.contentType) ? (
              <RCAProductView body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "Context" && !isMarkdownContent(resourceQuery.data.contentType) ? (
              <ContextProductView body={resourceQuery.data.body} />
            ) : null}

            {activeTab === "概览" && isMarkdownContent(resourceQuery.data.contentType) ? (
              <OverviewProductView
                body={resourceQuery.data.body}
                selected={selected}
                latest={latest}
              />
            ) : null}

            <div>
              <div className="mb-2 flex items-center justify-between">
                <h4 className="text-sm font-semibold text-slate-100">原始资源内容</h4>
                <span className="rounded-full border border-[#1f2b3d] bg-[#070b12] px-2.5 py-1 text-xs font-semibold text-slate-500">
                  Audit View
                </span>
              </div>
              <RawResourceViewer
                contentType={resourceQuery.data.contentType}
                body={resourceQuery.data.body}
              />
            </div>
          </div>
        ) : (
          <div className="mt-4 rounded-lg border border-[#1f2b3d] bg-[#0f1724] p-4 text-sm text-slate-400">
            暂无资源内容。
          </div>
        )}
      </div>
    </div>
  )
}

