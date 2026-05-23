import { Panel } from "@/components/common/Panel"
import {
  portalWorkspaces,
  type PortalWorkspace,
} from "@/components/layout/portalWorkspaceConfig"

export function PortalWorkspaceTabs({
  activeWorkspace,
  onWorkspaceChange,
}: {
  activeWorkspace: PortalWorkspace
  onWorkspaceChange: (workspace: PortalWorkspace) => void
}) {
  return (
    <Panel padding="md">
      <div className="flex flex-col justify-between gap-4 border-b border-[#1a2535] pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Control Plane Workspace
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-slate-100">
            选择一个发布控制台视图
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            发布总览保持在上方，Evidence、Policy、Supply Chain、Trace 与 Approval 作为可审计工作区逐步展开。
          </p>
        </div>

        <div className="rounded-xl border border-[#243044] bg-[#0b121d] px-4 py-3 text-sm text-slate-300">
          <p className="text-xs text-slate-500">Active Workspace</p>
          <p className="mt-1 font-semibold text-slate-100">{activeWorkspace}</p>
        </div>
      </div>

      <div className="mt-4 grid gap-2 md:grid-cols-2 xl:grid-cols-6">
        {portalWorkspaces.map((workspace) => {
          const active = workspace.id === activeWorkspace

          return (
            <button
              key={workspace.id}
              type="button"
              onClick={() => onWorkspaceChange(workspace.id)}
              className={`rounded-xl border p-3 text-left transition ${
                active
                  ? "border-[#35517a] bg-[#14233a] text-slate-50 shadow-sm"
                  : "border-[#1f2b3d] bg-[#0b121d] text-slate-300 hover:border-[#35517a] hover:bg-[#101a29]"
              }`}
            >
              <p className="text-sm font-semibold">{workspace.title}</p>
              <p className={`mt-1 text-xs leading-5 ${active ? "text-slate-300" : "text-slate-500"}`}>
                {workspace.description}
              </p>
            </button>
          )
        })}
      </div>
    </Panel>
  )
}
