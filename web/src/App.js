import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from "react";
import { Activity, AlertTriangle, Bot, CheckCircle2, Clock3, FileText, GitBranch, LockKeyhole, RefreshCw, ShieldCheck, Sparkles, TerminalSquare, } from "lucide-react";
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
];
const tabs = ["概览", "Evidence", "Action Plan", "Intelligence", "AI Advice", "Context"];
function statusClass(value) {
    if (["PASS", "LOW", "ALLOW", "NOOP", "NOT REQUIRED"].includes(value)) {
        return "border-emerald-200 bg-emerald-50 text-emerald-700";
    }
    if (["FAIL", "HIGH", "BLOCK", "STOP_PROMOTION", "REQUIRED"].includes(value)) {
        return "border-rose-200 bg-rose-50 text-rose-700";
    }
    return "border-amber-200 bg-amber-50 text-amber-700";
}
function approvalText(value) {
    if (value === "NOT REQUIRED")
        return "无需审批";
    if (value === "REQUIRED")
        return "需要审批";
    return value;
}
function riskText(value) {
    if (value === "LOW")
        return "低风险";
    if (value === "MEDIUM")
        return "中风险";
    if (value === "HIGH")
        return "高风险";
    return value;
}
function Badge({ value, label }) {
    return (_jsx("span", { className: `inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold ${statusClass(value)}`, children: label ?? value }));
}
function policyDisplay(value) {
    if (value === "ALLOW_ADVISORY_ONLY")
        return "ADVISORY";
    return value;
}
function actionDisplay(value) {
    if (value === "STOP_PROMOTION")
        return "STOP";
    return value;
}
function MetricCard({ label, value, rawValue, icon: Icon, hint, }) {
    return (_jsxs("article", { className: "group relative overflow-hidden rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60 transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md", children: [_jsx("div", { className: "absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-[#031a41] via-cyan-500 to-sky-300" }), _jsxs("div", { className: "flex items-start justify-between gap-3", children: [_jsx("p", { className: "text-xs font-semibold uppercase tracking-[0.16em] text-slate-500", children: label }), _jsx(Icon, { className: "h-4 w-4 text-cyan-500" })] }), _jsxs("div", { className: "mt-4", children: [_jsx("p", { className: "break-words text-[clamp(1.35rem,2vw,1.75rem)] font-bold tracking-tight text-[#031a41]", children: value }), rawValue ? (_jsx("p", { className: "mt-1 break-all font-mono text-[11px] text-slate-400", children: rawValue })) : null, _jsx("p", { className: "mt-1 text-xs text-slate-600", children: hint })] })] }));
}
function App() {
    const [selectedId, setSelectedId] = useState(releases[0].id);
    const [activeTab, setActiveTab] = useState("Action Plan");
    const selected = releases.find((release) => release.id === selectedId) ?? releases[0];
    return (_jsxs("main", { className: "min-h-screen text-slate-900", children: [_jsx("header", { className: "sticky top-0 z-20 border-b border-slate-200/80 bg-white/90 backdrop-blur-xl", children: _jsxs("div", { className: "mx-auto flex h-16 max-w-[1440px] items-center justify-between px-6", children: [_jsxs("div", { className: "flex items-center gap-4", children: [_jsx("img", { src: "/brand/s-sentinel-logo.svg", alt: "S Sentinel logo", className: "h-11 w-11 object-contain" }), _jsx("div", { className: "flex items-center leading-tight", children: _jsx("h1", { className: "text-xl font-bold tracking-tight text-[#031a41]", children: "S Sentinel" }) })] }), _jsxs("div", { className: "hidden items-center gap-2 md:flex", children: [_jsxs("span", { className: "inline-flex items-center gap-1.5 rounded-md border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700", children: [_jsx("span", { className: "h-1.5 w-1.5 rounded-full bg-emerald-500" }), "Watcher \u5728\u7EBF"] }), _jsxs("span", { className: "inline-flex items-center gap-1.5 rounded-md border border-slate-200 bg-slate-50 px-2.5 py-1 text-xs font-semibold text-slate-600", children: [_jsx(LockKeyhole, { className: "h-3.5 w-3.5" }), "\u53EA\u8BFB\u6A21\u5F0F"] }), _jsxs("span", { className: "inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium text-slate-500", children: [_jsx(Clock3, { className: "h-3.5 w-3.5" }), "2 \u5206\u949F\u524D\u5237\u65B0"] })] })] }) }), _jsxs("section", { className: "mx-auto flex max-w-[1440px] flex-col gap-6 px-6 py-6", children: [_jsx("section", { className: "rounded-2xl border border-slate-200 bg-white/95 p-4 shadow-sm shadow-slate-200/60", children: _jsxs("div", { className: "flex flex-col justify-between gap-6 lg:flex-row lg:items-end", children: [_jsxs("div", { children: [_jsx("p", { className: "text-xs font-semibold uppercase tracking-[0.22em] text-cyan-600", children: "\u9636\u6BB5 22 \u00B7 \u4EA7\u54C1\u7EA7 Dashboard \u9AA8\u67B6" }), _jsx("h2", { className: "mt-2 max-w-3xl text-[1.35rem] font-semibold leading-snug tracking-tight text-[#031a41]", children: "\u5C06\u53D1\u5E03\u8BC1\u636E\u3001SLO \u51B3\u7B56\u548C Action Plan \u6C47\u805A\u5230\u4E00\u4E2A\u5B89\u5168\u7684\u53EA\u8BFB\u63A7\u5236\u53F0\u3002" }), _jsx("p", { className: "mt-2 max-w-3xl text-sm leading-6 text-slate-600", children: "S Sentinel \u5C06 Watcher \u751F\u6210\u7684\u53D1\u5E03\u62A5\u544A\u8F6C\u5316\u4E3A\u53EF\u8BFB\u3001\u53EF\u8FFD\u6EAF\u3001\u53EF\u5BA1\u8BA1\u7684\u4EA7\u54C1\u754C\u9762\uFF0C\u5E2E\u52A9 SRE \u548C DevOps \u56E2\u961F\u5FEB\u901F\u5224\u65AD\u53D1\u5E03\u5065\u5EB7\u72B6\u6001\u3002" })] }), _jsxs("div", { className: "rounded-xl border border-cyan-100 bg-cyan-50 px-4 py-3 text-sm text-cyan-800", children: [_jsxs("div", { className: "flex items-center gap-2 font-semibold", children: [_jsx(ShieldCheck, { className: "h-4 w-4" }), "\u5B89\u5168\u8FB9\u754C\u5DF2\u542F\u7528"] }), _jsx("p", { className: "mt-1 text-xs text-cyan-700", children: "\u9875\u9762\u4E0D\u4F1A\u66B4\u9732 Rollback\u3001Promote\u3001Patch \u6216 Delete \u7B49\u9AD8\u98CE\u9669\u64CD\u4F5C\u3002" })] })] }) }), _jsxs("section", { className: "grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4", children: [_jsx(MetricCard, { label: "\u6700\u65B0\u7ED3\u679C", value: selected.result, icon: CheckCircle2, hint: "\u6700\u8FD1\u4E00\u6B21 evidence-backed \u53D1\u5E03" }), _jsx(MetricCard, { label: "\u7B56\u7565\u51B3\u7B56", value: policyDisplay(selected.policy), rawValue: selected.policy, icon: ShieldCheck, hint: "Policy Decision \u7ED3\u679C" }), _jsx(MetricCard, { label: "\u6700\u7EC8\u52A8\u4F5C", value: actionDisplay(selected.action), rawValue: selected.action, icon: TerminalSquare, hint: "\u7CFB\u7EDF\u5EFA\u8BAE\u7684\u6700\u7EC8\u52A8\u4F5C" }), _jsx(MetricCard, { label: "\u98CE\u9669\u7B49\u7EA7", value: riskText(selected.risk), rawValue: selected.risk, icon: AlertTriangle, hint: `Risk Score ${selected.riskScore}/100` }), _jsx(MetricCard, { label: "\u4EBA\u5DE5\u5BA1\u6279", value: approvalText(selected.approval), rawValue: selected.approval, icon: LockKeyhole, hint: "\u4EBA\u5DE5\u95E8\u7981\u72B6\u6001" }), _jsx(MetricCard, { label: "\u8D44\u6E90\u6570\u91CF", value: String(selected.resourceCount), icon: FileText, hint: "\u5173\u8054\u53D1\u5E03\u8BC1\u636E\u8D44\u6E90" })] }), _jsxs("section", { className: "grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]", children: [_jsxs("aside", { className: "rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-200/60", children: [_jsxs("div", { className: "mb-4 flex items-center justify-between", children: [_jsxs("div", { children: [_jsx("h3", { className: "font-semibold text-slate-950", children: "\u6700\u8FD1\u53D1\u5E03" }), _jsx("p", { className: "text-xs text-slate-500", children: "\u57FA\u4E8E\u8BC1\u636E\u94FE\u805A\u5408\u7684\u53D1\u5E03\u5386\u53F2" })] }), _jsx(RefreshCw, { className: "h-4 w-4 text-slate-400" })] }), _jsx("div", { className: "relative space-y-3 before:absolute before:left-3 before:top-2 before:h-[calc(100%-1rem)] before:w-px before:bg-slate-200", children: releases.map((release) => {
                                            const isActive = release.id === selected.id;
                                            return (_jsxs("button", { type: "button", onClick: () => setSelectedId(release.id), className: `relative w-full rounded-xl border py-4 pl-9 pr-4 text-left transition ${isActive
                                                    ? "border-[#031a41] bg-[#031a41] text-white shadow-md"
                                                    : "border-slate-200 bg-white text-slate-900 hover:border-cyan-200 hover:bg-cyan-50/40 hover:shadow-sm"}`, children: [_jsx("span", { className: `absolute left-[7px] top-5 h-3 w-3 rounded-full border-2 ${release.result === "PASS" ? "border-emerald-600 bg-emerald-100" : "border-rose-600 bg-rose-100"}` }), _jsxs("div", { className: "flex items-start justify-between gap-3", children: [_jsxs("div", { children: [_jsx("p", { className: `font-mono text-sm font-semibold ${isActive ? "text-white" : "text-[#031a41]"}`, children: release.name }), _jsx("p", { className: `mt-1 text-xs ${isActive ? "text-slate-300" : "text-slate-500"}`, children: release.id })] }), _jsx("span", { className: `text-xs ${isActive ? "text-cyan-200" : "text-slate-500"}`, children: release.modifiedAt })] }), _jsxs("div", { className: "mt-3 flex flex-wrap gap-2", children: [_jsx(Badge, { value: release.result }), _jsx(Badge, { value: release.risk, label: riskText(release.risk) })] })] }, release.id));
                                        }) })] }), _jsxs("section", { className: "rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-200/60", children: [_jsxs("div", { className: "border-b border-slate-200 p-6", children: [_jsxs("div", { className: "flex flex-col justify-between gap-5 lg:flex-row lg:items-start", children: [_jsxs("div", { children: [_jsxs("div", { className: "flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-cyan-600", children: [_jsx(GitBranch, { className: "h-4 w-4" }), "\u5F53\u524D\u9009\u4E2D\u53D1\u5E03"] }), _jsx("h3", { className: "mt-3 text-2xl font-semibold tracking-tight text-[#031a41]", children: selected.name }), _jsxs("p", { className: "mt-2 text-sm text-slate-500", children: ["Namespace ", selected.namespace, " \u00B7 Rollout ", selected.rollout, " \u00B7 AnalysisRun ", selected.analysisRun] })] }), _jsxs("div", { className: "grid grid-cols-2 gap-3 text-sm", children: [_jsxs("div", { className: "rounded-xl border border-slate-200 bg-slate-50 p-3", children: [_jsx("p", { className: "text-xs text-slate-500", children: "Risk Score" }), _jsxs("p", { className: "mt-1 text-xl font-semibold text-[#031a41]", children: [selected.riskScore, _jsx("span", { className: "text-xs text-slate-400", children: " /100" })] })] }), _jsxs("div", { className: "rounded-xl border border-slate-200 bg-slate-50 p-3", children: [_jsx("p", { className: "text-xs text-slate-500", children: "\u8D44\u6E90\u6570\u91CF" }), _jsx("p", { className: "mt-1 text-xl font-semibold text-[#031a41]", children: selected.resourceCount })] })] })] }), _jsx("div", { className: "mt-6 flex flex-wrap gap-2 rounded-2xl border border-slate-200 bg-slate-50 p-1.5", children: tabs.map((tab) => (_jsx("button", { type: "button", onClick: () => setActiveTab(tab), className: `rounded-full px-4 py-2 text-sm font-semibold transition ${activeTab === tab
                                                        ? "bg-[#031a41] text-white shadow-sm"
                                                        : "text-slate-600 hover:bg-white hover:text-[#031a41] hover:shadow-sm"}`, children: tab }, tab))) })] }), _jsx("div", { className: "p-6", children: activeTab === "Action Plan" ? (_jsxs("div", { className: "space-y-5", children: [_jsxs("div", { className: "rounded-xl border border-cyan-100 bg-cyan-50 p-4", children: [_jsxs("div", { className: "flex items-center gap-2 font-semibold text-cyan-900", children: [_jsx(Sparkles, { className: "h-4 w-4" }), "Action Plan \u5B89\u5168\u5EFA\u8BAE"] }), _jsx("p", { className: "mt-2 text-sm leading-6 text-cyan-800", children: "\u5F53\u524D\u7CFB\u7EDF\u5904\u4E8E\u53EA\u8BFB\u89C2\u5BDF\u6A21\u5F0F\u3002\u751F\u6210\u7684 Action Plan \u4EC5\u7528\u4E8E\u8F85\u52A9\u5224\u65AD\uFF0C\u4E0D\u4F1A\u4FEE\u6539 Kubernetes \u8D44\u6E90\u3002" })] }), _jsx("div", { className: "grid gap-3 md:grid-cols-2", children: [
                                                        ["executionMode", "dry_run"],
                                                        ["willExecute", "false"],
                                                        ["doesNotModifyKubernetes", "true"],
                                                        ["doesNotRollback", "true"],
                                                        ["doesNotPromote", "true"],
                                                        ["doesNotDeleteResources", "true"],
                                                    ].map(([key, value]) => (_jsxs("div", { className: "rounded-xl border border-slate-200 bg-slate-50 p-4", children: [_jsx("p", { className: "font-mono text-xs text-slate-500", children: key }), _jsx("p", { className: "mt-2 font-mono text-sm font-semibold text-[#031a41]", children: value })] }, key))) }), _jsxs("div", { className: "rounded-xl border border-slate-200", children: [_jsx("div", { className: "border-b border-slate-200 bg-slate-50 px-4 py-3", children: _jsx("h4", { className: "text-sm font-semibold text-slate-900", children: "\u6A21\u62DF\u64CD\u4F5C" }) }), _jsx("div", { className: "divide-y divide-slate-200", children: [
                                                                ["deployment/demo-app", "Deployment", "Would Patch"],
                                                                ["service/demo-app", "Service", "No Change"],
                                                            ].map(([resource, kind, action]) => (_jsxs("div", { className: "grid grid-cols-3 gap-4 px-4 py-3 text-sm", children: [_jsx("span", { className: "font-mono text-[#031a41]", children: resource }), _jsx("span", { className: "text-slate-500", children: kind }), _jsx("span", { className: "font-semibold text-amber-600", children: action })] }, resource))) })] })] })) : (_jsxs("div", { className: "rounded-xl border border-slate-200 bg-slate-50 p-5", children: [_jsxs("div", { className: "flex items-center gap-2 font-semibold text-[#031a41]", children: [activeTab === "AI Advice" ? _jsx(Bot, { className: "h-4 w-4" }) : _jsx(Activity, { className: "h-4 w-4" }), activeTab] }), _jsxs("p", { className: "mt-2 max-w-3xl text-sm leading-6 text-slate-600", children: ["\u8FD9\u91CC\u662F ", activeTab, " \u7684 mock \u5185\u5BB9\u5360\u4F4D\u3002\u4E0B\u4E00\u9636\u6BB5\u4F1A\u63A5\u5165 Release Portal API \u7684\u8D44\u6E90\u8BFB\u53D6\u63A5\u53E3\u3002"] }), _jsx("pre", { className: "mt-4 overflow-auto rounded-lg bg-[#031a41] p-4 text-xs leading-6 text-cyan-50", children: `{
  "releaseId": "${selected.id}",
  "resource": "${activeTab}",
  "readOnly": true,
  "willExecute": false
}` })] })) })] })] })] })] }));
}
export default App;
