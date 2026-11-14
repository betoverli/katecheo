import { Link } from "@tanstack/react-router";
import { MARKETING } from "@/lib/marketing-copy";
import { useAppStore } from "@/lib/store";

/** Short about blurb for App Store / help context; product use is iOS. */
export function AboutPage() {
  const locale = useAppStore((s) => s.locale);
  const copy = MARKETING[locale];

  return (
    <div className="flex flex-col gap-10">
      <section className="space-y-3">
        <h2 className="font-display text-2xl tracking-tight text-fg italic">{copy.tagline}</h2>
        <p className="max-w-xl text-pretty text-base leading-relaxed text-fg">{copy.lead}</p>
        <p className="max-w-xl text-pretty text-sm leading-relaxed text-muted">
          {copy.availableOnAppStore}. {copy.features.notes.body}
        </p>
      </section>

      <nav className="flex flex-col gap-2 text-sm">
        <Link to="/privacy" className="text-accent underline-offset-2 hover:underline">
          {copy.footerPrivacy}
        </Link>
        <Link to="/terms" className="text-accent underline-offset-2 hover:underline">
          {copy.footerTerms}
        </Link>
        <Link to="/contact" className="text-accent underline-offset-2 hover:underline">
          {copy.footerContact}
        </Link>
        <Link to="/for-ai" className="text-accent underline-offset-2 hover:underline">
          {copy.footerForAi}
        </Link>
      </nav>
    </div>
  );
}
