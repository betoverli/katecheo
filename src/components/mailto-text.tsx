import { CONTACT_EMAIL, CONTACT_MAILTO } from "@/lib/app-store";

/** Render plain copy with `contato@katecheo.app` as a mailto link. */
export function MailtoText({ text, className }: { text: string; className?: string }) {
  const parts = text.split(CONTACT_EMAIL);
  if (parts.length === 1) {
    return <p className={className}>{text}</p>;
  }
  return (
    <p className={className}>
      {parts.map((part, index) => (
        <span key={index}>
          {part}
          {index < parts.length - 1 ? (
            <a href={CONTACT_MAILTO} className="text-accent underline-offset-2 hover:underline">
              {CONTACT_EMAIL}
            </a>
          ) : null}
        </span>
      ))}
    </p>
  );
}
