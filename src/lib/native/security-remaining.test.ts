import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../../../", import.meta.url);

function read(rel: string) {
  return readFileSync(new URL(rel, root), "utf8");
}

describe("security audit remaining (M7/L2/L4/L5/L6)", () => {
  it("gates catalog broadcast behind CATALOG_PUSH_SECRET (M7)", () => {
    const catalog = read("src/lib/catalog-push.server.ts");
    assert.match(catalog, /CATALOG_PUSH_SECRET/);
    assert.match(catalog, /authorizeCatalogBroadcast/);
    assert.match(catalog, /broadcastCatalogHint/);
    const route = read("src/routes/api/internal/catalog-push.ts");
    assert.match(route, /authorizeCatalogBroadcast/);
    assert.match(route, /x-catalog-push-secret|Bearer/);
  });

  it("listGroupsForNote requires ownership or grant (L2)", () => {
    const groups = read("src/lib/native/api/v1-groups.server.ts");
    assert.match(groups, /listGroupsForNote/);
    assert.match(groups, /note_grants/);
    assert.match(groups, /notebook_notes where id = \$\{noteId\} and user_id/);
    const web = read("src/lib/notebook-groups.ts");
    assert.match(web, /note_grants/);
  });

  it("prefers https return mode and keeps PKCE (L4)", () => {
    const ret = read("src/lib/native/return-to.ts");
    assert.match(ret, /preferredNativeReturnMode[\s\S]*return "https"/);
    assert.match(ret, /shouldFallBackToScheme/);
    const login = read("ios/App/Katecheo/NativeLoginService.swift");
    assert.match(login, /returnMode: \.https/);
    assert.match(login, /shouldFallBackToScheme/);
    assert.match(login, /newPkceVerifier|pkceChallenge/);
  });

  it("guards UIKit dequeue casts in hot list paths (L5)", () => {
    for (const file of [
      "ios/App/Katecheo/NotebookListViewController.swift",
      "ios/App/Katecheo/GroupsListViewController.swift",
      "ios/App/Katecheo/VersesScreens.swift",
      "ios/App/Katecheo/VersesHomeViewController.swift",
      "ios/App/Katecheo/ReadingScreens.swift",
      "ios/App/Katecheo/BibleRefInsertPicker.swift",
      "ios/App/Katecheo/ProfileSettingsScreens.swift",
    ]) {
      const src = read(file);
      assert.equal(
        /dequeueReusable(?:Cell|SupplementaryView)[\s\S]{0,120} as!/.test(src),
        false,
        `${file} still force-casts a dequeue`,
      );
    }
  });

  it("stamps NativeOutbox jobs with accountId and drops mismatches (L6)", () => {
    const outbox = read("ios/App/Katecheo/NativeOutbox.swift");
    assert.match(outbox, /var accountId: String\?/);
    assert.match(outbox, /LocalSessionCache\.loadMe\(\)\?\.id/);
    assert.match(outbox, /accountId != currentAccountId|job\.accountId/);
  });

  it("production VAPID refuses auto-generation (M8)", () => {
    const notify = read("src/lib/notify.server.ts");
    assert.match(notify, /VAPID_PUBLIC_KEY/);
    assert.match(notify, /refusing web push/);
    assert.match(notify, /isProductionRuntime/);
  });
});
