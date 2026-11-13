import { writeFileSync } from "node:fs";
import postgres from "postgres";
import { expect, test, type Page } from "@playwright/test";
import { localSupabase, registerWithPassword } from "./local-supabase";

function future(days: number) {
  const d = new Date(Date.now() + days * 86400000);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
}

export async function contrastIssues(page: Page) {
  return page.evaluate(() => {
    const rgba = (value: string): number[] => {
      const alphaFrom = (raw: string | undefined) => {
        if (!raw) return 1;
        return raw.endsWith("%") ? Number(raw.slice(0, -1)) / 100 : Number(raw);
      };
      const encodeSrgb = (part: number) => {
        const clamped = Math.max(0, Math.min(1, part));
        return (
          255 *
          (clamped <= 0.0031308
            ? 12.92 * clamped
            : 1.055 * clamped ** (1 / 2.4) - 0.055)
        );
      };
      const oklch = value.match(
        /^oklch\(\s*([\d.]+)(%)?\s+([\d.]+)\s+([-\d.]+)(?:deg)?(?:\s*\/\s*([\d.]+%?))?/i,
      );
      if (oklch) {
        const lightness = Number(oklch[1]) / (oklch[2] ? 100 : 1);
        const chroma = Number(oklch[3]);
        const hue = (Number(oklch[4]) * Math.PI) / 180;
        const a = chroma * Math.cos(hue);
        const b = chroma * Math.sin(hue);
        const l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3;
        const m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3;
        const s = (lightness - 0.0894841775 * a - 1.291485548 * b) ** 3;
        return [
          encodeSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
          encodeSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
          encodeSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
          alphaFrom(oklch[5]),
        ];
      }
      const srgb = value.match(
        /^color\(srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*\/\s*([\d.]+%?))?/i,
      );
      if (srgb) {
        return [
          Number(srgb[1]) * 255,
          Number(srgb[2]) * 255,
          Number(srgb[3]) * 255,
          alphaFrom(srgb[4]),
        ];
      }
      const channels = value.match(/[\d.]+/g)?.map(Number) || [];
      return channels.length >= 3
        ? [channels[0]!, channels[1]!, channels[2]!, channels[3] ?? 1]
        : [0, 0, 0, 0];
    };
    const composite = (a: number[], b: number[]): number[] => {
      const alpha = a[3]! + b[3]! * (1 - a[3]!);
      return [0, 1, 2]
        .map(
          (i) => (a[i]! * a[3]! + b[i]! * b[3]! * (1 - a[3]!)) / (alpha || 1),
        )
        .concat(alpha);
    };
    const luminance = (c: number[]) => {
      const v = c.slice(0, 3).map((n) => {
        const x = n / 255;
        return x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
      });
      return v[0]! * 0.2126 + v[1]! * 0.7152 + v[2]! * 0.0722;
    };
    const ratio = (a: number[], b: number[]) => {
      const l = [luminance(a), luminance(b)].sort((a, b) => b - a);
      return (l[0]! + 0.05) / (l[1]! + 0.05);
    };
    const issues: {
      selector: string;
      text: string;
      ratio: number;
      color: string;
      background: string;
    }[] = [];
    const selectors =
      "main h1,main h2,main h3,main p,main button,main label,main a,main span,main strong,main small,main li,main th,main td,main select,main input,main summary,main dt,main dd";
    for (const el of document.querySelectorAll<HTMLElement>(selectors)) {
      const rect = el.getBoundingClientRect();
      if (
        !rect.width ||
        !rect.height ||
        rect.bottom < 0 ||
        rect.top > innerHeight + 2400
      )
        continue;
      const cs = getComputedStyle(el);
      if (
        cs.visibility === "hidden" ||
        cs.display === "none" ||
        Number(cs.opacity) < 0.6
      )
        continue;
      const text = (
        el instanceof HTMLInputElement
          ? el.value || el.placeholder
          : el instanceof HTMLSelectElement
            ? el.value
            : el.textContent || ""
      ).trim();
      if (
        !text ||
        text.length > 130 ||
        Array.from(el.children).some(
          (x) =>
            x instanceof HTMLElement &&
            x.textContent?.trim() &&
            getComputedStyle(x).display !== "none",
        )
      )
        continue;
      const parent: HTMLElement[] = [];
      for (let e: HTMLElement | null = el; e; e = e.parentElement)
        parent.push(e);
      let bg: number[] = [255, 255, 255, 1];
      for (const e of parent.reverse())
        bg = composite(rgba(getComputedStyle(e).backgroundColor), bg);
      const fg = rgba(cs.color);
      if (fg[3]! < 0.75) continue;
      const value = ratio(fg, bg),
        size = parseFloat(cs.fontSize),
        big = size >= 24 || (size >= 18.66 && parseInt(cs.fontWeight) >= 700);
      if (value < (big ? 3 : 4.5))
        issues.push({
          selector:
            el.tagName.toLowerCase() +
            "." +
            (typeof el.className === "string"
              ? el.className.trim().replace(/\s+/g, ".")
              : ""),
          text: text.slice(0, 45),
          ratio: Math.round(value * 100) / 100,
          color: cs.color,
          background: "rgb(" + bg.slice(0, 3).map(Math.round).join(",") + ")",
        });
    }
    return issues.sort((a, b) => a.ratio - b.ratio).slice(0, 35);
  });
}

test("dark mode visual audit of every primary route", async ({
  page,
}, info) => {
  test.setTimeout(540000);
  await page.goto("/login");
  await page.evaluate(() =>
    localStorage.setItem("xiaozhuwork-appearance", "dark"),
  );
  await page.reload();
  const email =
    "dark-audit-" + info.project.name + "-" + Date.now() + "@example.com";
  await registerWithPassword(page, email);
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15000 });
  await page.goto("/account/settings");
  await page.locator('input[name="displayName"]').fill("Dark QA");
  await page.getByRole("button", { name: "保存资料" }).click();
  await expect(page).toHaveURL(/\/projects$/, { timeout: 15000 });
  await page.goto("/projects/create");
  await page
    .getByPlaceholder("例如：计算机视觉课程设计")
    .fill("Dark Visual QA");
  await page.locator("#start-date").fill(future(1));
  await page.locator("#deadline").fill(future(12));
  await page.getByRole("button", { name: "继续确认" }).click();
  await page.getByRole("button", { name: "确认创建" }).click();
  await expect(page).toHaveURL(/\/projects\/[0-9a-f-]+$/, { timeout: 15000 });
  const id = page.url().match(/\/projects\/([^/?]+)/)![1]!;
  const routes = [
    "/projects",
    "/workspace/todo",
    "/workspace/cross-project",
    "/projects/create",
    "/projects/" + id,
    "/projects/" + id + "/todos",
    "/projects/" + id + "/tasks",
    "/projects/" + id + "/tasks/new",
    "/projects/" + id + "/files",
    "/projects/" + id + "/reviews",
    "/projects/" + id + "/contributions",
    "/projects/" + id + "/members",
    "/projects/" + id + "/analytics",
    "/projects/" + id + "/permissions",
    "/projects/" + id + "/integrations",
    "/projects/" + id + "/invitations",
    "/projects/" + id + "/settings",
    "/notifications",
    "/account/settings",
    "/upgrade",
    "/help",
    "/help/dependencies",
    "/download",
  ];
  const failures: {
    route: string;
    issues: Awaited<ReturnType<typeof contrastIssues>>;
  }[] = [];
  for (const route of routes) {
    await page.goto(route);
    await page
      .locator("main")
      .first()
      .waitFor({ state: "visible", timeout: 15000 });
    await page.waitForTimeout(200);
    expect(await page.locator("html").getAttribute("data-theme")).toBe("dark");
    // Guard against an incorrectly compiled Vue :global selector that inverted the entire document.
    expect(
      await page.locator("html").evaluate((el) => getComputedStyle(el).filter),
    ).toBe("none");
    if (route === "/workspace/todo")
      writeFileSync(
        info.outputPath("computed-theme.json"),
        JSON.stringify(
          await page.evaluate(() =>
            [
              document.documentElement,
              document.body,
              document.querySelector(".app-shell"),
              document.querySelector(".shell-main"),
              document.querySelector(".page-heading h1"),
              document.querySelector(".page-heading p"),
              document.querySelector(".state-wrap"),
            ]
              .filter(Boolean)
              .map((e) => ({
                element: e?.tagName,
                cls: e?.className,
                bg: getComputedStyle(e!).backgroundColor,
                color: getComputedStyle(e!).color,
                filter: getComputedStyle(e!).filter,
                tuInk: getComputedStyle(e!).getPropertyValue("--tu-ink"),
                shellInk: getComputedStyle(e!).getPropertyValue(
                  "--shell-warm-ink",
                ),
              })),
          ),
          null,
          2,
        ),
      );
    const issues = await contrastIssues(page);
    const key = route
      .replace(id, "project")
      .replace(/[^a-z0-9]+/gi, "-")
      .replace(/^-|-$/g, "");
    await page.screenshot({
      path: info.outputPath("dark-" + key + ".png"),
      fullPage: true,
    });
    if (issues.length)
      failures.push({
        route: route.replace(id, ":id"),
        issues: issues.slice(0, 12),
      });
  }

  // Exercise a real task detail and a second pass with actual Pro permissions.
  // The seed is restricted to the local disposable Playwright Supabase database.
  await page.goto("/projects/" + id + "/tasks/new");
  await page.getByLabel("任务名称 *").fill("Dark QA task");
  await page.getByLabel("截止时间 *").fill(future(5));
  // Seed the test task without depending on mobile sticky-nav pointer hit testing.
  // Actual submit interactions are covered by the separate task workflow smoke test.
  await page
    .getByRole("button", { name: "创建任务" })
    .evaluate((el) => (el as HTMLButtonElement).click());
  await expect(page).toHaveURL(/\/tasks\/[0-9a-f-]+$/, { timeout: 15000 });
  const taskRoute = new URL(page.url()).pathname;
  await page.waitForTimeout(250);
  const taskIssues = await contrastIssues(page);
  await page.screenshot({
    path: info.outputPath("dark-task-detail.png"),
    fullPage: true,
  });
  if (taskIssues.length)
    failures.push({
      route: "/projects/:id/tasks/:taskId",
      issues: taskIssues.slice(0, 12),
    });

  const url = localSupabase().dbUrl;
  if (
    !/^postgresql?:\/\/[^@]+@(?:127\.0\.0\.1|localhost):54322\/postgres$/.test(
      url,
    )
  )
    throw Error("Dark audit DB must be local");
  const db = postgres(url, { max: 1 });
  try {
    const rows = await db.unsafe("select id from auth.users where email=$1", [
      email,
    ]);
    const uid = rows[0]?.id as string | undefined;
    if (!uid) throw Error("Missing local dark audit user");
    await db.unsafe(
      "insert into public.account_entitlements(user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version) values($1,'pro','active',now()-interval '1 day',now()+interval '15 days',now(),$1,'test',1)",
      [uid],
    );
  } finally {
    await db.end();
  }
  const proRoutes = [
    "/workspace/cross-project",
    "/projects/" + id + "/analytics",
    "/projects/" + id + "/permissions",
    "/projects/" + id + "/integrations",
    "/projects/" + id + "/files",
    "/projects/" + id + "/contributions",
    taskRoute,
  ];
  for (const route of proRoutes) {
    await page.goto(route);
    await page
      .locator("main")
      .first()
      .waitFor({ state: "visible", timeout: 15000 });
    await page.waitForTimeout(320);
    const issues = await contrastIssues(page);
    const key = route
      .replace(id, "project")
      .replace(/[^a-z0-9]+/gi, "-")
      .replace(/^-|-$/g, "");
    await page.screenshot({
      path: info.outputPath("dark-pro-" + key + ".png"),
      fullPage: true,
    });
    if (issues.length)
      failures.push({
        route: "Pro " + route.replace(id, ":id"),
        issues: issues.slice(0, 12),
      });
  }
  writeFileSync(
    info.outputPath("contrast-results.json"),
    JSON.stringify(failures, null, 2),
  );
  expect(
    failures.length,
    `Contrast violations on ${failures.map((x) => x.route).join(", ")}`,
  ).toBe(0);
});
