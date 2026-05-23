import type { UseQueryResult } from "@tanstack/react-query"
import {
  Boxes,
  FileJson,
  GitBranch,
  Layers3,
  Server,
  ShieldCheck,
} from "lucide-react"
import type { ReleaseResourceContent } from "@/api/releaseResources"
import { KeyValueRows } from "@/components/common/KeyValueRows"
import type { ReleaseIndexItem } from "@/types/release"
import { parseJsonResource } from "@/components/product-views/shared"

type EnvironmentEvidencePayload = {
  service?: string
  namespace?: string
  env?: string
  environmentConfigRef?: string
  environmentProfile?: string
  clusterName?: string
  environmentClass?: string
  policyProfile?: string
  gitopsOverlayPath?: string
  executionMode?: string
  environment?: {
    env?: string
    profile?: string
    clusterName?: string
    environmentClass?: string
    namespace?: string
    policyProfile?: string
    gitopsOverlayPath?: string
    configRef?: string
    configFound?: boolean
  }
  environmentConfigSnapshot?: {
    apiVersion?: string
    kind?: string
    metadata?: {
      name?: string
      env?: string
    }
    spec?: {
      description?: string
      cluster?: {
        name?: string
        provider?: string
        environmentClass?: string
      }
      kubernetes?: {
        namespace?: string
        context?: string | null
      }
      gitops?: {
        mode?: string
        basePath?: string
        overlayPath?: string
        applicationPath?: string
      }
      release?: {
        profile?: string
        reportDir?: string
        evidenceRetention?: string
      }
      policies?: {
        policyProfile?: string
        approvalRequired?: boolean
        executionMode?: string
      }
      supplyChain?: {
        requireImageDigest?: boolean
        blockMutableTags?: boolean
      }
      safety?: {
        readOnlyDefault?: boolean
        willExecuteDefault?: boolean
        requiresHumanApprovalForExecution?: boolean
      }
    }
  }
}

function valueOrDash(value: unknown) {
  if (value === null || value === undefined || value === "") return "-"
  return String(value)
}

function SignalCard({
  label,
  value,
  hint,
  icon: Icon,
}: {
  label: string
  value: string
  hint: string
  icon: typeof Server
}) {
  return (
    <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
      <div className="flex items-center gap-3">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-[#243044] bg-[#070b12] text-[#5d8fd8]">
          <Icon className="h-4 w-4" />
        </div>
        <div>
          <p className="text-xs text-slate-500">{label}</p>
          <p className="mt-1 font-semibold text-slate-100">{value}</p>
        </div>
      </div>
      <p className="mt-3 text-xs leading-5 text-slate-500">{hint}</p>
    </div>
  )
}

function ActionButton({
  children,
  onClick,
}: {
  children: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-xl border border-[#243044] bg-[#0b121d] px-4 py-2 text-sm font-semibold text-slate-300 transition hover:border-[#35517a] hover:bg-[#101a29] hover:text-slate-100"
    >
      {children}
    </button>
  )
}

export function EnvironmentAwarePortalPanel({
  selected,
  evidenceQuery,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  evidenceQuery: UseQueryResult<ReleaseResourceContent, Error>
  onTabChange: (tab: string) => void
}) {
  const evidence = evidenceQuery.data
    ? parseJsonResource<EnvironmentEvidencePayload>(evidenceQuery.data.body)
    : null

  const environment = evidence?.environment ?? {}
  const snapshot = evidence?.environmentConfigSnapshot
  const spec = snapshot?.spec
  const cluster = spec?.cluster
  const kubernetes = spec?.kubernetes
  const gitops = spec?.gitops
  const policies = spec?.policies
  const supplyChain = spec?.supplyChain
  const safety = spec?.safety

  const env = evidence?.env ?? environment.env ?? snapshot?.metadata?.env ?? "-"
  const profile = evidence?.environmentProfile ?? environment.profile ?? spec?.release?.profile ?? env
  const clusterName = evidence?.clusterName ?? environment.clusterName ?? cluster?.name ?? "-"
  const namespace = evidence?.namespace ?? environment.namespace ?? kubernetes?.namespace ?? "-"
  const environmentClass = evidence?.environmentClass ?? environment.environmentClass ?? cluster?.environmentClass ?? "-"
  const policyProfile = evidence?.policyProfile ?? environment.policyProfile ?? policies?.policyProfile ?? "-"
  const overlayPath = evidence?.gitopsOverlayPath ?? environment.gitopsOverlayPath ?? gitops?.overlayPath ?? "-"
  const configRef = evidence?.environmentConfigRef ?? environment.configRef ?? "-"
  const configFound = environment.configFound ?? Boolean(snapshot)

  return (
    <section className="rounded-2xl border border-[#1f2b3d] bg-[#0f1724] p-5 shadow-sm shadow-black/20">
      <div className="flex flex-col justify-between gap-4 border-b border-[#1a2535] pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
            Environment-aware Portal View
          </p>
          <h3 className="mt-2 text-lg font-semibold tracking-tight text-slate-100">
            当前发布运行环境与 GitOps Packaging 摘要
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
            从 release evidence 读取 Stage 34 环境字段，展示 env、cluster、namespace、policy profile 和 overlay path。
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          <span className="rounded-full border border-[#35517a] bg-[#101a29] px-3 py-1 font-mono text-xs font-semibold text-sky-200">
            releaseId={selected.releaseId}
          </span>
          <span className={`rounded-full border px-3 py-1 font-mono text-xs font-semibold ${
            configFound
              ? "border-emerald-900/45 bg-emerald-950/25 text-emerald-200"
              : "border-amber-900/45 bg-amber-950/25 text-amber-200"
          }`}>
            configFound={String(configFound)}
          </span>
        </div>
      </div>

      {evidenceQuery.isLoading ? (
        <div className="mt-4 rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4 text-sm text-slate-400">
          正在读取 release evidence 中的环境字段...
        </div>
      ) : evidenceQuery.isError ? (
        <div className="mt-4 rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-200">
          环境字段读取失败：{evidenceQuery.error instanceof Error ? evidenceQuery.error.message : "unknown error"}
        </div>
      ) : !evidence ? (
        <div className="mt-4 rounded-xl border border-amber-900/45 bg-amber-950/20 p-4 text-sm text-amber-200">
          Evidence JSON 暂时无法解析，环境摘要保留为空。
        </div>
      ) : (
        <>
          <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            <SignalCard
              label="Environment"
              value={env}
              hint={`profile=${profile} · class=${environmentClass}`}
              icon={Layers3}
            />
            <SignalCard
              label="Cluster"
              value={clusterName}
              hint={`provider=${valueOrDash(cluster?.provider)} · namespace=${namespace}`}
              icon={Server}
            />
            <SignalCard
              label="GitOps Overlay"
              value={overlayPath}
              hint={`mode=${valueOrDash(gitops?.mode)} · app=${valueOrDash(gitops?.applicationPath)}`}
              icon={GitBranch}
            />
            <SignalCard
              label="Policy Profile"
              value={policyProfile}
              hint={`executionMode=${valueOrDash(policies?.executionMode ?? evidence.executionMode)}`}
              icon={ShieldCheck}
            />
          </div>

          <section className="mt-5 grid gap-4 lg:grid-cols-2">
            <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
              <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
                <FileJson className="h-4 w-4 text-[#5d8fd8]" />
                Environment Config Reference
              </div>
              <KeyValueRows
                rows={[
                  ["environmentConfigRef", configRef],
                  ["snapshotKind", valueOrDash(snapshot?.kind)],
                  ["snapshotApiVersion", valueOrDash(snapshot?.apiVersion)],
                  ["reportDir", valueOrDash(spec?.release?.reportDir)],
                  ["evidenceRetention", valueOrDash(spec?.release?.evidenceRetention)],
                ]}
              />
            </div>

            <div className="rounded-xl border border-[#1f2b3d] bg-[#0b121d] p-4">
              <div className="mb-3 flex items-center gap-2 font-semibold text-slate-100">
                <Boxes className="h-4 w-4 text-[#5d8fd8]" />
                Safety / Supply Chain Defaults
              </div>
              <KeyValueRows
                rows={[
                  ["approvalRequired", String(policies?.approvalRequired ?? "-")],
                  ["readOnlyDefault", String(safety?.readOnlyDefault ?? true)],
                  ["willExecuteDefault", String(safety?.willExecuteDefault ?? false)],
                  ["requireImageDigest", String(supplyChain?.requireImageDigest ?? false)],
                  ["blockMutableTags", String(supplyChain?.blockMutableTags ?? false)],
                ]}
              />
            </div>
          </section>

          <div className="mt-5 flex flex-wrap gap-2">
            <ActionButton onClick={() => onTabChange("Evidence")}>查看 Evidence</ActionButton>
            <ActionButton onClick={() => onTabChange("Context")}>查看 Context</ActionButton>
          </div>
        </>
      )}
    </section>
  )
}
