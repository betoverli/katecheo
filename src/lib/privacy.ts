import type { Locale } from "@/lib/bible/books";

type Copy = {
  title: string;
  updated: string;
  sections: { title: string; body: string }[];
};

const COPY: Record<Locale, Copy> = {
  pt: {
    title: "Privacidade",
    updated: "Atualizado em 24 de outubro de 2026",
    sections: [
      {
        title: "Quem somos",
        body: "Katecheo (katecheo.app; verse2note.com during cutover) é um app web para copiar referências bíblicas com link, caderno de reunião, coleções, planos e grupos. Operado por Beto Verlí. Contato: o repositório github.com/betoverli/verse2note ou a ajuda no app.",
      },
      {
        title: "O que guardamos",
        body: "Sem conta: só o que fica neste aparelho (idioma, app da Bíblia, notas locais). Com conta: e-mail e nome do Google ou do cadastro; handle, nome, foto; preferências; notas e speakers; coleções; planos; grupos e membros; vínculos; inscrição de avisos (endpoint do aparelho); caixa de avisos. Não usamos analytics de terceiros nem anúncios.",
      },
      {
        title: "Para que",
        body: "Para você entrar, sincronizar entre aparelhos, participar de grupos e planos, receber avisos que escolheu, e manter o perfil público (@, nome, foto e selos). Base: execução do serviço que você pediu. Notas de reunião podem incluir convicção religiosa (dado sensível no Brasil). Só processamos isso para o caderno funcionar, e só com a sua conta.",
      },
      {
        title: "Com quem",
        body: "Google, se você entrar por ele. Neon (banco). Serviços de web push (Apple, Google, Mozilla, Microsoft) se ligar avisos neste aparelho. A API pública para IA (/api, MCP) não lê a sua conta, notas ou grupos.",
      },
      {
        title: "O que é público",
        body: "O perfil /u/@seuhandle mostra foto, nome, @ e selos para qualquer pessoa com o link. Notas e grupos privados não entram em busca. Um grupo na busca mostra o nome. Quem tem o link de um grupo pode pedir para entrar.",
      },
      {
        title: "Prazo e exclusão",
        body: "Guardamos enquanto a conta existir. Você pode baixar seus dados e excluir a conta em Perfil. A exclusão apaga notas, grupos em que você era o único membro, coleções, planos pessoais, avisos e a sessão. Grupos com outras pessoas continuam, sem o seu usuário.",
      },
      {
        title: "Seus direitos (LGPD)",
        body: "Acesso, correção (editar perfil), portabilidade (baixar JSON), exclusão da conta, e informação sobre o uso. Para exercer: Perfil, ou o contato acima. Você pode desligar cada tipo de aviso. Este aparelho também guarda uma cópia local; ao sair, notas locais deste login são apagadas neste aparelho.",
      },
    ],
  },
  en: {
    title: "Privacy",
    updated: "Updated 24 October 2026",
    sections: [
      {
        title: "Who we are",
        body: "Katecheo (katecheo.app; verse2note.com during cutover) is a web app for copying Bible references with a link, a meeting notebook, collections, plans, and groups. Operated by Beto Verlí. Contact: github.com/betoverli/verse2note or Help in the app.",
      },
      {
        title: "What we store",
        body: "With no account: only what stays on this device (language, Bible app, local notes). With an account: email and name from Google or sign-up; handle, name, photo; preferences; notes and speakers; collections; plans; groups and members; friend links; push subscription; in-app alerts. No third-party analytics or ads.",
      },
      {
        title: "Why",
        body: "So you can sign in, sync across devices, join groups and plans, receive the alerts you chose, and keep a public profile (@, name, photo, badges). Legal basis: performing the service you asked for. Meeting notes may include religious belief (sensitive data in Brazil). We only process that to run the notebook, and only with your account.",
      },
      {
        title: "Who else",
        body: "Google if you sign in with it. Neon (database). Web-push services (Apple, Google, Mozilla, Microsoft) if you enable alerts on this device. The public AI API (/api, MCP) does not read your account, notes, or groups.",
      },
      {
        title: "What is public",
        body: "Profile /u/@yourhandle shows photo, name, @, and badges to anyone with the link. Private notes and groups are not searchable. A listed group shows its name. Anyone with a group link can ask to join.",
      },
      {
        title: "How long, and deletion",
        body: "We keep data while the account exists. You can download your data and delete the account in Profile. Deletion removes notes, groups where you were the only member, collections, personal plans, alerts, and the session. Groups with other people stay, without your user.",
      },
      {
        title: "Your rights (LGPD)",
        body: "Access, correction (edit profile), portability (JSON download), account deletion, and information about use. Use Profile, or the contact above. You can turn each alert type off. This device also keeps a local copy; on sign-out, notes for this login are cleared here.",
      },
    ],
  },
  es: {
    title: "Privacidad",
    updated: "Actualizado el 24 de octubre de 2026",
    sections: [
      {
        title: "Quiénes somos",
        body: "Katecheo (katecheo.app; verse2note.com during cutover) es una app web para copiar referencias bíblicas con enlace, cuaderno de reunión, colecciones, planes y grupos. Operado por Beto Verlí. Contacto: github.com/betoverli/verse2note o la ayuda en la app.",
      },
      {
        title: "Qué guardamos",
        body: "Sin cuenta: solo lo que queda en este aparato (idioma, app de Biblia, notas locales). Con cuenta: correo y nombre de Google o del registro; handle, nombre, foto; preferencias; notas y speakers; colecciones; planes; grupos y miembros; vínculos; suscripción de avisos; bandeja de avisos. No usamos analítica de terceros ni anuncios.",
      },
      {
        title: "Para qué",
        body: "Para que entres, sincronices entre aparatos, participes en grupos y planes, recibas los avisos que elegiste, y mantengas el perfil público (@, nombre, foto y sellos). Base: prestar el servicio que pediste. Las notas de reunión pueden incluir convicción religiosa (dato sensible en Brasil). Solo las procesamos para que el cuaderno funcione, y solo con tu cuenta.",
      },
      {
        title: "Con quién",
        body: "Google, si entras con él. Neon (base de datos). Servicios de web push (Apple, Google, Mozilla, Microsoft) si activas avisos en este aparato. La API pública para IA (/api, MCP) no lee tu cuenta, notas ni grupos.",
      },
      {
        title: "Qué es público",
        body: "El perfil /u/@tuhandle muestra foto, nombre, @ y sellos a cualquiera con el enlace. Notas y grupos privados no salen en la búsqueda. Un grupo listado muestra el nombre. Quien tiene el enlace de un grupo puede pedir entrar.",
      },
      {
        title: "Plazo y eliminación",
        body: "Guardamos mientras exista la cuenta. Puedes bajar tus datos y borrar la cuenta en Perfil. La eliminación borra notas, grupos en los que eras el único miembro, colecciones, planes personales, avisos y la sesión. Los grupos con otras personas siguen, sin tu usuario.",
      },
      {
        title: "Tus derechos (LGPD)",
        body: "Acceso, corrección (editar perfil), portabilidad (JSON), eliminación de la cuenta, e información sobre el uso. Ejércelos en Perfil o con el contacto de arriba. Puedes apagar cada tipo de aviso. Este aparato también guarda una copia local; al salir, las notas de este inicio se borran aquí.",
      },
    ],
  },
};

export function privacyCopy(locale: Locale) {
  return COPY[locale] ?? COPY.pt;
}
