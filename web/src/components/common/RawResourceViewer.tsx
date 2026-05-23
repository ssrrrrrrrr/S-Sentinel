import { formatResourceBody, isMarkdownContent } from "@/api/releaseResources"

export function RawResourceViewer({ contentType, body }: { contentType: string; body: string }) {
  if (isMarkdownContent(contentType)) {
    return (
      <pre className="max-h-[520px] overflow-auto whitespace-pre-wrap rounded-lg border border-[#1f2b3d] bg-[#070b12] p-5 text-sm leading-7 text-slate-300">
        {formatResourceBody(contentType, body)}
      </pre>
    )
  }

  return (
    <pre className="max-h-[520px] overflow-auto rounded-lg border border-[#1f2b3d] bg-[#070b12] p-5 text-xs leading-6 text-slate-300">
      {formatResourceBody(contentType, body)}
    </pre>
  )
}
