import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

describe("Xiaozhu brand assets", () => {
  it("vendors the filled pig and wires the favicon without a runtime CDN", () => {
    const pig = readFileSync(resolve("src/assets/brand/pig.svg"), "utf8");
    const favicon = readFileSync(resolve("public/favicon.svg"), "utf8");
    const html = readFileSync(resolve("index.html"), "utf8");

    expect(pig).toContain('fill="currentColor"');
    expect(pig).toContain("<path");
    expect(favicon).toBe(pig);
    expect(html).toContain('href="/favicon.svg"');
    expect(html).toContain("<title>小猪作业</title>");
    expect(html).not.toContain("TeamUp");
  });

  it("keeps user-visible auth and report branding on 小猪作业", () => {
    const config = readFileSync(resolve("supabase/config.toml"), "utf8");
    const confirmation = readFileSync(
      resolve("supabase/templates/confirmation.html"),
      "utf8",
    );
    const reportExport = readFileSync(
      resolve("supabase/functions/_shared/report-export.ts"),
      "utf8",
    );

    expect(config).toContain('subject = "小猪作业登录验证码"');
    expect(config).toContain("[auth.email.template.confirmation]");
    expect(config).toContain("[auth.email.template.magic_link]");
    expect(config).not.toContain('subject = "TeamUp 登录验证码"');
    expect(confirmation).toContain("你的小猪作业登录验证码是");
    expect(confirmation).not.toContain("你的 TeamUp 登录验证码是");
    expect(reportExport).toContain('"小猪作业贡献报告"');
  });
});
