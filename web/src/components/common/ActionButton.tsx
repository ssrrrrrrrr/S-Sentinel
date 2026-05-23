import type { ButtonHTMLAttributes, PropsWithChildren } from "react"

export type ActionButtonVariant = "default" | "primary" | "danger"

const variantClass: Record<ActionButtonVariant, string> = {
  default:
    "border-[#243044] bg-[#0b121d] text-slate-300 hover:border-[#35517a] hover:bg-[#101a29] hover:text-slate-100",
  primary:
    "border-[#35517a] bg-[#14233a] text-slate-50 hover:border-[#5d8fd8] hover:bg-[#172b46]",
  danger:
    "border-rose-900/45 bg-rose-950/20 text-rose-200 hover:border-rose-700/60 hover:bg-rose-950/30",
}

export function ActionButton({
  children,
  variant = "default",
  className = "",
  type = "button",
  ...props
}: PropsWithChildren<
  ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: ActionButtonVariant
  }
>) {
  return (
    <button
      type={type}
      className={`inline-flex items-center justify-center rounded-xl border px-4 py-2 text-sm font-semibold transition ${variantClass[variant]} ${className}`}
      {...props}
    >
      {children}
    </button>
  )
}
