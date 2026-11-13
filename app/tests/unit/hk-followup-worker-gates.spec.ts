import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const checkoutRoot = process.cwd();
const script = resolve(
  checkoutRoot,
  "tests/integration/check-hk-followup-worker-gates.sh",
);

describe("HK follow-up scheduler release gates", () => {
  it.skipIf(process.platform === "win32")(
    "dispatches only approved HTTP jobs and rejects unsafe F auth revocation",
    () => {
      const result = spawnSync("bash", [script], {
        cwd: checkoutRoot,
        encoding: "utf8",
        env: { ...process.env },
        timeout: 15_000,
      });

      expect(
        result.status,
        `Scheduler gate failure: ${result.stdout}\n${result.stderr}`,
      ).toBe(0);
      expect(result.stdout).toContain("PASS");
    },
  );
});
