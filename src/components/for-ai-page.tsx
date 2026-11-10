import { useEffect, useState } from "react";
import { BIBLE_APPS } from "@/lib/bible/apps";
import { t } from "@/lib/i18n";
import { useAppStore } from "@/lib/store";
import { Button } from "@/components/ui/button";

function originOf() {
  if (typeof window === "undefined") return "";
  return window.location.origin;
}

function CopyBlock({ label, value }: { label: string; value: string }) {
  const locale = useAppStore((s) => s.locale);
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
    } catch {
      return;
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs font-medium tracking-wide text-muted uppercase">{label}</p>
        <button
          type="button"
          onClick={() => void copy()}
          className="min-h-11 rounded-md px-3 text-xs text-muted hover:text-fg"
        >
          {copied ? t(locale, "copied") : t(locale, "copy")}
        </button>
      </div>
      <pre className="overflow-x-auto rounded-md bg-surface px-4 py-3 text-xs leading-relaxed break-all whitespace-pre-wrap text-fg shadow-[var(--shadow-border)]">
        {value}
      </pre>
    </div>
  );
}

export function ForAiPage() {
  const locale = useAppStore((s) => s.locale);
  const [origin, setOrigin] = useState("");
  const [sample, setSample] = useState("");

  useEffect(() => {
    const host = originOf();
    setOrigin(host);
    const ref = locale === "en" ? "John 3:16" : locale === "es" ? "Juan 3:16" : "João 3:16";
    void fetch(`/api/link?ref=${encodeURIComponent(ref)}&locale=${locale}`)
      .then((res) => res.json())
      .then((data: { markdown?: string }) => {
        if (data.markdown) setSample(data.markdown);
      })
      .catch(() => undefined);
  }, [locale]);

  const getExample = origin
    ? `GET ${origin}/api/link?ref=${encodeURIComponent(locale === "en" ? "John 3:16" : locale === "es" ? "Juan 3:16" : "João 3:16")}&app=youversion&locale=${locale}`
    : "GET /api/link?ref=John+3:16&app=youversion&locale=en";

  const collectionsExample = origin
    ? `GET ${origin}/api/collections?id=salvation&app=youversion&locale=${locale}`
    : "GET /api/collections?id=salvation&app=youversion&locale=pt";

  const plansExample = origin
    ? `GET ${origin}/api/plans?id=gospels-30&day=1&app=youversion&locale=${locale}`
    : "GET /api/plans?id=gospels-30&day=1&app=youversion&locale=pt";

  const postExample = `{
  "refs": ["John 3:16", "Romans 8:28"],
  "app": "youversion",
  "locale": "en"
}`;

  const mcpExample = `{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "katecheo_link",
    "arguments": { "ref": "John 3:16", "app": "youversion", "locale": "en" }
  }
}`;

  const mcpCollectionExample = `{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "katecheo_collection",
    "arguments": { "id": "salvation", "app": "youversion", "locale": "pt" }
  }
}`;

  return (
    <div className="flex flex-col gap-10">
      <p className="max-w-xl text-pretty text-base leading-relaxed text-muted">{t(locale, "forAiLead")}</p>

      <section className="space-y-4">
        <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "forAiApiTitle")}</h2>
        <p className="max-w-xl text-sm leading-relaxed text-fg">{t(locale, "forAiApiLead")}</p>
        <CopyBlock label="GET" value={getExample} />
        <CopyBlock label="GET /api/collections" value={collectionsExample} />
        <CopyBlock label="GET /api/plans" value={plansExample} />
        <CopyBlock label="POST /api/link" value={postExample} />
        {sample ? <CopyBlock label={t(locale, "forAiExample")} value={sample} /> : null}
      </section>

      <section className="space-y-4">
        <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "forAiSkillTitle")}</h2>
        <p className="max-w-xl text-sm leading-relaxed text-fg">{t(locale, "forAiSkillLead")}</p>
        <Button asChild variant="secondary">
          <a href="/skill.md">{t(locale, "forAiSkillCta")}</a>
        </Button>
      </section>

      <section className="space-y-4">
        <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "forAiMcpTitle")}</h2>
        <p className="max-w-xl text-sm leading-relaxed text-fg">{t(locale, "forAiMcpLead")}</p>
        <CopyBlock label="POST /api/mcp" value={mcpExample} />
        <CopyBlock label="katecheo_collection" value={mcpCollectionExample} />
        <CopyBlock
          label="katecheo_plan"
          value={`{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "katecheo_plan",
    "arguments": { "id": "gospels-30", "day": 1, "app": "youversion", "locale": "pt" }
  }
}`}
        />
      </section>

      <section className="space-y-3">
        <h2 className="text-xs font-medium tracking-wide text-muted uppercase">{t(locale, "forAiAppsTitle")}</h2>
        <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {BIBLE_APPS.map((app) => (
            <li
              key={app.id}
              className="rounded-md bg-surface px-4 py-3 text-sm text-fg shadow-[var(--shadow-border)]"
            >
              <span className="font-medium">{app.names[locale]}</span>
              <span className="mt-0.5 block text-xs text-muted">{app.id}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
