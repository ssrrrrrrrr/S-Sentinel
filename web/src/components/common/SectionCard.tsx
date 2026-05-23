import type { PropsWithChildren, ReactNode } from "react"

export function SectionCard({
  children,
  title,
  description,
  icon,
  action,
  className = "",
  bodyClassName = "",
}: PropsWithChildren<{
  title?: string
  description?: string
  icon?: ReactNode
  action?: ReactNode
  className?: string
  bodyClassName?: string
}>) {
  const hasHeader = title || description || icon || action

  return (
    <section className={`rounded-2xl border border-[#1f2b3d] bg-[#0b121d] shadow-sm shadow-black/20 ${className}`}>
      {hasHeader ? (
        <div className="flex flex-col justify-between gap-4 border-b border-[#1f2b3d] px-5 py-4 lg:flex-row lg:items-start">
          <div className="min-w-0">
            <div className="flex min-w-0 items-center gap-2">
              {icon ? <span className="shrink-0 text-[#5d8fd8]">{icon}</span> : null}
              {title ? (
                <h3 className="truncate text-base font-semibold tracking-tight text-slate-100">
                  {title}
                </h3>
              ) : null}
            </div>
            {description ? (
              <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-400">
                {description}
              </p>
            ) : null}
          </div>

          {action ? <div className="shrink-0">{action}</div> : null}
        </div>
      ) : null}

      <div className={bodyClassName || "p-5"}>
        {children}
      </div>
    </section>
  )
}
