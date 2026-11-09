import { cn } from "@/lib/utils";

const SIZE = {
  sm: "text-2xl",
  md: "text-3xl sm:text-4xl",
  lg: "text-4xl sm:text-5xl",
} as const;

export function Wordmark({
  className,
  size = "md",
}: {
  className?: string;
  size?: keyof typeof SIZE;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-baseline whitespace-nowrap text-fg",
        SIZE[size],
        className,
      )}
      aria-label="Katecheo"
    >
      <span className="font-display font-medium tracking-tight italic">Kate</span>
      <span className="font-sans font-semibold tracking-tight not-italic">cheo</span>
    </span>
  );
}
