import { createFileRoute, Link, Navigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { AppHeader } from "@/components/app-header";
import { Screen } from "@/components/screen";
import { SharedCollectionView, UserCollectionDetail } from "@/components/user-collection-detail";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { getGrantedCollection, getMyCollection, getSharedCollection, type UserCollection } from "@/lib/user-collections";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";
import { Button } from "@/components/ui/button";

const shell =
  "mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-6 px-4 pt-0 pb-[calc(var(--tab-bar-height)+1.5rem)] sm:px-6";

export const Route = createFileRoute("/c/$id")({
  component: UserCollectionRoute,
  head: () => {
    const seo = pageHead({
      title: "Katecheo — Coleção",
      description: "Lista de referências bíblicas.",
      path: "/c",
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});

function UserCollectionRoute() {
  const { id } = Route.useParams();
  const locale = useAppStore((s) => s.locale);
  const mineLocal = useAppStore((s) => s.myCollections.find((item) => item.id === id));
  const { user, isPending } = useCurrentUserState();
  const [collection, setCollection] = useState<UserCollection | null | undefined>(undefined);
  const [mine, setMine] = useState(false);

  useEffect(() => {
    if (isPending) return;
    let cancelled = false;
    void (async () => {
      if (user) {
        try {
          const own = await getMyCollection({ data: { id } });
          if (cancelled) return;
          if (own) {
            setCollection(own);
            setMine(true);
            return;
          }
          const granted = await getGrantedCollection({ data: { id } });
          if (cancelled) return;
          if (granted) {
            setCollection(granted);
            setMine(false);
            return;
          }
        } catch {
          if (cancelled) return;
          if (mineLocal) {
            setCollection(mineLocal);
            setMine(true);
            return;
          }
        }
      }
      try {
        const shared = await getSharedCollection({ data: { id } });
        if (cancelled) return;
        if (shared) {
          setCollection(shared);
          setMine(false);
          return;
        }
      } catch {
        /* offline */
      }
      if (cancelled) return;
      if (mineLocal) {
        setCollection(mineLocal);
        setMine(true);
        return;
      }
      setCollection(null);
      setMine(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [id, user, isPending, mineLocal]);

  if (isPending || collection === undefined) {
    return (
      <Screen className={shell}>
        <AppHeader title={t(locale, "myCollections")} backTo="/collections" />
        <div className="h-40 rounded-lg bg-surface" aria-hidden="true" />
      </Screen>
    );
  }

  if (!collection) {
    if (!user) {
      return (
        <Screen className={shell}>
          <AppHeader title={t(locale, "myCollections")} backTo="/collections" />
          <p className="text-sm text-muted">{t(locale, "collectionLogin")}</p>
          <Button asChild>
            <Link to="/login" search={{ create: false, next: `/c/${id}` }}>
              {t(locale, "signIn")}
            </Link>
          </Button>
        </Screen>
      );
    }
    return <Navigate to="/collections" />;
  }

  if (mine) return <UserCollectionDetail collection={collection} />;

  return (
    <Screen className={shell}>
      <AppHeader title={collection.title} backTo="/collections" />
      <SharedCollectionView collection={collection} />
    </Screen>
  );
}
