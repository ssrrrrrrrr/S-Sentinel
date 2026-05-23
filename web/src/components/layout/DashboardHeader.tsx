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
    <header className="sticky top-0 z-20 border-b border-slate-200 bg-white">
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
          <span className={`inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-semibold ${
            hasError
              ? "border-rose-200 bg-rose-50 text-rose-700"
              : "border-emerald-200 bg-emerald-50 text-emerald-700"
          }`}>
            <span className={`h-1.5 w-1.5 rounded-full ${hasError ? "bg-rose-500" : "bg-emerald-500"}`} />
            {hasError ? "Watcher 异常" : "Watcher 在线"}
          </span>
          <span className="inline-flex items-center gap-1.5 rounded-md border border-slate-200 bg-slate-50 px-2.5 py-1 text-xs font-semibold text-slate-600">
            <LockKeyhole className="h-3.5 w-3.5" />
            {latest?.safety?.readOnly === false ? "非只读模式" : "只读模式"}
          </span>
          <span className="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium text-slate-500">
            <Clock3 className="h-3.5 w-3.5" />
            {formatTime(generatedAt)}刷新
          </span>
        </div>
      </div>
    </header>
  )
}

