import type { ComponentProps } from "react"
import { ReleaseDetailHeader } from "@/components/release/ReleaseDetailHeader"
import { ReleaseList } from "@/components/release/ReleaseList"
import { ReleaseResourcePanel } from "@/components/release/ReleaseResourcePanel"

type ReleaseListProps = ComponentProps<typeof ReleaseList>
type ReleaseDetailHeaderProps = ComponentProps<typeof ReleaseDetailHeader>
type ReleaseResourcePanelProps = ComponentProps<typeof ReleaseResourcePanel>

export function ReleaseDetailWorkspace({
  releases,
  selected,
  totalCount,
  onSelect,
  onRefresh,
  tabs,
  activeTab,
  onTabChange,
  latest,
  resourceKind,
  resourceQuery,
}: {
  releases: ReleaseListProps["releases"]
  selected: ReleaseListProps["selected"]
  totalCount: ReleaseListProps["totalCount"]
  onSelect: ReleaseListProps["onSelect"]
  onRefresh: ReleaseListProps["onRefresh"]
  tabs: ReleaseDetailHeaderProps["tabs"]
  activeTab: ReleaseDetailHeaderProps["activeTab"]
  onTabChange: ReleaseDetailHeaderProps["onTabChange"]
  latest: ReleaseResourcePanelProps["latest"]
  resourceKind: ReleaseResourcePanelProps["resourceKind"]
  resourceQuery: ReleaseResourcePanelProps["resourceQuery"]
}) {
  return (
    <section className="grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
      <ReleaseList
        releases={releases}
        selected={selected}
        totalCount={totalCount}
        onSelect={onSelect}
        onRefresh={onRefresh}
      />

      <section className="rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-200/60">
        <ReleaseDetailHeader
          selected={selected}
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={onTabChange}
        />

        <div className="p-6">
          <ReleaseResourcePanel
            activeTab={activeTab}
            selected={selected}
            latest={latest}
            resourceKind={resourceKind}
            resourceQuery={resourceQuery}
          />
        </div>
      </section>
    </section>
  )
}
