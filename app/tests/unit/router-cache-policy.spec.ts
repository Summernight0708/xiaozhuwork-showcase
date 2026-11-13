import { describe, expect, it } from "vitest";

import { createAppRouter } from "@/router";

describe("shared list/detail route cache policy", () => {
  it.each([
    ["project-files", "file-detail", "project-files"],
    ["project-reviews", "review-detail", "project-reviews"],
    ["project-contributions", "contribution-detail", "project-contributions"],
  ])(
    "reuses one KeepAlive instance for %s and %s",
    (listName, detailName, cacheKey) => {
      const routes = createAppRouter().getRoutes();
      const list = routes.find((route) => route.name === listName);
      const detail = routes.find((route) => route.name === detailName);

      expect(list?.meta.keepAlive).toBe(true);
      expect(detail?.meta.keepAlive).toBe(true);
      expect(list?.meta.cacheKey).toBe(cacheKey);
      expect(detail?.meta.cacheKey).toBe(cacheKey);
    },
  );
});
