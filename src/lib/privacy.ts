import type { Locale } from "@/lib/bible/books";

type Copy = {
  title: string;
  updated: string;
  sections: { title: string; body: string }[];
};

const COPY: Record<Locale, Copy> = {
  pt: {
    title: "Privacidade",
    updated: "Atualizado em 11 de novembro de 2026",
    sections: [
      {
        title: "Quem somos",
        body: "Katecheo (katecheo.app; verse2note.com redireciona para katecheo.app) é um app nativo para iPhone e um site de marketing com APIs públicas. Ajuda a organizar estudo bíblico: notas com referências que abrem no seu app de Bíblia, temas, planos, grupos e amigos. O Katecheo não exibe o texto bíblico. Operado por Beto Verlí. Contato: katecheo.app/contact ou github.com/betoverli/katecheo.",
      },
      {
        title: "O que guardamos",
        body: "No aparelho (iOS): preferências locais e dados em cache necessários ao app. Com conta: e-mail e nome (Google, Apple ou cadastro); handle, nome, foto; preferências; notas e speakers; coleções; planos; grupos e membros; vínculos; tokens de push (APNs); caixa de avisos. Não usamos analytics de terceiros nem anúncios.",
      },
      {
        title: "Para que",
        body: "Para você entrar, sincronizar entre aparelhos, participar de grupos e planos, receber avisos que escolheu, e manter o perfil. Base: execução do serviço que você pediu. Notas podem incluir convicção religiosa (dado sensível no Brasil). Só processamos isso para o caderno funcionar, e só com a sua conta.",
      },
      {
        title: "Com quem",
        body: "Google ou Apple, se você entrar por eles. Neon (banco). Apple Push Notification service se ligar avisos. Resend, se usar recuperação de senha por e-mail. A API pública para IA (/api, MCP) não lê a sua conta, notas ou grupos.",
      },
      {
        title: "O que é público",
        body: "Perfis e conteúdos que você tornar compartilháveis seguem as regras do app. Notas e grupos privados não entram em busca pública do site. Quem tem o convite de um grupo pode pedir para entrar.",
      },
      {
        title: "Prazo e exclusão",
        body: "Guardamos enquanto a conta existir. No app iOS (Perfil) você pode exportar dados e excluir a conta. A exclusão apaga notas, grupos em que você era o único membro, coleções, planos pessoais, avisos e a sessão. Grupos com outras pessoas continuam, sem o seu usuário.",
      },
      {
        title: "Seus direitos (LGPD)",
        body: "Acesso, correção (editar perfil), portabilidade (exportar), exclusão da conta, e informação sobre o uso. Para exercer: Perfil no app, ou Contato em katecheo.app/contact. Você pode desligar cada tipo de aviso.",
      },
    ],
  },
  en: {
    title: "Privacy",
    updated: "Updated 11 November 2026",
    sections: [
      {
        title: "Who we are",
        body: "Katecheo (katecheo.app; verse2note.com redirects to katecheo.app) is a native iPhone app plus a marketing site with public APIs. It helps organize Bible study: notes with references that open in your Bible app, themes, plans, groups and friends. Katecheo does not display Bible text. Operated by Beto Verlí. Contact: katecheo.app/contact or github.com/betoverli/katecheo.",
      },
      {
        title: "What we store",
        body: "On device (iOS): local preferences and cache needed by the app. With an account: email and name (Google, Apple, or sign-up); handle, name, photo; preferences; notes and speakers; collections; plans; groups and members; friend links; APNs push tokens; in-app alerts. No third-party analytics or ads.",
      },
      {
        title: "Why",
        body: "So you can sign in, sync across devices, join groups and plans, receive the alerts you chose, and keep a profile. Legal basis: performing the service you asked for. Notes may include religious belief (sensitive data in Brazil). We only process that to run the notebook, and only with your account.",
      },
      {
        title: "Who else",
        body: "Google or Apple if you sign in with them. Neon (database). Apple Push Notification service if you enable alerts. Resend if you use email password recovery. The public AI API (/api, MCP) does not read your account, notes, or groups.",
      },
      {
        title: "What is public",
        body: "Profiles and content you choose to share follow the app’s rules. Private notes and groups are not publicly searchable on the site. Anyone with a group invite can ask to join.",
      },
      {
        title: "How long, and deletion",
        body: "We keep data while the account exists. In the iOS app (Profile) you can export data and delete the account. Deletion removes notes, groups where you were the only member, collections, personal plans, alerts, and the session. Groups with other people stay, without your user.",
      },
      {
        title: "Your rights (LGPD)",
        body: "Access, correction (edit profile), portability (export), account deletion, and information about use. Use Profile in the app, or Contact at katecheo.app/contact. You can turn each alert type off.",
      },
    ],
  },
  es: {
    title: "Privacidad",
    updated: "Actualizado el 11 de noviembre de 2026",
    sections: [
      {
        title: "Quiénes somos",
        body: "Katecheo (katecheo.app; verse2note.com redirige a katecheo.app) es una app nativa para iPhone y un sitio de marketing con APIs públicas. Ayuda a organizar el estudio bíblico: notas con referencias que abren en tu app de Biblia, temas, planes, grupos y amigos. Katecheo no muestra el texto bíblico. Operado por Beto Verlí. Contacto: katecheo.app/contact o github.com/betoverli/katecheo.",
      },
      {
        title: "Qué guardamos",
        body: "En el aparato (iOS): preferencias locales y caché necesarios para la app. Con cuenta: correo y nombre (Google, Apple o registro); handle, nombre, foto; preferencias; notas y speakers; colecciones; planes; grupos y miembros; vínculos; tokens de push (APNs); bandeja de avisos. No usamos analítica de terceros ni anuncios.",
      },
      {
        title: "Para qué",
        body: "Para que entres, sincronices entre aparatos, participes en grupos y planes, recibas los avisos que elegiste y mantengas el perfil. Base: prestar el servicio que pediste. Las notas pueden incluir convicción religiosa (dato sensible en Brasil). Solo las procesamos para que el cuaderno funcione, y solo con tu cuenta.",
      },
      {
        title: "Con quién",
        body: "Google o Apple, si entras con ellos. Neon (base de datos). Apple Push Notification service si activas avisos. Resend, si usas recuperación de contraseña por correo. La API pública para IA (/api, MCP) no lee tu cuenta, notas ni grupos.",
      },
      {
        title: "Qué es público",
        body: "Los perfiles y contenidos que elijas compartir siguen las reglas de la app. Notas y grupos privados no salen en búsqueda pública del sitio. Quien tiene la invitación de un grupo puede pedir entrar.",
      },
      {
        title: "Plazo y eliminación",
        body: "Guardamos mientras exista la cuenta. En la app iOS (Perfil) puedes exportar datos y borrar la cuenta. La eliminación borra notas, grupos en los que eras el único miembro, colecciones, planes personales, avisos y la sesión. Los grupos con otras personas siguen, sin tu usuario.",
      },
      {
        title: "Tus derechos (LGPD)",
        body: "Acceso, corrección (editar perfil), portabilidad (exportar), eliminación de la cuenta e información sobre el uso. Ejércelos en Perfil en la app, o Contacto en katecheo.app/contact. Puedes apagar cada tipo de aviso.",
      },
    ],
  },
};

export function privacyCopy(locale: Locale) {
  return COPY[locale] ?? COPY.pt;
}
