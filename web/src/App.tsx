import { useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import {
  Activity,
  Bot,
  GitBranch,
  RefreshCw,
  Sparkles,
} from "lucide-react"
import { fetchLatestRelease, fetchReleases } from "@/api/releases"
import {
  fetchReleaseResource,
  getResourceKindByTab,
  isMarkdownContent,
} from "@/api/releaseResources"
import { Badge } from "@/components/common/Badge"

import { RawResourceViewer } from "@/components/common/RawResourceViewer"
import { DashboardHeader } from "@/components/layout/DashboardHeader"
import { StageBanner } from "@/components/layout/StageBanner"
import {
  ActionPlanProductView,
  AIAdviceProductView,
  ContextProductView,
  EvidenceProductView,
  IntelligenceProductView,
  OverviewProductView,
} from "@/components/product-views/ProductViews"

import { ReleaseMetricGrid } from "@/components/release/ReleaseMetricGrid"
import { SafetyPanel } from "@/components/release/SafetyPanel"

import {
  formatTime,
  normalize,
  resultDisplay,
  riskText,
} from "@/utils/format"

const tabs = ["概览", "Evidence", "Action Plan", "Intelligence", "AI Advice", "Context"]

function App() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState("Action Plan")

  const releasesQuery = useQuery({
    queryKey: ["releases"],
    queryFn: fetchReleases,
    refetchInterval: 15000,
  })

  const latestQuery = useQuery({
    queryKey: ["latest-release"],
    queryFn: fetchLatestRelease,
    refetchInterval: 15000,
  })

  const releases = useMemo(() => releasesQuery.data?.items ?? [], [releasesQuery.data?.items])
  const selected = releases.find((release) => release.releaseId === selectedId) ?? releases[0]
  const selectedSummary = selected?.summary
  const resourceKind = getResourceKindByTab(activeTab)

  const resourceQuery = useQuery({
    queryKey: ["release-resource", selected?.releaseId, resourceKind],
    queryFn: () => fetchReleaseResource(selected!.releaseId, resourceKind),
    enabled: Boolean(selected?.releaseId),
    staleTime: 10000,
  })

  const isLoading = releasesQuery.isLoading || latestQuery.isLoading
  const hasError = releasesQuery.isError || latestQuery.isError

  function refreshAll() {
    void releasesQuery.refetch()
    void latestQuery.refetch()
  }

  return (
    <main className="min-h-screen text-slate-900">
      <DashboardHeader
        hasError={hasError}
        latest={latestQuery.data}
        generatedAt={releasesQuery.data?.generatedAt}
      />

      <section className="mx-auto flex max-w-[1440px] flex-col gap-6 px-6 py-6">
        <StageBanner latest={latestQuery.data} />

        {isLoading ? (
          <section className="rounded-2xl border border-slate-200 bg-white p-8 text-sm text-slate-600 shadow-sm">
            正在加载 Release Portal API 数据...
          </section>
        ) : hasError ? (
          <section className="rounded-2xl border border-rose-200 bg-rose-50 p-8 text-sm text-rose-700 shadow-sm">
            Release Portal API 读取失败。请确认虚拟机 port-forward 仍在运行，并且 Vite proxy 指向 http://192.168.30.11:18090。
          </section>
        ) : !selected || !selectedSummary ? (
          <section className="rounded-2xl border border-slate-200 bg-white p-8 text-sm text-slate-600 shadow-sm">
            当前没有可展示的发布记录。
          </section>
        ) : (
          <>
            <ReleaseMetricGrid selected={selected} />

            <section className="grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
              <aside className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60">
                <div className="mb-4 flex items-center justify-between">
                  <div>
                    <h3 className="font-semibold text-slate-950">最近发布</h3>
                    <p className="text-xs text-slate-500">共 {releasesQuery.data?.count ?? releases.length} 条发布记录</p>
                  </div>
                  <button type="button" onClick={refreshAll} title="刷新发布列表">
                    <RefreshCw className="h-4 w-4 text-slate-400 hover:text-cyan-600" />
                  </button>
                </div>

                <div className="relative space-y-3 before:absolute before:left-3 before:top-2 before:h-[calc(100%-1rem)] before:w-px before:bg-slate-200">
                  {releases.map((release) => {
                    const isActive = release.releaseId === selected.releaseId
                    const result = release.summary.releaseResult
                    return (
                      <button
                        key={release.releaseId}
                        type="button"
                        onClick={() => setSelectedId(release.releaseId)}
                        className={`relative w-full rounded-xl border py-4 pl-9 pr-4 text-left transition ${
                          isActive
                            ? "border-[#031a41] bg-[#031a41] text-white shadow-md"
                            : "border-slate-200 bg-white text-slate-900 hover:border-cyan-200 hover:bg-cyan-50/40 hover:shadow-sm"
                        }`}
                      >
                        <span className={`absolute left-[7px] top-5 h-3 w-3 rounded-full border-2 ${normalize(result).startsWith("PASS") ? "border-emerald-600 bg-emerald-100" : "border-rose-600 bg-rose-100"}`} />
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <p className={`font-mono text-sm font-semibold ${isActive ? "text-white" : "text-[#031a41]"}`}>
                              {release.releaseId}
                            </p>
                            <p className={`mt-1 text-xs ${isActive ? "text-slate-300" : "text-slate-500"}`}>{release.generatedAt}</p>
                          </div>
                          <span className={`text-xs ${isActive ? "text-cyan-200" : "text-slate-500"}`}>{formatTime(release.modifiedAt)}</span>
                        </div>
                        <div className="mt-3 flex flex-wrap gap-2">
                          <Badge value={result} label={resultDisplay(result)} />
                          <Badge value={release.summary.riskLevel} label={riskText(release.summary.riskLevel)} />
                        </div>
                      </button>
                    )
                  })}
                </div>
              </aside>

              <section className="rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-200/60">
                <div className="border-b border-slate-200 p-6">
                  <div className="flex flex-col justify-between gap-5 lg:flex-row lg:items-start">
                    <div>
                      <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-cyan-600">
                        <GitBranch className="h-4 w-4" />
                        当前选中发布
                      </div>
                      <h3 className="mt-3 text-2xl font-semibold tracking-tight text-[#031a41]">{selected.releaseId}</h3>
                      <p className="mt-2 text-sm text-slate-500">
                        GeneratedAt {selected.generatedAt} · ModifiedAt {selected.modifiedAt}
                      </p>
                    </div>
                    <div className="grid grid-cols-2 gap-3 text-sm">
                      <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                        <p className="text-xs text-slate-500">Risk Score</p>
                        <p className="mt-1 text-xl font-semibold text-[#031a41]">{selectedSummary.riskScore}<span className="text-xs text-slate-400"> /100</span></p>
                      </div>
                      <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                        <p className="text-xs text-slate-500">资源数量</p>
                        <p className="mt-1 text-xl font-semibold text-[#031a41]">{selected.resourceCount}</p>
                      </div>
                    </div>
                  </div>

                  <div className="mt-6 flex flex-wrap gap-2 rounded-2xl border border-slate-200 bg-slate-50 p-1.5">
                    {tabs.map((tab) => (
                      <button
                        key={tab}
                        type="button"
                        onClick={() => setActiveTab(tab)}
                        className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                          activeTab === tab
                            ? "bg-[#031a41] text-white shadow-sm"
                            : "text-slate-600 hover:bg-white hover:text-[#031a41] hover:shadow-sm"
                        }`}
                      >
                        {tab}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="p-6">
                  <div className="space-y-5">
                    {activeTab === "Action Plan" ? (
                      <div className="rounded-xl border border-cyan-100 bg-cyan-50 p-4">
                        <div className="flex items-center gap-2 font-semibold text-cyan-900">
                          <Sparkles className="h-4 w-4" />
                          Action Plan 安全建议
                        </div>
                        <p className="mt-2 text-sm leading-6 text-cyan-800">
                          当前系统处于只读观察模式。Release Portal 返回的 Action Plan 仅用于辅助判断，不会修改 Kubernetes 资源。
                        </p>
                      </div>
                    ) : null}

                    {activeTab === "Action Plan" ? <SafetyPanel latest={latestQuery.data} /> : null}

                    <div className="rounded-xl border border-slate-200 bg-slate-50 p-5">
                      <div className="flex flex-col gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start md:justify-between">
                        <div>
                          <div className="flex items-center gap-2 font-semibold text-[#031a41]">
                            {activeTab === "AI Advice" ? <Bot className="h-4 w-4" /> : <Activity className="h-4 w-4" />}
                            {activeTab}
                          </div>
                          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-600">
                            正在读取 <span className="font-mono text-[#031a41]">/api/releases/{selected.releaseId}/{resourceKind}</span>
                          </p>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          <span className="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-semibold text-slate-600">
                            {resourceQuery.data?.contentType ?? "loading"}
                          </span>
                          <span className="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-semibold text-slate-600">
                            {resourceKind}
                          </span>
                        </div>
                      </div>

                      {resourceQuery.isLoading ? (
                        <div className="mt-4 rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
                          正在加载资源内容...
                        </div>
                      ) : resourceQuery.isError ? (
                        <div className="mt-4 rounded-lg border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
                          资源读取失败：{resourceQuery.error instanceof Error ? resourceQuery.error.message : "unknown error"}
                        </div>
                      ) : resourceQuery.data ? (
                        <div className="mt-4 space-y-5">
                          {activeTab === "Action Plan" && !isMarkdownContent(resourceQuery.data.contentType) ? (
                            <ActionPlanProductView body={resourceQuery.data.body} />
                          ) : null}

                          {activeTab === "Evidence" && !isMarkdownContent(resourceQuery.data.contentType) ? (
                            <EvidenceProductView body={resourceQuery.data.body} />
                          ) : null}

                          {activeTab === "Intelligence" && !isMarkdownContent(resourceQuery.data.contentType) ? (
                            <IntelligenceProductView body={resourceQuery.data.body} />
                          ) : null}

                          {activeTab === "AI Advice" && isMarkdownContent(resourceQuery.data.contentType) ? (
                            <AIAdviceProductView body={resourceQuery.data.body} />
                          ) : null}

                          {activeTab === "Context" && !isMarkdownContent(resourceQuery.data.contentType) ? (
                            <ContextProductView body={resourceQuery.data.body} />
                          ) : null}

                          {activeTab === "概览" && isMarkdownContent(resourceQuery.data.contentType) ? (
                            <OverviewProductView
                              body={resourceQuery.data.body}
                              selected={selected}
                              latest={latestQuery.data}
                            />
                          ) : null}

                          <div>
                            <div className="mb-2 flex items-center justify-between">
                              <h4 className="text-sm font-semibold text-slate-900">原始资源内容</h4>
                              <span className="rounded-full border border-slate-200 bg-white px-2.5 py-1 text-xs font-semibold text-slate-500">
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
                        <div className="mt-4 rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
                          暂无资源内容。
                        </div>
                      )}
                    </div>

                  </div>
                </div>
              </section>
            </section>
          </>
        )}
      </section>
    </main>
  )
}

export default App


