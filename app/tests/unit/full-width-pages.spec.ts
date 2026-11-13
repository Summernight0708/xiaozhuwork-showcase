import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), "utf8");
}

function expectFullWidthRule(text: string, className: string) {
  const rule = new RegExp(
    "\\." +
      className +
      "\\s*\\{[\\s\\S]*?width:\\s*100%;[\\s\\S]*?max-width:\\s*none;",
  );
  expect(text).toMatch(rule);
}

describe("full-width app page contract", () => {
  it("lets workbench and data-dense utility pages consume AppShell width", () => {
    expectFullWidthRule(
      source("src/views/ProjectSettingsView.vue"),
      "settings-page",
    );
    expectFullWidthRule(
      source("src/views/NotificationsView.vue"),
      "notifications-page",
    );
    expectFullWidthRule(source("src/views/SettingsView.vue"), "settings-page");
    expectFullWidthRule(source("src/views/ProjectCreateView.vue"), "form-page");
    expectFullWidthRule(source("src/views/TaskCreateView.vue"), "form-page");
    expectFullWidthRule(source("src/views/UpgradeView.vue"), "upgrade-page");
    expectFullWidthRule(source("src/views/HelpCenterView.vue"), "help-center");
  });

  it("keeps long-form reading pages at an intentional text width", () => {
    expect(source("src/views/HelpArticleView.vue")).toContain(
      "max-width: 920px",
    );
  });
});
