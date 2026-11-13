import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const paths = [
  "scripts/admin/workbench-grant-pro.sql",
  "scripts/admin/workbench-grant-pro-by-username.sql",
] as const;

describe("Workbench Pro grant source contract", () => {
  for (const path of paths) {
    it(path + " requires a deliberate source classification", () => {
      const sql = readFileSync(resolve(path), "utf8");

      expect(sql).toContain("v_grant_source text := 'CHANGE_ME';");
      expect(sql).toMatch(
        /v_grant_source\s+not\s+in\s*\(\s*'test'\s*,\s*'gift'\s*,\s*'commercial'\s*,\s*'other'\s*\)/i,
      );
      expect(sql).toContain("v_grant_source,");
      expect(sql).toContain("a.grant_source = v_grant_source");
      expect(sql).not.toContain("manual_workbench");
    });
  }
});
