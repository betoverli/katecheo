import { BRAND_NAME, absoluteUrl, publicBaseUrl } from "@/lib/site";

export const SITE = publicBaseUrl();

export function pageHead({
  title,
  description,
  path = "/",
}: {
  title: string;
  description: string;
  path?: string;
}) {
  const url = absoluteUrl(path);
  const site = publicBaseUrl();
  return {
    meta: [
      { title },
      { name: "description", content: description },
      { property: "og:type", content: "website" },
      { property: "og:site_name", content: BRAND_NAME },
      { property: "og:title", content: title },
      { property: "og:description", content: description },
      { property: "og:url", content: url },
      { property: "og:image", content: `${site}/og.jpg` },
      { property: "og:image:width", content: "1200" },
      { property: "og:image:height", content: "630" },
      { property: "og:locale", content: "pt_BR" },
      { property: "og:locale:alternate", content: "en_US" },
      { property: "og:locale:alternate", content: "es_ES" },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:title", content: title },
      { name: "twitter:description", content: description },
      { name: "twitter:image", content: `${site}/x-banner.jpg` },
    ],
    links: [{ rel: "canonical", href: url }],
  };
}
