import { Wordmark } from "@/components/wordmark";

export function SplashScreen() {
  return (
    <div
      className="fixed inset-0 z-[100] grid place-items-center bg-bg"
      role="status"
      aria-live="polite"
      aria-label="Katecheo"
    >
      <div className="flex flex-col items-center gap-6">
        <img
          src="/icon-192.png"
          alt=""
          width={96}
          height={96}
          className="size-24 rounded-[1.5rem] object-cover"
        />
        <Wordmark size="md" />
      </div>
    </div>
  );
}
