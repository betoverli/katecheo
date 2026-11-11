import type { Locale } from "@/lib/bible/books";

type Copy = {
  title: string;
  lead: string;
  sections: { title: string; body: string }[];
};

const COPY: Record<Locale, Copy> = {
  pt: {
    title: "Contato e suporte",
    lead: "Suporte para o app Katecheo no iPhone e para as ferramentas públicas de IA.",
    sections: [
      {
        title: "E-mail / issues",
        body: "Abra uma issue ou escreva pelo repositório: github.com/betoverli/katecheo. Preferimos o GitHub para bugs e pedidos de recurso.",
      },
      {
        title: "Privacidade e conta",
        body: "Para pedidos sobre dados pessoais (LGPD), veja a Política de Privacidade. Exclusão de conta e exportação de dados ficam no app iOS (Perfil), quando a conta estiver ativa.",
      },
      {
        title: "App Store",
        body: "Esta página serve como URL de suporte do Katecheo na App Store. O produto de uso diário é o app nativo para iPhone; este site é a página de marketing e as APIs.",
      },
    ],
  },
  en: {
    title: "Contact & support",
    lead: "Support for the Katecheo iPhone app and the public AI tools.",
    sections: [
      {
        title: "Email / issues",
        body: "Open an issue or write via the repository: github.com/betoverli/katecheo. We prefer GitHub for bugs and feature requests.",
      },
      {
        title: "Privacy and account",
        body: "For personal-data requests, see the Privacy Policy. Account deletion and data export live in the iOS app (Profile) once your account is active.",
      },
      {
        title: "App Store",
        body: "This page is Katecheo’s App Store support URL. Day-to-day product use is the native iPhone app; this site is marketing plus APIs.",
      },
    ],
  },
  es: {
    title: "Contacto y soporte",
    lead: "Soporte para la app Katecheo en iPhone y para las herramientas públicas de IA.",
    sections: [
      {
        title: "Correo / issues",
        body: "Abre un issue o escribe por el repositorio: github.com/betoverli/katecheo. Preferimos GitHub para errores y peticiones.",
      },
      {
        title: "Privacidad y cuenta",
        body: "Para solicitudes de datos personales, consulta la Política de Privacidad. La eliminación de cuenta y la exportación de datos están en la app iOS (Perfil) cuando la cuenta esté activa.",
      },
      {
        title: "App Store",
        body: "Esta página es la URL de soporte de Katecheo en App Store. El uso diario del producto es la app nativa para iPhone; este sitio es marketing y APIs.",
      },
    ],
  },
};

export function contactCopy(locale: Locale): Copy {
  return COPY[locale] ?? COPY.pt;
}
