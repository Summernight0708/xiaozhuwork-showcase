import { readFileSync } from "node:fs";
import { resolve, join } from "node:path";

import sharedGlobalSetup from "../e2e/global-setup";

export default async function globalSetup() {
  const expectedRoot = resolve("../xiaozhuwork-ui-visual-validation");
  const actualRoot = resolve(
    process.env.XIAOZHUWORK_E2E_SUPABASE_WORKDIR || ".",
  );
  if (actualRoot !== expectedRoot) {
    throw new Error(
      "UI visual tests require the exact disposable UI-review Supabase workdir.",
    );
  }
  const config = readFileSync(
    join(actualRoot, "supabase", "config.toml"),
    "utf8",
  );
  if (
    !/^project_id\s*=\s*"xiaozhuwork_ui_review_20261013"/m.test(config) ||
    !/^port\s*=\s*56922\s*$/m.test(config) ||
    !/^port\s*=\s*56921\s*$/m.test(config)
  ) {
    throw new Error(
      "Refusing visual E2E: disposable database identity mismatch.",
    );
  }
  return sharedGlobalSetup();
}
