import { ShieldCheck } from "lucide-react"
import type { LatestReleaseResponse } from "@/types/release"

export function StageBanner({ latest }: { latest?: LatestReleaseResponse }) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white/95 p-4 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-6 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-cyan-600">
            阶段 22.6 · Release Portal API 联调
          </p>
          <h2 className="mt-2 max-w-3xl text-[1.35rem] font-semibold leading-snug tracking-tight text-[#031a41]">
            真实读取发布证据、SLO 决策和 Action Plan，形成安全的只读发布控制台。
          </h2>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-600">
            当前页面数据来自 Release Portal API：/api/releases 与 /api/releases/latest。前端不会暴露 Rollback、Promote、Patch 或 Delete 等高风险操作。
          </p>
        </div>
        <div className="rounded-xl border border-cyan-100 bg-cyan-50 px-4 py-3 text-sm text-cyan-800">
          <div className="flex items-center gap-2 font-semibold">
            <ShieldCheck className="h-4 w-4" />
            安全边界已启用
          </div>
          <p className="mt-1 text-xs text-cyan-700">
            willExecute={String(latest?.safety?.willExecute ?? false)} · readOnly={String(latest?.safety?.readOnly ?? true)}
          </p>
        </div>
      </div>
    </section>
  )
}
