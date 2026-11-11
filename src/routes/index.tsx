import { createFileRoute } from "@tanstack/react-router";
import { Landing } from "@/components/landing";
import { MARKETING } from "@/lib/marketing-copy";
import { getRequestLocale } from "@/lib/request-locale";
import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/")({
  component: Home,
  loader: async () => {
    try {
      const locale = await getRequestLocale();
      return { locale };
    } catch {
      return { locale: "pt" as const };
    }
  },
  head: ({ loaderData }) => {
    const locale = loaderData?.locale ?? "pt";
    const copy = MARKETING[locale];
    return pageHead({
      title: copy.metaTitle,
      description: copy.metaDescription,
      path: "/",
    });
  },
});

function Home() {
  const { locale } = Route.useLoaderData();
  return <Landing initialLocale={locale} />;
}
