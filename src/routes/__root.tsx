import { createRootRoute, HeadContent, Scripts } from "@tanstack/react-router";
import { AuthProvider } from "@/lib/auth/provider";
import { APP_STORE_ID, APP_STORE_LIVE } from "@/lib/app-store";
import { PreviewHostBridge } from "@/components/preview-host-bridge";
import { ThemeSync } from "@/components/theme-sync";
import { AppShell } from "@/components/app-shell";
import appCss from "../styles.css?url";

const THEME_BOOT = `(function(){try{if(/Verse2NoteIOS/.test(navigator.userAgent||""))document.documentElement.classList.add("native-ios");var p=JSON.parse(localStorage.getItem("cita-settings")||"{}");var s=p.state||{};var t=s.theme||"system";var d=t==="dark"||(t!=="light"&&window.matchMedia("(prefers-color-scheme: dark)").matches);var r=d?"dark":"light";document.documentElement.classList.add(r);document.documentElement.style.colorScheme=r;var m=document.querySelector('meta[name="theme-color"]');if(m)m.setAttribute("content",d?"#000000":"#f2f2f7");var loc=s.locale;if(loc!=="pt"&&loc!=="en"&&loc!=="es"){var c=(document.cookie.match(/(?:^|; )v2n-locale=(pt|en|es)/)||[])[1];if(c)loc=c;else{var lang=(navigator.language||"pt").toLowerCase();loc=lang.indexOf("en")===0?"en":lang.indexOf("es")===0?"es":"pt";}}document.documentElement.lang=loc==="pt"?"pt-BR":loc;document.documentElement.setAttribute("data-locale",loc);}catch(e){document.documentElement.classList.add("dark");document.documentElement.style.colorScheme="dark";document.documentElement.lang="pt-BR";}})();`;

function Recover({ title, action }: { title: string; action: string }) {
  return (
    <div
      style={{
        minHeight: "100dvh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 16,
        background: "#000000",
        color: "#ffffff",
        padding: 24,
        fontFamily: "system-ui, sans-serif",
      }}
    >
      <p style={{ textAlign: "center", fontSize: 15 }}>{title}</p>
      <a
        href="/"
        style={{
          borderRadius: 8,
          background: "#0a84ff",
          color: "#ffffff",
          padding: "10px 16px",
          fontSize: 14,
          fontWeight: 600,
          textDecoration: "none",
        }}
      >
        {action}
      </a>
    </div>
  );
}

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1, viewport-fit=cover" },
      { title: "Katecheo" },
      { name: "theme-color", content: "#000000" },
      { name: "apple-mobile-web-app-title", content: "Katecheo" },
      { name: "application-name", content: "Katecheo" },
      ...(APP_STORE_LIVE ? [{ name: "apple-itunes-app", content: `app-id=${APP_STORE_ID}` }] : []),
    ],
    links: [
      { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" },
      { rel: "icon", type: "image/png", sizes: "192x192", href: "/icon-192.png" },
      { rel: "stylesheet", href: appCss },
      { rel: "apple-touch-icon", sizes: "180x180", href: "/icon-180.png" },
      { rel: "describedby", href: "/llms.txt" },
    ],
  }),
  component: RootDocument,
  errorComponent: () => <Recover title="Algo deu errado." action="Início" />,
  notFoundComponent: () => <Recover title="Página não encontrada." action="Início" />,
});

function RootDocument() {
  return (
    <html lang="pt-BR" suppressHydrationWarning className="antialiased">
      <head>
        <HeadContent />
      </head>
      <body className="bg-bg text-fg">
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT }} />
        <PreviewHostBridge />
        <ThemeSync />
        <AuthProvider>
          <AppShell />
        </AuthProvider>
        <Scripts />
      </body>
    </html>
  );
}
