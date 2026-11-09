import { createFileRoute } from "@tanstack/react-router";
import { NotebookGroupDetail } from "@/components/notebook-group-detail";
import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/groups/$id")({
  component: GroupDetailRoute,
  head: () =>
    pageHead({
      title: "Katecheo — Grupo",
      description: "Caderno compartilhado de um grupo.",
      path: "/groups",
    }),
});

function GroupDetailRoute() {
  const { id } = Route.useParams();
  return <NotebookGroupDetail id={id} />;
}
