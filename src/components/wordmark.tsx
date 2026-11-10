import { cn } from "@/lib/utils";

const SIZE = {
  sm: "text-2xl",
  md: "text-3xl sm:text-4xl",
  lg: "text-4xl sm:text-5xl",
} as const;

/** Product name as one word — single font/weight/style (no Kate/cheo split). */
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
        "inline-block whitespace-nowrap font-display font-medium tracking-tight text-fg",
        SIZE[size],
        className,
      )}
    >
      Katecheo
    </span>
  );
}
