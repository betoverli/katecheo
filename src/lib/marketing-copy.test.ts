import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import {
  MARKETING,
  SCREENSHOT_ORDER,
  SCREENSHOT_SIZE,
  type MarketingScreenshotId,
} from "./marketing-copy.ts";

const root = new URL("../../", import.meta.url);
const rootPath = fileURLToPath(root);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

const LIVE: Record<"pt" | "en" | "es", string> = {
  pt: "Disponível na App Store",
  en: "Available on the App Store",
  es: "Disponible en el App Store",
};

const COMING_SOON = /Em breve no iPhone|Coming soon on iPhone|Próximamente en iPhone/;

describe("marketing copy — App Store live", () => {
  it("uses Available on the App Store wording in meta, OG, and about copy", () => {
    for (const locale of ["pt", "en", "es"] as const) {
      assert.match(MARKETING[locale].metaDescription, new RegExp(LIVE[locale]));
      assert.doesNotMatch(MARKETING[locale].metaDescription, COMING_SOON);
      assert.equal(MARKETING[locale].availableOnAppStore, LIVE[locale]);
    }

    const site = JSON.parse(read("src/lib/og/site.json")) as { description: string };
    assert.match(site.description, /Disponível na App Store/);
    assert.doesNotMatch(site.description, COMING_SOON);

    const groups = read("src/routes/groups.$id.tsx");
    assert.match(groups, /MARKETING\.pt\.metaDescription/);
    assert.doesNotMatch(groups, COMING_SOON);

    const about = read("src/components/about-page.tsx");
    assert.match(about, /availableOnAppStore/);
    assert.doesNotMatch(about, /comingSoon/);
  });

  it("renders official localized App Store screenshots on the landing page", () => {
    assert.equal(existsSync(new URL("scripts/app-store-screenshots.json", root)), true);
    assert.equal(existsSync(new URL("scripts/materialize-screenshots.mjs", root)), true);
    const pkg = JSON.parse(read("package.json")) as { scripts: Record<string, string> };
    assert.match(pkg.scripts.build, /materialize-screenshots/);
    assert.match(pkg.scripts.dev, /materialize-screenshots/);

    const generated = spawnSync(process.execPath, ["scripts/materialize-screenshots.mjs"], {
      cwd: rootPath,
      encoding: "utf8",
    });
    assert.equal(generated.status, 0, generated.stderr || generated.stdout);

    const landing = read("src/components/landing.tsx");
    assert.match(landing, /SCREENSHOT_ORDER/);
    assert.match(landing, /\/screenshots\/\$\{locale\}\/\$\{id\}/);
    assert.match(landing, /image\/avif/);
    assert.match(landing, /image\/webp/);
    assert.doesNotMatch(
      landing,
      /PhoneFrame|NotesPlaceholder|ThemesPlaceholder|ReadingPlaceholder|GroupsPlaceholder/,
    );

    for (const locale of ["pt", "en", "es"] as const) {
      for (const id of SCREENSHOT_ORDER satisfies MarketingScreenshotId[]) {
        assert.equal(
          existsSync(new URL(`public/screenshots/${locale}/${id}.webp`, root)),
          true,
          `${locale}/${id}.webp`,
        );
        assert.equal(
          existsSync(new URL(`public/screenshots/${locale}/${id}.avif`, root)),
          true,
          `${locale}/${id}.avif`,
        );
        assert.ok(MARKETING[locale].screenshotAlts[id].startsWith("Katecheo"));
      }
    }

    assert.equal(SCREENSHOT_SIZE.width, 800);
    assert.equal(SCREENSHOT_SIZE.height, 1738);
    assert.equal(SCREENSHOT_ORDER.length, 5);
  });
});
