import { Panel, type PanelTone } from "@/components/common/Panel"

type PortalStateKind = "loading" | "error" | "empty"

const portalStateCopy: Record<PortalStateKind, { tone: PanelTone; message: string }> = {
  loading: {
    tone: "muted",
    message: "???? Release Portal API ??...",
  },
  error: {
    tone: "danger",
    message: "Release Portal API ??????????? port-forward ??????? Vite proxy ?? http://192.168.30.11:18090?",
  },
  empty: {
    tone: "muted",
    message: "?????????????",
  },
}

export function PortalState({ kind }: { kind: PortalStateKind }) {
  const state = portalStateCopy[kind]

  return (
    <Panel tone={state.tone} padding="lg" className="text-sm">
      {state.message}
    </Panel>
  )
}
