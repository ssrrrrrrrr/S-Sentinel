import { Activity, LockKeyhole, ShieldCheck } from "lucide-react"
import { Panel } from "@/components/common/Panel"
import type { LatestReleaseResponse } from "@/types/release"

export function StageBanner({ latest }: { latest?: LatestReleaseResponse }) {
  const readOnly = latest?.safety?.readOnly !== false
  const willExecute = latest?.safety?.willExecute === true

  return (
    <Panel padding="md" className="border-[#243044] bg-[#0f1724]">
      <div className="flex flex-col justify-between gap-5 xl:flex-row xl:items-center">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">
            Release Control Room
          </p>
          <h2 className="mt-2 max-w-3xl text-[1.25rem] font-semibold leading-snug tracking-tight text-slate-100">
            当前发布由 SLO、Evidence、Policy、Supply Chain 和 Approval Boundary 共同约束。
          </h2>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            S Sentinel 将发布结果、证据记录、策略裁决和只读 Advisor Trace 聚合到统一控制台，用于解释一次发布为什么通过、失败、阻断或需要审批。
          </p>
        </div>

        <div className="grid min-w-full gap-3 sm:grid-cols-3 xl:min-w-[480px]">
          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
            <div className="flex items-center gap-2 text-xs font-semibold text-slate-400">
              <Activity className="h-4 w-4 text-[#5d8fd8]" />
              Runtime
            </div>
            <p className="mt-2 text-sm font-semibold text-slate-100">
              Watcher {latest ? "Connected" : "Pending"}
            </p>
          </div>

          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
            <div className="flex items-center gap-2 text-xs font-semibold text-slate-400">
              <ShieldCheck className="h-4 w-4 text-emerald-300" />
              Safety
            </div>
            <p className="mt-2 text-sm font-semibold text-slate-100">
              {readOnly ? "Read-only" : "Writable"}
            </p>
          </div>

          <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-3">
            <div className="flex items-center gap-2 text-xs font-semibold text-slate-400">
              <LockKeyhole className="h-4 w-4 text-amber-300" />
              Execution
            </div>
            <p className="mt-2 text-sm font-semibold text-slate-100">
              {willExecute ? "Action enabled" : "Blocked"}
            </p>
          </div>
        </div>
      </div>
    </Panel>
  )
}

