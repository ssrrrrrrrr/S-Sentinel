import { Panel } from "@/components/common/Panel"
﻿import {
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
      <div className="flex flex-col justify-between gap-4 border-b border-slate-200 pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Portal Workspace
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-[#031a41]">
            选择一个产品工作台查看详情
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            发布总览保持在上方，长内容面板收进工作台，避免所有控制台视图堆在一个超长页面里。
          </p>
        </div>

        <div className="rounded-xl border border-cyan-100 bg-cyan-50 px-4 py-3 text-sm text-cyan-800">
          <p className="text-xs text-cyan-700">Active Workspace</p>
          <p className="mt-1 font-semibold">{activeWorkspace}</p>
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
                  ? "border-[#031a41] bg-[#031a41] text-white shadow-sm"
                  : "border-slate-200 bg-slate-50 text-slate-700 hover:border-cyan-200 hover:bg-cyan-50"
              }`}
            >
              <p className="text-sm font-semibold">{workspace.title}</p>
              <p className={`mt-1 text-xs leading-5 ${active ? "text-cyan-50" : "text-slate-500"}`}>
                {workspace.description}
              </p>
            </button>
          )
        })}
      </div>
    </Panel>
  )
}
