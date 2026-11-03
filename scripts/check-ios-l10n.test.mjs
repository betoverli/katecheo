import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

describe("check-ios-l10n", () => {
  it("passes on the current String Catalog", () => {
    const result = spawnSync(process.execPath, ["scripts/check-ios-l10n.mjs"], {
      cwd: root,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /catálogo pt-BR\/en\/es completo/);
  });
});
