import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

describe("notification message layout", () => {
  it("preserves explicit line breaks in notification bodies", () => {
    const source = readFileSync(
      resolve("src/components/notification/NotificationItem.vue"),
      "utf8",
    );

    expect(source).toContain(".context {");
    expect(source).toContain("white-space: pre-line;");
    expect(source).toContain("overflow-wrap: anywhere;");
  });
});
