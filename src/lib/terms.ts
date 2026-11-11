import type { Locale } from "@/lib/bible/books";
import { CONTACT_EMAIL } from "@/lib/app-store";

type Copy = {
  title: string;
  updated: string;
  sections: { title: string; body: string }[];
};

const COPY: Record<Locale, Copy> = {
  pt: {
    title: "Termos de uso",
    updated: "Atualizado em 11 de novembro de 2026",
    sections: [
      {
        title: "Serviço",
        body: "Katecheo é um aplicativo para iPhone (e APIs públicas para agentes) que ajuda a organizar estudo bíblico: notas com referências que abrem no seu app de Bíblia, temas, planos de leitura, grupos e amigos. O Katecheo não exibe o texto bíblico. Operado por Beto Verlí.",
      },
      {
        title: "Conta",
        body: "Algumas funções pedem conta (e-mail/senha, Google ou Sign in with Apple). Você é responsável pelas credenciais e pelo conteúdo que publica em notas e grupos. Não use o serviço para spam, abuso ou conteúdo ilegal.",
      },
      {
        title: "Conteúdo e Escritura",
        body: "Referências bíblicas abrem no app de Bíblia que você escolher. Direitos sobre traduções bíblicas pertencem aos respectivos editores. Suas notas e materiais que você cria continuam seus.",
      },
      {
        title: "Disponibilidade",
        body: "O app e as APIs podem mudar, pausar ou encerrar. Não garantimos disponibilidade ininterrupta. Funções em pré-lançamento (“em breve”) podem mudar antes da publicação na App Store.",
      },
      {
        title: "Contato",
        body: `Dúvidas sobre estes termos: escreva para ${CONTACT_EMAIL}, use katecheo.app/contact ou o repositório github.com/betoverli/katecheo.`,
      },
    ],
  },
  en: {
    title: "Terms of use",
    updated: "Updated November 11, 2026",
    sections: [
      {
        title: "Service",
        body: "Katecheo is an iPhone app (plus public APIs for agents) that helps organize Bible study: notes with references that open in your Bible app, themes, reading plans, groups and friends. Katecheo does not display Bible text. Operated by Beto Verlí.",
      },
      {
        title: "Account",
        body: "Some features require an account (email/password, Google, or Sign in with Apple). You are responsible for your credentials and for content you publish in notes and groups. Do not use the service for spam, abuse, or illegal content.",
      },
      {
        title: "Content and Scripture",
        body: "Bible references open in the Bible app you choose. Rights in Bible translations belong to their publishers. Notes and materials you create remain yours.",
      },
      {
        title: "Availability",
        body: "The app and APIs may change, pause, or end. We do not guarantee uninterrupted availability. Pre-launch (“coming soon”) features may change before App Store release.",
      },
      {
        title: "Contact",
        body: `Questions about these terms: email ${CONTACT_EMAIL}, use katecheo.app/contact, or github.com/betoverli/katecheo.`,
      },
    ],
  },
  es: {
    title: "Términos de uso",
    updated: "Actualizado el 11 de noviembre de 2026",
    sections: [
      {
        title: "Servicio",
        body: "Katecheo es una app para iPhone (y APIs públicas para agentes) que ayuda a organizar el estudio bíblico: notas con referencias que abren en tu app de Biblia, temas, planes de lectura, grupos y amigos. Katecheo no muestra el texto bíblico. Operado por Beto Verlí.",
      },
      {
        title: "Cuenta",
        body: "Algunas funciones requieren cuenta (correo/contraseña, Google o Sign in with Apple). Eres responsable de tus credenciales y del contenido que publicas en notas y grupos. No uses el servicio para spam, abuso o contenido ilegal.",
      },
      {
        title: "Contenido y Escritura",
        body: "Las referencias bíblicas abren en la app de Biblia que elijas. Los derechos de las traducciones pertenecen a sus editores. Tus notas y materiales que creas siguen siendo tuyos.",
      },
      {
        title: "Disponibilidad",
        body: "La app y las APIs pueden cambiar, pausarse o terminar. No garantizamos disponibilidad ininterrumpida. Funciones en prelanzamiento (“próximamente”) pueden cambiar antes de la publicación en App Store.",
      },
      {
        title: "Contacto",
        body: `Preguntas sobre estos términos: escribe a ${CONTACT_EMAIL}, usa katecheo.app/contact o github.com/betoverli/katecheo.`,
      },
    ],
  },
};

export function termsCopy(locale: Locale): Copy {
  return COPY[locale] ?? COPY.pt;
}
