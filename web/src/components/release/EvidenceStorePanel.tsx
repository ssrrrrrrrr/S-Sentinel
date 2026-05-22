import { useMemo, useState } from "react"
import { useMutation, useQuery } from "@tanstack/react-query"
import {
  Database,
  FileSearch,
  RefreshCw,
  Search,
  ShieldCheck,
} from "lucide-react"
import {
  fetchEvidenceStoreObject,
  fetchEvidenceStoreRefresh,
  fetchEvidenceStoreRelease,
  fetchEvidenceStoreStatus,
  type EvidenceStoreJson,
} from "@/api/evidenceStore"
import { RawResourceViewer } from "@/components/common/RawResourceViewer"
import {
  arrayFromPaths,
  asRecord,
  stringifyValue,
  type JsonRecord,
} from "@/components/product-views/shared"
import type { ReleaseIndexItem } from "@/types/release"

type EvidenceStoreObjectRow = {
  key: string
  objectType: string
  objectId: string
  schemaVersion: string
  releaseId: string
  generatedAt: string
  sourceFile: string
  raw: JsonRecord
}

function field(record: JsonRecord, names: string[], fallback = "-") {
  for (const name of names) {
    const value = record[name]
    if (value !== undefined && value !== null && value !== "") {
      return stringifyValue(value)
    }
  }

  return fallback
}

function shortValue(value: string, max = 44) {
  if (value.length <= max) return value
  return `${value.slice(0, 20)}…${value.slice(-16)}`
}

function collectObjectCandidates(payload: EvidenceStoreJson) {
  return [
    ...arrayFromPaths(payload, [["objects"]]),
    ...arrayFromPaths(payload, [["items"]]),
    ...arrayFromPaths(payload, [["records"]]),
    ...arrayFromPaths(payload, [["evidenceObjects"]]),
    ...arrayFromPaths(payload, [["release", "objects"]]),
    ...arrayFromPaths(payload, [["data", "objects"]]),
  ]
}

function extractObjectRows(payload: EvidenceStoreJson | undefined, fallbackReleaseId: string) {
  if (!payload) return []

  const candidates = collectObjectCandidates(payload)
  const rows: EvidenceStoreObjectRow[] = []
  const seen = new Set<string>()

  for (const candidate of candidates) {
    const record = asRecord(candidate)
    if (!record) continue

    const objectType = field(record, ["objectType", "object_type", "type", "kind"])
    const objectId = field(record, ["objectId", "object_id", "id", "name"])
    const releaseId = field(record, ["releaseId", "release_id"], fallbackReleaseId)

    if (objectType === "-" || objectId === "-") continue

    const key = `${objectType}:${objectId}`
    if (seen.has(key)) continue
    seen.add(key)

    rows.push({
      key,
      objectType,
      objectId,
      releaseId,
      schemaVersion: field(record, ["schemaVersion", "schema_version"]),
      generatedAt: field(record, ["generatedAt", "generated_at", "createdAt", "created_at", "modifiedAt", "modified_at"]),
      sourceFile: field(record, ["sourceFile", "source_file", "file", "filePath", "file_path", "path"]),
      raw: record,
    })
  }

  return rows
}

function typeCounts(rows: EvidenceStoreObjectRow[]) {
  return rows.reduce<Record<string, number>>((acc, row) => {
    acc[row.objectType] = (acc[row.objectType] ?? 0) + 1
    return acc
  }, {})
}

function matchesSearch(row: EvidenceStoreObjectRow, query: string) {
  const normalized = query.trim().toLowerCase()
  if (!normalized) return true

  return [
    row.objectType,
    row.objectId,
    row.schemaVersion,
    row.releaseId,
    row.generatedAt,
    row.sourceFile,
  ].some((value) => value.toLowerCase().includes(normalized))
}

function queryErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : "unknown error"
}

function isNotFoundError(error: unknown) {
  return queryErrorMessage(error).includes("HTTP 404")
}

function isNotReadyError(error: unknown) {
  return queryErrorMessage(error).includes("HTTP 409")
}

export function EvidenceStorePanel({
  selected,
  onTabChange,
}: {
  selected: ReleaseIndexItem
  onTabChange: (tab: string) => void
}) {
  const [searchText, setSearchText] = useState("")
  const [selectedKey, setSelectedKey] = useState<string | null>(null)

  const statusQuery = useQuery({
    queryKey: ["evidence-store-status"],
    queryFn: fetchEvidenceStoreStatus,
    staleTime: 15000,
  })

  const statusData = asRecord(statusQuery.data)
  const evidenceStoreReady = statusData?.ready === true

  const releaseQuery = useQuery({
    queryKey: ["evidence-store-release", selected.releaseId],
    queryFn: () => fetchEvidenceStoreRelease(selected.releaseId, true),
    enabled: Boolean(selected.releaseId) && evidenceStoreReady,
    staleTime: 15000,
  })

  const objectRows = useMemo(
    () => extractObjectRows(releaseQuery.data, selected.releaseId),
    [releaseQuery.data, selected.releaseId],
  )

  const filteredRows = useMemo(
    () => objectRows.filter((row) => matchesSearch(row, searchText)),
    [objectRows, searchText],
  )

  const selectedObject =
    filteredRows.find((row) => row.key === selectedKey) ??
    filteredRows[0] ??
    objectRows[0]

  const detailQuery = useQuery({
    queryKey: [
      "evidence-store-object",
      selectedObject?.objectType,
      selectedObject?.objectId,
      selectedObject?.releaseId,
    ],
    queryFn: () =>
      fetchEvidenceStoreObject({
        objectType: selectedObject!.objectType,
        objectId: selectedObject!.objectId,
        releaseId: selectedObject!.releaseId,
        includeRaw: true,
      }),
    enabled: Boolean(selectedObject),
    staleTime: 15000,
  })

  const refreshMutation = useMutation({
    mutationFn: fetchEvidenceStoreRefresh,
    onSuccess: () => {
      void statusQuery.refetch()
      void releaseQuery.refetch()
      void detailQuery.refetch()
    },
  })

  const refreshData = asRecord(refreshMutation.data)
  const refreshImportResult = asRecord(refreshData?.importResult)
  const statusLastImportResult = asRecord(statusData?.lastImportResult)
  const importResult = refreshImportResult ?? statusLastImportResult
  const statusReleaseList = asRecord(statusData?.releaseList)
  const latestRelease = asRecord(refreshData?.latestRelease) ?? asRecord(statusData?.latestRelease)

  const dbFile = field(statusData ?? {}, ["dbFile", "db_file"])
  const releaseCount = field(importResult ?? statusReleaseList ?? {}, ["releaseCount", "release_count", "count"])
  const importedObjects = field(importResult ?? {}, ["importedObjects", "imported_objects"], "-")
  const skippedObjects = field(importResult ?? {}, ["skippedObjects", "skipped_objects"], "-")
  const latestReleaseId = field(latestRelease ?? {}, ["release_id", "releaseId"])
  const statusErrorMessage = statusQuery.isError ? queryErrorMessage(statusQuery.error) : ""
  const refreshErrorMessage = refreshMutation.isError ? queryErrorMessage(refreshMutation.error) : ""

  const counts = useMemo(() => typeCounts(objectRows), [objectRows])
  const objectTypeCount = Object.keys(counts).length
  const releaseIndexMissing = releaseQuery.isError && isNotFoundError(releaseQuery.error)
  const releaseDBNotReady = releaseQuery.isError && isNotReadyError(releaseQuery.error)
  const releaseQueryErrorMessage = releaseQuery.isError ? queryErrorMessage(releaseQuery.error) : ""

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-200/60">
      <div className="flex flex-col justify-between gap-4 border-b border-slate-200 pb-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-600">
            Evidence Search / Object Detail
          </p>
          <h3 className="mt-2 flex items-center gap-2 text-lg font-semibold tracking-tight text-[#031a41]">
            <Database className="h-5 w-5 text-cyan-700" />
            EvidenceStore 当前发布对象索引
          </h3>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-600">
            通过 EvidenceStore 查询当前 release 关联的对象，按 objectType / objectId / schemaVersion
            建立只读检索入口。点击对象后读取 object detail，用于后续 Agent Trace、Policy Explanation
            和 Supply Chain Gate View。
          </p>
        </div>

        <div className="grid grid-cols-3 gap-2 text-xs lg:min-w-[360px]">
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <p className="text-slate-500">Objects</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">{objectRows.length}</p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <p className="text-slate-500">Types</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">{objectTypeCount}</p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <p className="text-slate-500">Mode</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">Read-only</p>
          </div>
        </div>
      </div>

      <div
        className={`mt-4 rounded-2xl border p-4 ${
          evidenceStoreReady
            ? "border-emerald-200 bg-emerald-50"
            : "border-amber-200 bg-amber-50"
        }`}
      >
        <div className="flex flex-col justify-between gap-3 lg:flex-row lg:items-center">
          <div>
            <p
              className={`text-xs font-semibold uppercase tracking-[0.2em] ${
                evidenceStoreReady ? "text-emerald-700" : "text-amber-700"
              }`}
            >
              EvidenceStore Status
            </p>
            <h4 className="mt-1 text-base font-semibold text-[#031a41]">
              {statusQuery.isLoading
                ? "Checking EvidenceStore..."
                : evidenceStoreReady
                  ? "Ready · SQLite index available"
                  : "Not Ready · refresh required"}
            </h4>
            <p className="mt-1 text-sm leading-6 text-slate-600">
              查询接口现在只读读取 SQLite 索引；需要通过 Refresh 显式导入 release evidence。
            </p>
          </div>

          <button
            type="button"
            onClick={() => refreshMutation.mutate()}
            disabled={refreshMutation.isPending}
            className="inline-flex items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <RefreshCw className={`h-4 w-4 ${refreshMutation.isPending ? "animate-spin" : ""}`} />
            {refreshMutation.isPending ? "Refreshing..." : "Refresh EvidenceStore"}
          </button>
        </div>

        <div className="mt-4 grid gap-2 text-xs md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-xl border border-white/70 bg-white/80 p-3">
            <p className="text-slate-500">DB</p>
            <p className="mt-1 break-all font-mono font-semibold text-[#031a41]">{shortValue(dbFile, 56)}</p>
          </div>
          <div className="rounded-xl border border-white/70 bg-white/80 p-3">
            <p className="text-slate-500">Releases</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">{releaseCount}</p>
          </div>
          <div className="rounded-xl border border-white/70 bg-white/80 p-3">
            <p className="text-slate-500">Imported / Skipped</p>
            <p className="mt-1 text-lg font-semibold text-[#031a41]">
              {importedObjects}/{skippedObjects}
            </p>
          </div>
          <div className="rounded-xl border border-white/70 bg-white/80 p-3">
            <p className="text-slate-500">Latest Release</p>
            <p className="mt-1 break-all font-mono font-semibold text-[#031a41]">
              {shortValue(latestReleaseId)}
            </p>
          </div>
        </div>

        {statusQuery.isError ? (
          <p className="mt-3 rounded-xl border border-amber-200 bg-white/80 p-3 text-sm text-amber-800">
            EvidenceStore status 读取失败：{statusErrorMessage}
          </p>
        ) : null}

        {refreshMutation.isError ? (
          <p className="mt-3 rounded-xl border border-amber-200 bg-white/80 p-3 text-sm text-amber-800">
            EvidenceStore refresh 失败：{refreshErrorMessage}
          </p>
        ) : null}
      </div>

      {statusQuery.isLoading ? (
        <div className="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
          正在检查 EvidenceStore status...
        </div>
      ) : !evidenceStoreReady ? (
        <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          <p className="font-semibold">EvidenceStore DB 尚未准备好</p>
          <p className="mt-2 leading-6">
            当前查询接口不会再隐式导入 evidence。请点击上方 Refresh EvidenceStore，显式刷新 SQLite 索引后再查看对象详情。
          </p>
        </div>
      ) : releaseQuery.isLoading ? (
        <div className="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
          正在查询 EvidenceStore release detail...
        </div>
      ) : releaseQuery.isError ? (
        <div
          className={`mt-4 rounded-xl border p-4 text-sm ${
            releaseIndexMissing
              ? "border-cyan-200 bg-cyan-50 text-cyan-800"
              : "border-amber-200 bg-amber-50 text-amber-800"
          }`}
        >
          <p className="font-semibold">
            {releaseDBNotReady
              ? "EvidenceStore DB 尚未刷新"
              : releaseIndexMissing
                ? "当前 release 尚未进入 EvidenceStore 索引"
                : "EvidenceStore 查询失败"}
          </p>
          <p className="mt-2 leading-6">
            {releaseDBNotReady
              ? "当前 SQLite 索引尚未初始化。请点击上方 Refresh EvidenceStore 后重试。"
              : releaseIndexMissing
                ? `EvidenceStore 没有找到 releaseId=${selected.releaseId}。这通常表示历史 release 尚未导入索引，或当前 EvidenceStore 尚未刷新。`
                : `接口返回错误：${releaseQueryErrorMessage}`}
          </p>
        </div>
      ) : objectRows.length === 0 ? (
        <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          EvidenceStore 已返回数据，但没有解析出对象列表。当前面板保留为只读 Raw View，后续可根据真实 schema 调整解析路径。
        </div>
      ) : (
        <>
          <div className="mt-5 flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div className="flex flex-wrap gap-2">
              {Object.entries(counts).map(([objectType, count]) => (
                <span
                  key={objectType}
                  className="rounded-full border border-cyan-200 bg-cyan-50 px-3 py-1 font-mono text-xs font-semibold text-cyan-800"
                >
                  {objectType}={count}
                </span>
              ))}
            </div>

            <label className="flex min-w-[280px] items-center gap-2 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm">
              <Search className="h-4 w-4 text-slate-400" />
              <input
                value={searchText}
                onChange={(event) => setSearchText(event.target.value)}
                placeholder="Search object type / id / schema"
                className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-slate-400"
              />
            </label>
          </div>

          <section className="mt-5 grid gap-4 xl:grid-cols-[420px_minmax(0,1fr)]">
            <div className="rounded-2xl border border-slate-200 bg-slate-50">
              <div className="flex items-center justify-between border-b border-slate-200 px-4 py-3">
                <div className="flex items-center gap-2 font-semibold text-[#031a41]">
                  <FileSearch className="h-4 w-4 text-cyan-700" />
                  Evidence Objects
                </div>
                <span className="rounded-full border border-slate-200 bg-white px-2.5 py-1 text-xs font-semibold text-slate-500">
                  {filteredRows.length}/{objectRows.length}
                </span>
              </div>

              <div className="max-h-[520px] overflow-auto p-3">
                {filteredRows.map((row) => {
                  const active = selectedObject?.key === row.key

                  return (
                    <button
                      key={row.key}
                      type="button"
                      onClick={() => setSelectedKey(row.key)}
                      className={`mb-2 w-full rounded-xl border p-3 text-left transition ${
                        active
                          ? "border-[#031a41] bg-white shadow-sm"
                          : "border-slate-200 bg-white hover:border-cyan-200"
                      }`}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="font-mono text-xs font-semibold text-cyan-700">
                            {row.objectType}
                          </p>
                          <p className="mt-1 break-all font-mono text-sm font-semibold text-[#031a41]">
                            {shortValue(row.objectId)}
                          </p>
                        </div>
                        <span className="shrink-0 rounded-full border border-slate-200 bg-slate-50 px-2 py-1 text-[11px] font-semibold text-slate-500">
                          detail
                        </span>
                      </div>
                      <div className="mt-3 grid gap-1 text-xs text-slate-500">
                        <p>schema={shortValue(row.schemaVersion)}</p>
                        <p>generatedAt={shortValue(row.generatedAt)}</p>
                        <p>source={shortValue(row.sourceFile)}</p>
                      </div>
                    </button>
                  )
                })}
              </div>
            </div>

            <div className="min-w-0 rounded-2xl border border-slate-200 bg-slate-50 p-4">
              <div className="flex flex-col justify-between gap-3 border-b border-slate-200 pb-4 md:flex-row md:items-start">
                <div>
                  <div className="flex items-center gap-2 font-semibold text-[#031a41]">
                    <ShieldCheck className="h-4 w-4 text-cyan-700" />
                    Object Detail
                  </div>
                  <p className="mt-2 break-all font-mono text-xs text-slate-500">
                    {selectedObject
                      ? `/api/evidence-store/objects/${selectedObject.objectType}/${selectedObject.objectId}`
                      : "no object selected"}
                  </p>
                </div>

                <button
                  type="button"
                  onClick={() => {
                    void statusQuery.refetch()
                    void releaseQuery.refetch()
                    void detailQuery.refetch()
                  }}
                  className="inline-flex items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
                >
                  <RefreshCw className="h-4 w-4" />
                  Refresh
                </button>
              </div>

              <div className="mt-4">
                {detailQuery.isLoading ? (
                  <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
                    正在读取 object detail...
                  </div>
                ) : detailQuery.isError ? (
                  <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
                    Object detail 读取失败：
                    {queryErrorMessage(detailQuery.error)}
                  </div>
                ) : detailQuery.data ? (
                  <RawResourceViewer
                    contentType="application/json; charset=utf-8"
                    body={JSON.stringify(detailQuery.data, null, 2)}
                  />
                ) : releaseQuery.data ? (
                  <RawResourceViewer
                    contentType="application/json; charset=utf-8"
                    body={JSON.stringify(releaseQuery.data, null, 2)}
                  />
                ) : (
                  <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
                    暂无可展示对象。
                  </div>
                )}
              </div>
            </div>
          </section>
        </>
      )}

      <div className="mt-5 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => onTabChange("Evidence")}
          className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
        >
          查看 Release Evidence
        </button>
        <button
          type="button"
          onClick={() => onTabChange("AI Advice")}
          className="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:border-cyan-200 hover:text-cyan-700"
        >
          查看 AI Advice
        </button>
      </div>
    </section>
  )
}
