import type { PropsWithChildren } from "react"
import { Clock3, LockKeyhole, RefreshCw } from "lucide-react"
import type { LatestReleaseResponse } from "@/types/release"
import { formatTime } from "@/utils/format"
import {
  SidebarNavigation,
} from "@/components/layout/SidebarNavigation"
import {
  ReleaseContextBar,
  type ReleaseContext,
} from "@/components/layout/ReleaseContextBar"
import type { PortalWorkspace } from "@/components/layout/portalWorkspaceConfig"

export function LayoutShell({
  children,
  hasError,
  latest,
  generatedAt,
  activeWorkspace,
  onWorkspaceChange,
  releaseContext,
  onRefresh,
}: PropsWithChildren<{
  hasError: boolean
  latest?: LatestReleaseResponse
  generatedAt?: string
  activeWorkspace: PortalWorkspace
  onWorkspaceChange: (workspace: PortalWorkspace) => void
  releaseContext: ReleaseContext
  onRefresh: () => void
}>) {
  return (
    <div className="min-h-screen bg-[#070b12] text-slate-100 lg:grid lg:grid-cols-[248px_minmax(0,1fr)]">
      <SidebarNavigation
        activeWorkspace={activeWorkspace}
        onWorkspaceChange={onWorkspaceChange}
      />

      <main className="min-w-0">
        <header className="sticky top-0 z-20 border-b border-[#1a2535] bg-[#080d15]">
          <div className="flex h-16 items-center justify-between px-5 lg:px-7">
            <div className="flex min-w-0 items-center gap-4">
              <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-[#33445d] bg-[#c8d6e8]">
                <img
                  src="/brand/s-sentinel-logo.svg"
                  alt="S Sentinel logo"
                  className="h-8 w-8 object-contain"
                />
              </div>

              <div className="min-w-0 leading-tight">
                <h1 className="truncate text-base font-bold tracking-tight text-slate-100">
                  S Sentinel
                </h1>
                <p className="mt-0.5 truncate text-xs font-medium text-slate-500">
                  Evidence-first Release Control Plane
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

              <button
                type="button"
                onClick={onRefresh}
                className="inline-flex h-9 items-center gap-2 rounded-lg border border-[#243044] bg-[#0b121d] px-3 text-xs font-semibold text-slate-300 transition hover:border-[#35517a] hover:bg-[#101a29] hover:text-slate-100"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                Refresh
              </button>
            </div>
          </div>
        </header>

        <div className="px-4 py-5 lg:px-7 lg:py-6">
          <ReleaseContextBar context={releaseContext} />

          <section className="mt-6 flex flex-col gap-6">
            {children}
          </section>
        </div>
      </main>
    </div>
  )
}
