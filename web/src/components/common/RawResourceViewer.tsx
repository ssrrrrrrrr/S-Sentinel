import { formatResourceBody, isMarkdownContent } from "@/api/releaseResources"

export function RawResourceViewer({ contentType, body }: { contentType: string; body: string }) {
  if (isMarkdownContent(contentType)) {
    return (
      <pre className="max-h-[520px] overflow-auto whitespace-pre-wrap rounded-lg border border-slate-200 bg-white p-5 text-sm leading-7 text-slate-700">
        {formatResourceBody(contentType, body)}
      </pre>
    )
  }

  return (
    <pre className="max-h-[520px] overflow-auto rounded-lg bg-[#031a41] p-5 text-xs leading-6 text-cyan-50">
      {formatResourceBody(contentType, body)}
    </pre>
  )
}
