const CACHE = "katecheo-v16";

const PRECACHE = [
  "/",
  "/app",
  "/collections",
  "/reading",
  "/profile",
  "/notebook",
  "/notebook/import",
  "/groups",
  "/inbox",
  "/about",
  "/for-ai",
  "/login",
  "/llms.txt",
  "/skill.md",
  "/robots.txt",
  "/favicon.svg",
  "/icon-180.png",
  "/icon-192.png",
  "/icon-512.png",
  "/manifest.webmanifest",
  "/fonts/cormorant-italic-500-latin.woff2",
  "/fonts/cormorant-italic-500-latin-ext.woff2",
  "/fonts/cormorant-normal-500-latin.woff2",
  "/fonts/cormorant-normal-500-latin-ext.woff2",
  "/fonts/outfit-normal-400-latin.woff2",
  "/fonts/outfit-normal-400-latin-ext.woff2",
  "/apps/youversion.png",
  "/apps/tecarta.png",
  "/apps/logos.png",
  "/apps/olive-tree.png",
  "/apps/bible-gateway.png",
  "/apps/blue-letter.png",
  "/apps/esv.png",
  "/apps/biblia-online.svg",
  "/apps/bible-hub.png",
  "/apps/accordance.png",
  "/apps/e-sword.png",
  "/apps/mysword.png",
  "/apps/jw-library.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

function putCache(request, response) {
  const cacheControl = response.headers.get("cache-control") ?? "";
  if (!response.ok || cacheControl.includes("no-store") || cacheControl.includes("private")) return;
  const copy = response.clone();
  void caches.open(CACHE).then((cache) => cache.put(request, copy));
}

async function networkFirst(request, { timeoutMs = 2500 } = {}) {
  const cached = await caches.match(request);
  const ctrl = typeof AbortController !== "undefined" ? new AbortController() : null;
  const timer = ctrl ? setTimeout(() => ctrl.abort(), timeoutMs) : 0;
  try {
    const response = await fetch(request, ctrl ? { signal: ctrl.signal } : undefined);
    clearTimeout(timer);
    putCache(request, response);
    return response;
  } catch {
    clearTimeout(timer);
    if (cached) return cached;
    if (request.mode === "navigate") {
      return (
        (await caches.match("/notebook")) ||
        (await caches.match("/app")) ||
        (await caches.match("/")) ||
        Response.error()
      );
    }
    return Response.error();
  }
}

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) {
    // Refresh in the background when online.
    void fetch(request)
      .then((response) => putCache(request, response))
      .catch(() => {});
    return cached;
  }
  try {
    const response = await fetch(request);
    putCache(request, response);
    return response;
  } catch {
    return Response.error();
  }
}

self.addEventListener("message", (event) => {
  const data = event.data;
  if (!data || data.type !== "PRECACHE_URLS" || !Array.isArray(data.urls)) return;
  event.waitUntil(
    caches.open(CACHE).then(async (cache) => {
      for (const url of data.urls) {
        try {
          await cache.add(url);
        } catch {
          /* ignore individual failures */
        }
      }
    }),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method === "POST" && url.origin === self.location.origin && url.pathname === "/notebook/import") {
    event.respondWith(
      (async () => {
        const form = await request.formData();
        const title = String(form.get("title") || "");
        const text = String(form.get("text") || form.get("url") || "");
        const file = form.get("file");
        const cache = await caches.open("katecheo-share");
        const fileName = file instanceof File ? file.name : "";
        await cache.put(
          "/__import_share",
          new Response(JSON.stringify({ title, text, fileName }), { headers: { "content-type": "application/json" } }),
        );
        if (file instanceof File && file.size) {
          await cache.put("/__import_file", new Response(file));
        } else {
          await cache.delete("/__import_file");
        }
        return Response.redirect("/notebook/import?shared=1", 303);
      })(),
    );
    return;
  }
  if (request.method !== "GET") return;
  if (url.origin !== self.location.origin) return;
  // Auth, server functions, and APIs must hit the network — never the cache.
  if (url.pathname.startsWith("/api/")) return;

  const dest = request.destination;
  const accept = request.headers.get("accept") ?? "";
  const isAsset =
    dest === "script" ||
    dest === "style" ||
    dest === "worker" ||
    dest === "font" ||
    dest === "image" ||
    url.pathname.startsWith("/assets/") ||
    url.pathname.startsWith("/fonts/") ||
    url.pathname.startsWith("/apps/");

  if (isAsset) {
    event.respondWith(cacheFirst(request));
    return;
  }

  if (accept.includes("application/json")) return;

  // Navigations / documents: short network budget, then shell cache so
  // client-side route changes and cold reopen do not black-screen offline.
  event.respondWith(networkFirst(request));
});

self.addEventListener("push", (event) => {
  let payload = { title: "Katecheo", body: "", href: "/app" };
  try {
    const data = event.data ? event.data.json() : {};
    payload = { ...payload, ...data };
  } catch {
    if (event.data) payload.body = event.data.text();
  }
  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      data: { href: payload.href || "/app" },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const raw = event.notification.data?.href;
  const href = typeof raw === "string" && raw.startsWith("/") && !raw.startsWith("//") ? raw : "/app";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => {
      const existing = windows[0];
      if (existing) {
        if ("navigate" in existing) void existing.navigate(href);
        return existing.focus();
      }
      return self.clients.openWindow(href);
    }),
  );
});
