import { useState } from "react"
import {
  Activity,
  AlertTriangle,
  Bot,
  CheckCircle2,
  Clock3,
  FileText,
  GitBranch,
  LockKeyhole,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  TerminalSquare,
} from "lucide-react"

const releases = [
  {
    id: "20260519-194236",
    name: "rel-v11-actions",
    result: "PASS",
    policy: "ALLOW",
    action: "NOOP",
    risk: "LOW",
    riskScore: 12,
    approval: "NOT REQUIRED",
    resourceCount: 124,
    modifiedAt: "2 分钟前",
    namespace: "slo-rollout",
    rollout: "demo-app",
    analysisRun: "demo-app-86bd977576-64-2",
  },
  {
    id: "20260519-192108",
    name: "rel-multi-slo-failure",
    result: "FAIL",
    policy: "ALLOW_ADVISORY_ONLY",
    action: "STOP_PROMOTION",
    risk: "HIGH",
    riskScore: 91,
    approval: "REQUIRED",
    resourceCount: 9,
    modifiedAt: "27 分钟前",
    namespace: "slo-rollout",
    rollout: "demo-app",
    analysisRun: "demo-app-86bd977576-57-2",
  },
  {
    id: "20260519-193204",
    name: "rel-portal-api-pass",
    result: "PASS",
    policy: "ALLOW",
    action: "NOOP",
    risk: "LOW",
    riskScore: 8,
    approval: "NOT REQUIRED",
    resourceCount: 8,
    modifiedAt: "43 分钟前",
    namespace: "slo-rollout",
    rollout: "demo-app",
    analysisRun: "demo-app-86bd977576-61-2",
  },
]

const tabs = ["概览", "Evidence", "Action Plan", "Intelligence", "AI Advice", "Context"]

function statusClass(value: string) {
  if (["PASS", "LOW", "ALLOW", "NOOP", "NOT REQUIRED"].includes(value)) {
    return "border-emerald-200 bg-emerald-50 text-emerald-700"
  }
  if (["FAIL", "HIGH", "BLOCK", "STOP_PROMOTION", "REQUIRED"].includes(value)) {
    return "border-rose-200 bg-rose-50 text-rose-700"
  }
  return "border-amber-200 bg-amber-50 text-amber-700"
}

function approvalText(value: string) {
  if (value === "NOT REQUIRED") return "无需审批"
  if (value === "REQUIRED") return "需要审批"
  return value
}

function riskText(value: string) {
  if (value === "LOW") return "低风险"
  if (value === "MEDIUM") return "中风险"
  if (value === "HIGH") return "高风险"
  return value
}

function Badge({ value, label }: { value: string; label?: string }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${statusClass(value)}`}>
      {label ?? value}
    </span>
  )
}

function policyDisplay(value: string) {
  if (value === "ALLOW_ADVISORY_ONLY") return "ADVISORY"
  return value
}

function actionDisplay(value: string) {
  if (value === "STOP_PROMOTION") return "STOP"
  return value
}

function MetricCard({
  label,
  value,
  rawValue,
  icon: Icon,
  hint,
}: {
  label: string
  value: string
  rawValue?: string
  icon: typeof Activity
  hint: string
}) {
  return (
    <article className="group relative overflow-hidden rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60 transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md">
      <div className="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-[#031a41] via-cyan-500 to-sky-300" />
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">{label}</p>
        <Icon className="h-4 w-4 text-cyan-500" />
      </div>
      <div className="mt-4">
        <p className="break-words text-[clamp(1.35rem,2vw,1.75rem)] font-bold tracking-tight text-[#031a41]">
          {value}
        </p>
        {rawValue ? (
          <p className="mt-1 break-all font-mono text-[11px] text-slate-400">{rawValue}</p>
        ) : null}
        <p className="mt-1 text-xs text-slate-600">{hint}</p>
      </div>
    </article>
  )
}

function App() {
  const [selectedId, setSelectedId] = useState(releases[0].id)
  const [activeTab, setActiveTab] = useState("Action Plan")
  const selected = releases.find((release) => release.id === selectedId) ?? releases[0]

  return (
    <main className="min-h-screen text-slate-900">
      <header className="sticky top-0 z-20 border-b border-slate-200/80 bg-white/90 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-[1440px] items-center justify-between px-6">
          <div className="flex items-center gap-4">
            <img
              src="/brand/s-sentinel-logo.svg"
              alt="S Sentinel logo"
              className="h-11 w-11 object-contain"
            />
            <div className="flex items-center leading-tight">
              <h1 className="text-xl font-bold tracking-tight text-[#031a41]">S Sentinel</h1>
            </div>
          </div>

          <div className="hidden items-center gap-2 md:flex">
            <span className="inline-flex items-center gap-1.5 rounded-md border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
              Watcher 在线
            </span>
            <span className="inline-flex items-center gap-1.5 rounded-md border border-slate-200 bg-slate-50 px-2.5 py-1 text-xs font-semibold text-slate-600">
              <LockKeyhole className="h-3.5 w-3.5" />
              只读模式
            </span>
            <span className="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium text-slate-500">
              <Clock3 className="h-3.5 w-3.5" />
              2 分钟前刷新
            </span>
          </div>
        </div>
      </header>

      <section className="mx-auto flex max-w-[1440px] flex-col gap-6 px-6 py-6">
        <section className="rounded-2xl border border-slate-200 bg-white/95 p-4 shadow-sm shadow-slate-200/60">
          <div className="flex flex-col justify-between gap-6 lg:flex-row lg:items-end">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-cyan-600">
                阶段 22 · 产品级 Dashboard 骨架
              </p>
              <h2 className="mt-2 max-w-3xl text-[1.35rem] font-semibold leading-snug tracking-tight text-[#031a41]">
                将发布证据、SLO 决策和 Action Plan 汇聚到一个安全的只读控制台。
              </h2>
              <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-600">
                S Sentinel 将 Watcher 生成的发布报告转化为可读、可追溯、可审计的产品界面，帮助 SRE 和 DevOps 团队快速判断发布健康状态。
              </p>
            </div>
            <div className="rounded-xl border border-cyan-100 bg-cyan-50 px-4 py-3 text-sm text-cyan-800">
              <div className="flex items-center gap-2 font-semibold">
                <ShieldCheck className="h-4 w-4" />
                安全边界已启用
              </div>
              <p className="mt-1 text-xs text-cyan-700">
                页面不会暴露 Rollback、Promote、Patch 或 Delete 等高风险操作。
              </p>
            </div>
          </div>
        </section>

        <section className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4">
          <MetricCard label="最新结果" value={selected.result} icon={CheckCircle2} hint="最近一次 evidence-backed 发布" />
          <MetricCard
            label="策略决策"
            value={policyDisplay(selected.policy)}
            rawValue={selected.policy}
            icon={ShieldCheck}
            hint="Policy Decision 结果"
          />
          <MetricCard
            label="最终动作"
            value={actionDisplay(selected.action)}
            rawValue={selected.action}
            icon={TerminalSquare}
            hint="系统建议的最终动作"
          />
          <MetricCard label="风险等级" value={riskText(selected.risk)} rawValue={selected.risk} icon={AlertTriangle} hint={`Risk Score ${selected.riskScore}/100`} />
          <MetricCard label="人工审批" value={approvalText(selected.approval)} rawValue={selected.approval} icon={LockKeyhole} hint="人工门禁状态" />
          <MetricCard label="资源数量" value={String(selected.resourceCount)} icon={FileText} hint="关联发布证据资源" />
        </section>

        <section className="grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
          <aside className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60">
            <div className="mb-4 flex items-center justify-between">
              <div>
                <h3 className="font-semibold text-slate-950">最近发布</h3>
                <p className="text-xs text-slate-500">基于证据链聚合的发布历史</p>
              </div>
              <RefreshCw className="h-4 w-4 text-slate-400" />
            </div>

            <div className="relative space-y-3 before:absolute before:left-3 before:top-2 before:h-[calc(100%-1rem)] before:w-px before:bg-slate-200">
              {releases.map((release) => {
                const isActive = release.id === selected.id
                return (
                  <button
                    key={release.id}
                    type="button"
                    onClick={() => setSelectedId(release.id)}
                    className={`relative w-full rounded-xl border py-4 pl-9 pr-4 text-left transition ${
                      isActive
                        ? "border-[#031a41] bg-[#031a41] text-white shadow-md"
                        : "border-slate-200 bg-white text-slate-900 hover:border-cyan-200 hover:bg-cyan-50/40 hover:shadow-sm"
                    }`}
                  >
                    <span className={`absolute left-[7px] top-5 h-3 w-3 rounded-full border-2 ${release.result === "PASS" ? "border-emerald-600 bg-emerald-100" : "border-rose-600 bg-rose-100"}`} />
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className={`font-mono text-sm font-semibold ${isActive ? "text-white" : "text-[#031a41]"}`}>
                          {release.name}
                        </p>
                        <p className={`mt-1 text-xs ${isActive ? "text-slate-300" : "text-slate-500"}`}>{release.id}</p>
                      </div>
                      <span className={`text-xs ${isActive ? "text-cyan-200" : "text-slate-500"}`}>{release.modifiedAt}</span>
                    </div>
                    <div className="mt-3 flex flex-wrap gap-2">
                      <Badge value={release.result} />
                      <Badge value={release.risk} label={riskText(release.risk)} />
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
                  <h3 className="mt-3 text-2xl font-semibold tracking-tight text-[#031a41]">{selected.name}</h3>
                  <p className="mt-2 text-sm text-slate-500">
                    Namespace {selected.namespace} · Rollout {selected.rollout} · AnalysisRun {selected.analysisRun}
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-3 text-sm">
                  <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                    <p className="text-xs text-slate-500">Risk Score</p>
                    <p className="mt-1 text-xl font-semibold text-[#031a41]">{selected.riskScore}<span className="text-xs text-slate-400"> /100</span></p>
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
              {activeTab === "Action Plan" ? (
                <div className="space-y-5">
                  <div className="rounded-xl border border-cyan-100 bg-cyan-50 p-4">
                    <div className="flex items-center gap-2 font-semibold text-cyan-900">
                      <Sparkles className="h-4 w-4" />
                      Action Plan 安全建议
                    </div>
                    <p className="mt-2 text-sm leading-6 text-cyan-800">
                      当前系统处于只读观察模式。生成的 Action Plan 仅用于辅助判断，不会修改 Kubernetes 资源。
                    </p>
                  </div>

                  <div className="grid gap-3 md:grid-cols-2">
                    {[
                      ["executionMode", "dry_run"],
                      ["willExecute", "false"],
                      ["doesNotModifyKubernetes", "true"],
                      ["doesNotRollback", "true"],
                      ["doesNotPromote", "true"],
                      ["doesNotDeleteResources", "true"],
                    ].map(([key, value]) => (
                      <div key={key} className="rounded-xl border border-slate-200 bg-slate-50 p-4">
                        <p className="font-mono text-xs text-slate-500">{key}</p>
                        <p className="mt-2 font-mono text-sm font-semibold text-[#031a41]">{value}</p>
                      </div>
                    ))}
                  </div>

                  <div className="rounded-xl border border-slate-200">
                    <div className="border-b border-slate-200 bg-slate-50 px-4 py-3">
                      <h4 className="text-sm font-semibold text-slate-900">模拟操作</h4>
                    </div>
                    <div className="divide-y divide-slate-200">
                      {[
                        ["deployment/demo-app", "Deployment", "Would Patch"],
                        ["service/demo-app", "Service", "No Change"],
                      ].map(([resource, kind, action]) => (
                        <div key={resource} className="grid grid-cols-3 gap-4 px-4 py-3 text-sm">
                          <span className="font-mono text-[#031a41]">{resource}</span>
                          <span className="text-slate-500">{kind}</span>
                          <span className="font-semibold text-amber-600">{action}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              ) : (
                <div className="rounded-xl border border-slate-200 bg-slate-50 p-5">
                  <div className="flex items-center gap-2 font-semibold text-[#031a41]">
                    {activeTab === "AI Advice" ? <Bot className="h-4 w-4" /> : <Activity className="h-4 w-4" />}
                    {activeTab}
                  </div>
                  <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-600">
                    这里是 {activeTab} 的 mock 内容占位。下一阶段会接入 Release Portal API 的资源读取接口。
                  </p>
                  <pre className="mt-4 overflow-auto rounded-lg bg-[#031a41] p-4 text-xs leading-6 text-cyan-50">
{`{
  "releaseId": "${selected.id}",
  "resource": "${activeTab}",
  "readOnly": true,
  "willExecute": false
}`}
                  </pre>
                </div>
              )}
            </div>
          </section>
        </section>
      </section>
    </main>
  )
}

export default App





