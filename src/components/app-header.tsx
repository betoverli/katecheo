import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { Link } from "@tanstack/react-router";
import { ArrowLeft, ChevronLeft, Search, X } from "lucide-react";
import { t } from "@/lib/i18n";
import { bindHeader, type FabMenuItem } from "@/lib/native/chrome-store";
import { isAppleUa } from "@/lib/platform";
import { useAppStore } from "@/lib/store";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type BackTo = "/" | "/privacy" | "/terms" | "/contact" | "/for-ai" | "/about";

export type HeaderSearch = {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
};

function HeaderTitle({ title }: { title?: string }) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const textRef = useRef<HTMLHeadingElement>(null);
  const [shift, setShift] = useState(0);

  useEffect(() => {
    const wrap = wrapRef.current;
    const text = textRef.current;
    if (!wrap || !text) {
      setShift(0);
      return;
    }
    const measure = () => {
      const width = wrap.clientWidth;
      if (width < 8) {
        setShift(0);
        return;
      }
      const overflow = text.scrollWidth - width;
      setShift(overflow > 8 ? overflow : 0);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(wrap);
    observer.observe(text);
    return () => observer.disconnect();
  }, [title]);

  const duration = Math.max(6, shift / 12);
  const style = (
    shift
      ? ({
          "--title-shift": `-${shift}px`,
          "--title-duration": `${duration}s`,
        } as CSSProperties)
      : undefined
  );

  return (
    <div ref={wrapRef} className="header-title min-w-0 flex-1 overflow-hidden px-1">
      <h1
        ref={textRef}
        key={title}
        className={cn(
          "mx-auto w-max max-w-none text-center text-[17px] leading-snug font-semibold tracking-[-0.02em] whitespace-nowrap text-fg",
          shift && "header-title-marquee",
        )}
        style={style}
      >
        {title}
      </h1>
    </div>
  );
}

export function AppHeader({
  title,
  backTo,
  backParams,
  trailing,
  search,
  titleField,
  extra,
  compact,
  pinned,
  nativeBar = true,
  nativeSymbol,
  trailingMenu,
  onTrailingMenuSelect,
}: {
  title?: string;
  backTo?: BackTo;
  backParams?: { categoryId: string } | { id: string };
  backLabel?: string;
  trailing?: ReactNode;
  search?: HeaderSearch;
  titleField?: ReactNode;
  extra?: ReactNode;
  compact?: boolean;
  pinned?: boolean;
  /** When false, the iOS shell keeps this header in HTML. */
  nativeBar?: boolean;
  /** SF Symbol for the native trailing button. The tap still hits `trailing`. */
  nativeSymbol?: string;
  /**
   * Items for a native UIMenu on the Liquid Glass trailing button
   * (`showsMenuAsPrimaryAction`). Prefer this over round-tripping through
   * NativeMenus + a hidden anchor — the user's own tap presents the menu.
   */
  trailingMenu?: FabMenuItem[];
  onTrailingMenuSelect?: (id: string) => void;
}) {
  const locale = useAppStore((s) => s.locale);
  const [apple, setApple] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const searchRef = useRef(search);
  searchRef.current = search;
  const selectRef = useRef(onTrailingMenuSelect);
  selectRef.current = onTrailingMenuSelect;
  const keepWebHeader = Boolean(titleField) || compact || !nativeBar;
  const menuKey = JSON.stringify(trailingMenu ?? []);
  useEffect(() => setApple(isAppleUa()), []);
  useLayoutEffect(() => {
    if (keepWebHeader) return;
    const current = searchRef.current;
    return bindHeader({
      title: title ?? "",
      back: Boolean(backTo),
      backLabel: t(locale, "back"),
      search: current ? { value: current.value, placeholder: current.placeholder } : null,
      onSearch: (value) => searchRef.current?.onChange(value),
      trailingSymbol: nativeSymbol ?? null,
      trailingMenu,
      onTrailingMenuSelect: (id) => selectRef.current?.(id),
    });
    // menuKey stands in for trailingMenu contents.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [keepWebHeader, title, backTo, nativeSymbol, search?.value, search?.placeholder, locale, menuKey]);
  const BackIcon = apple ? ChevronLeft : ArrowLeft;

  function cancelSearch() {
    search?.onChange("");
    setSearchOpen(false);
    inputRef.current?.blur();
  }

  return (
    <header className={cn("app-header z-20", pinned ? "relative" : "sticky top-0 -mx-4 sm:-mx-6")}>
      <div className={cn("header-row flex min-h-12 items-center gap-1", compact && "hidden")}>
        <div className="window-controls-pad" aria-hidden />
        <div className="native-back-slot flex w-12 shrink-0 items-center justify-start">
          {backTo ? (
            <Button variant="ghost" size="icon" asChild className="relative z-10 size-11 -ml-1.5 text-accent [&_svg]:size-6">
              {backTo.includes("$") && backParams ? (
                <Link to={backTo} params={backParams} aria-label={t(locale, "back")} data-native-back="">
                  <BackIcon />
                </Link>
              ) : (
                <Link to={backTo} aria-label={t(locale, "back")} data-native-back="">
                  <BackIcon />
                </Link>
              )}
            </Button>
          ) : null}
        </div>
        {titleField ? (
          <div className="min-w-0 flex-1">{titleField}</div>
        ) : (
          <HeaderTitle title={title} />
        )}
        <div
          className="header-trailing flex min-w-12 shrink-0 items-center justify-end"
          data-native-trailing=""
          data-native-symbol={nativeSymbol}
        >
          {trailing}
        </div>
      </div>
      {search ? (
        <form
          className="header-search flex items-center gap-2 px-1 pb-1.5"
          onSubmit={(event) => {
            event.preventDefault();
            inputRef.current?.blur();
          }}
        >
          <div className="relative min-w-0 flex-1">
            <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted" />
            <input
              ref={inputRef}
              type="search"
              inputMode="search"
              value={search.value}
              onChange={(event) => search.onChange(event.target.value)}
              onFocus={() => setSearchOpen(true)}
              onBlur={() => {
                if (!search.value) setSearchOpen(false);
              }}
              onKeyDown={(event) => {
                if (event.key === "Escape") {
                  event.preventDefault();
                  cancelSearch();
                }
              }}
              placeholder={search.placeholder}
              aria-label={search.placeholder}
              autoCapitalize="none"
              autoCorrect="off"
              autoComplete="off"
              spellCheck={false}
              enterKeyHint="search"
              className="h-9 w-full rounded-[10px] bg-fill pr-8 pl-8 text-[17px] text-fg placeholder:text-subtle outline-none [&::-webkit-search-cancel-button]:hidden [&::-webkit-search-decoration]:hidden"
            />
            {search.value ? (
              <button
                type="button"
                aria-label={t(locale, "searchClear")}
                className="absolute top-1/2 right-1 grid size-7 -translate-y-1/2 place-items-center"
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => {
                  search.onChange("");
                  inputRef.current?.focus();
                }}
              >
                <span className="grid size-[18px] place-items-center rounded-full bg-[#8e8e93] text-white">
                  <X className="size-3" strokeWidth={3} />
                </span>
              </button>
            ) : null}
          </div>
          {searchOpen || search.value ? (
            <button
              type="button"
              className="shrink-0 px-1 text-[17px] text-accent active:opacity-60"
              onMouseDown={(event) => event.preventDefault()}
              onClick={cancelSearch}
            >
              {t(locale, "linkCancel")}
            </button>
          ) : null}
        </form>
      ) : null}
      {extra}
    </header>
  );
}
