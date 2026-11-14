/**
 * Single switch for the App Store CTA on the marketing site.
 * Set `APP_STORE_URL` to the real listing URL when the app launches;
 * while null, the hero shows a “coming soon” badge instead of a live link.
 */
export const APP_STORE_ID = "6826551392";

export const APP_STORE_URL: string | null = "https://apps.apple.com/app/id6826551392";

export const APP_STORE_LIVE = Boolean(APP_STORE_URL);

export const INSTAGRAM_URL = "https://www.instagram.com/katecheo.app";

/** General public contact email (mailto on the marketing site). */
export const CONTACT_EMAIL = "contato@katecheo.app";
export const CONTACT_MAILTO = `mailto:${CONTACT_EMAIL}`;
