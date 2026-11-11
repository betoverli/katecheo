import type { Locale } from "@/lib/bible/books";

export type MarketingFeatureId = "notes" | "themes" | "reading" | "groups";

type MarketingCopy = {
  metaTitle: string;
  metaDescription: string;
  tagline: string;
  lead: string;
  comingSoon: string;
  openAppStore: string;
  featuresEyebrow: string;
  features: Record<
    MarketingFeatureId,
    { title: string; body: string; visual: string }
  >;
  instagram: string;
  footerPrivacy: string;
  footerTerms: string;
  footerContact: string;
  footerForAi: string;
  footerRights: string;
};

export const MARKETING: Record<Locale, MarketingCopy> = {
  pt: {
    metaTitle: "Katecheo — Seu estudo bíblico, organizado",
    metaDescription:
      "Notas com referências que abrem no seu app de Bíblia, temas, planos de leitura, grupos e amigos. Em breve no iPhone. Katecheo nunca mostra o texto bíblico.",
    tagline: "Seu estudo bíblico, organizado",
    lead: "Anote o que importa, ligue às Escrituras no app de Bíblia que você já usa, e compartilhe com quem estuda junto.",
    comingSoon: "Em breve no iPhone",
    openAppStore: "Baixar na App Store",
    featuresEyebrow: "No iPhone",
    features: {
      notes: {
        title: "Notas com referências",
        body: "Escreva no caderno e marque passagens. Cada referência abre no seu app de Bíblia — o Katecheo nunca mostra o texto bíblico.",
        visual: "Caderno",
      },
      themes: {
        title: "Temas",
        body: "Coleções temáticas prontas para estudar, copiar e guardar — organizadas para achar o que precisa rápido.",
        visual: "Temas",
      },
      reading: {
        title: "Planos de leitura",
        body: "Planos de capítulos inteiros, do ano aos Evangelhos. Acompanhe o ritmo e continue de onde parou.",
        visual: "Leitura",
      },
      groups: {
        title: "Grupos e amigos",
        body: "Estude com outras pessoas: compartilhe notas, convide amigos e acompanhe o grupo no mesmo lugar.",
        visual: "Grupos",
      },
    },
    instagram: "Instagram",
    footerPrivacy: "Privacidade",
    footerTerms: "Termos",
    footerContact: "Contato",
    footerForAi: "Ferramentas de IA",
    footerRights: "Katecheo",
  },
  en: {
    metaTitle: "Katecheo — Your Bible study, organized",
    metaDescription:
      "Notes with references that open in your own Bible app, themes, reading plans, groups and friends. Coming soon on iPhone. Katecheo never shows Bible text.",
    tagline: "Your Bible study, organized",
    lead: "Capture what matters, link it to Scripture in the Bible app you already use, and share with the people you study with.",
    comingSoon: "Coming soon on iPhone",
    openAppStore: "Download on the App Store",
    featuresEyebrow: "On iPhone",
    features: {
      notes: {
        title: "Notes with references",
        body: "Write in your notebook and mark passages. Each reference opens in your Bible app — Katecheo never shows Bible text.",
        visual: "Notebook",
      },
      themes: {
        title: "Themes",
        body: "Ready-made themed collections to study, copy, and save — organized so you find what you need quickly.",
        visual: "Themes",
      },
      reading: {
        title: "Reading plans",
        body: "Whole-chapter plans, from a year to the Gospels. Keep your pace and pick up where you left off.",
        visual: "Reading",
      },
      groups: {
        title: "Groups and friends",
        body: "Study with others: share notes, invite friends, and keep the group in one place.",
        visual: "Groups",
      },
    },
    instagram: "Instagram",
    footerPrivacy: "Privacy",
    footerTerms: "Terms",
    footerContact: "Contact",
    footerForAi: "AI tools",
    footerRights: "Katecheo",
  },
  es: {
    metaTitle: "Katecheo — Tu estudio bíblico, organizado",
    metaDescription:
      "Notas con referencias que abren en tu app de Biblia, temas, planes de lectura, grupos y amigos. Próximamente en iPhone. Katecheo nunca muestra el texto bíblico.",
    tagline: "Tu estudio bíblico, organizado",
    lead: "Anota lo importante, enlázalo a la Escritura en la app de Biblia que ya usas y comparte con quienes estudian contigo.",
    comingSoon: "Próximamente en iPhone",
    openAppStore: "Descargar en App Store",
    featuresEyebrow: "En iPhone",
    features: {
      notes: {
        title: "Notas con referencias",
        body: "Escribe en el cuaderno y marca pasajes. Cada referencia abre en tu app de Biblia — Katecheo nunca muestra el texto bíblico.",
        visual: "Cuaderno",
      },
      themes: {
        title: "Temas",
        body: "Colecciones temáticas listas para estudiar, copiar y guardar — organizadas para encontrar lo que necesitas rápido.",
        visual: "Temas",
      },
      reading: {
        title: "Planes de lectura",
        body: "Planes de capítulos enteros, del año a los Evangelios. Sigue el ritmo y retoma donde lo dejaste.",
        visual: "Lectura",
      },
      groups: {
        title: "Grupos y amigos",
        body: "Estudia con otras personas: comparte notas, invita amigos y sigue al grupo en un solo lugar.",
        visual: "Grupos",
      },
    },
    instagram: "Instagram",
    footerPrivacy: "Privacidad",
    footerTerms: "Términos",
    footerContact: "Contacto",
    footerForAi: "Herramientas de IA",
    footerRights: "Katecheo",
  },
};

export const FEATURE_ORDER: MarketingFeatureId[] = ["notes", "themes", "reading", "groups"];
