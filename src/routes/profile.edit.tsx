import { createFileRoute } from "@tanstack/react-router";
import { AppHeader } from "@/components/app-header";
import { ProfileScreen } from "@/components/screen";
import { ProfileEdit } from "@/components/profile-page";
import { t } from "@/lib/i18n";
import { pageHead } from "@/lib/seo";
import { useAppStore } from "@/lib/store";

export const Route = createFileRoute("/profile/edit")({
  component: ProfileEditRoute,
  head: () => {
    const seo = pageHead({
      title: "Katecheo — Editar perfil",
      description: "Edite avatar, @, nome e e-mail.",
      path: "/profile/edit",
    });
    return { ...seo, meta: [...seo.meta, { name: "robots", content: "noindex" }] };
  },
});

function ProfileEditRoute() {
  const locale = useAppStore((s) => s.locale);
  return (
    <ProfileScreen>
      <AppHeader title={t(locale, "editProfile")} backTo="/profile" />
      <ProfileEdit />
    </ProfileScreen>
  );
}
