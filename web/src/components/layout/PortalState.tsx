type PortalStateKind = "loading" | "error" | "empty"

const portalStateCopy: Record<PortalStateKind, { className: string; message: string }> = {
  loading: {
    className: "border-slate-200 bg-white text-slate-600",
    message: "正在加载 Release Portal API 数据...",
  },
  error: {
    className: "border-rose-200 bg-rose-50 text-rose-700",
    message: "Release Portal API 读取失败。请确认虚拟机 port-forward 仍在运行，并且 Vite proxy 指向 http://192.168.30.11:18090。",
  },
  empty: {
    className: "border-slate-200 bg-white text-slate-600",
    message: "当前没有可展示的发布记录。",
  },
}

export function PortalState({ kind }: { kind: PortalStateKind }) {
  const state = portalStateCopy[kind]

  return (
    <section className={`rounded-2xl border p-8 text-sm shadow-sm ${state.className}`}>
      {state.message}
    </section>
  )
}
