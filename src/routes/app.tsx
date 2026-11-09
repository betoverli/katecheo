import { createFileRoute } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { LinkPreview } from "@/components/link-preview";
import { NotifyBell } from "@/components/notify-bell";
import { Picker } from "@/components/picker";
import { VerseSectionTabs } from "@/components/verse-section-tabs";
import { bookById } from "@/lib/bible/books";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/app")({
  component: AppPage,
  head: () =>
    pageHead({
      title: "Katecheo — picker",
      description: "Escolha livro, capítulo e versos e copie o link rico para o seu app de Bíblia.",
      path: "/app",
    }),
});

function AppPage() {
  const locale = useAppStore((s) => s.locale);
  const copyLocale = useAppStore((s) => s.copyLocale);
  const bookId = useAppStore((s) => s.bookId);
  const chapter = useAppStore((s) => s.chapter);
  const listCount = useAppStore((s) => s.list.length);
  const dock = Boolean((bookId && chapter) || listCount);
  const book = bookId ? bookById(bookId) : undefined;

  return (
    <Screen
      className={cn(
        "mx-auto flex min-h-dvh w-full max-w-4xl flex-col gap-6 px-4 pt-0 sm:px-6",
        dock ? "pb-[calc(var(--tab-bar-height)+16rem)]" : "pb-[calc(var(--tab-bar-height)+1rem)]",
      )}
    >
      <AppHeader
        title={book ? book.names[copyLocale] : t(locale, "navBooks")}
        nativeSymbol="bell"
        trailing={<NotifyBell />}
      />
      <VerseSectionTabs />
      <Picker />
      <LinkPreview />
    </Screen>
  );
}
