import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

describe("Xiaozhu visual interaction contracts", () => {
  it("keeps the locked sage palette while routing Vant buttons through semantic tokens", () => {
    const css = readFileSync(resolve("src/assets/main.css"), "utf8");
    const tokens = readFileSync(resolve("tokens.css"), "utf8");

    expect(tokens).toContain("--color-accent:");
    expect(tokens).toContain("--tu-blue: var(--color-accent)");
    expect(tokens).toContain("--tu-action: var(--color-accent)");
    expect(tokens).toContain(
      "--van-button-primary-background: var(--tu-action)",
    );
    expect(tokens).toContain(
      "--van-button-default-border-color: var(--tu-action-border)",
    );
    expect(tokens).toContain("--van-button-disabled-opacity: 0.46");
    expect(tokens).toContain(':root[data-theme="dark"]');
    expect(css).toContain("outline: 3px solid var(--tu-focus-ring)");
  });

  it("uses the existing pig mark and warm tokenized invite surfaces without the legacy blue T brand", () => {
    const invite = readFileSync(
      resolve("src/views/InviteTokenView.vue"),
      "utf8",
    );

    expect(invite).toContain('import pigLogo from "@/assets/brand/pig.svg";');
    expect(invite).toContain(
      '<img :src="pigLogo" alt="" width="20" height="20" />',
    );
    expect(invite).not.toContain("<span>T</span>");
    expect(invite).not.toContain("background: var(--tu-blue);");
    expect(invite).not.toContain("color: var(--tu-blue-strong);");
    expect(invite).toContain("--invite-bg: var(--tu-bg)");
    expect(invite).toContain("--invite-surface: var(--tu-surface)");
    expect(invite).toContain(
      ':global(:root[data-theme="dark"] .invite-brand-mark)',
    );
  });
});
