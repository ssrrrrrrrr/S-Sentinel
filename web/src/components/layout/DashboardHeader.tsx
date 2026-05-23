import { Clock3, LockKeyhole } from "lucide-react"
import type { LatestReleaseResponse } from "@/types/release"
import { formatTime } from "@/utils/format"

export function DashboardHeader({
  hasError,
  latest,
  generatedAt,
}: {
  hasError: boolean
  latest?: LatestReleaseResponse
  generatedAt?: string
}) {
  return (
    <header className="sticky top-0 z-20 border-b border-[#1a2535] bg-[#080d15]">
      <div className="mx-auto flex h-16 max-w-[1440px] items-center justify-between px-6">
        <div className="flex items-center gap-4">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-[#33445d] bg-[#c8d6e8]">
            <img
              src="/brand/s-sentinel-logo.svg"
              alt="S Sentinel logo"
              className="h-8 w-8 object-contain"
            />
          </div>
          <div className="leading-tight">
            <h1 className="text-xl font-bold tracking-tight text-slate-100">
              S Sentinel
            </h1>
            <p className="mt-0.5 text-xs font-medium text-slate-500">
              Release Control Plane
            </p>
          </div>
        </div>

        <div className="hidden items-center gap-2 md:flex">
          <span className={`inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-semibold ${
            hasError
              ? "border-rose-900/45 bg-rose-950/25 text-rose-200"
              : "border-emerald-900/45 bg-emerald-950/25 text-emerald-200"
          }`}>
            <span className={`h-1.5 w-1.5 rounded-full ${hasError ? "bg-rose-400" : "bg-emerald-400"}`} />
            {hasError ? "Watcher 异常" : "Watcher 在线"}
          </span>

          <span className="inline-flex items-center gap-1.5 rounded-md border border-[#243044] bg-[#0b121d] px-2.5 py-1 text-xs font-semibold text-slate-300">
            <LockKeyhole className="h-3.5 w-3.5" />
            {latest?.safety?.readOnly === false ? "非只读模式" : "只读模式"}
          </span>

          <span className="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium text-slate-500">
            <Clock3 className="h-3.5 w-3.5" />
            {formatTime(generatedAt)} 刷新
          </span>
        </div>
      </div>
    </header>
  )
}

