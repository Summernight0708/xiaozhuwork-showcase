import { describe, expect, it } from "vitest";
import {
  HELP_ARTICLES,
  HELP_CATEGORIES,
  findHelpArticle,
  searchHelpArticles,
} from "@/content/help/articles";
import {
  HELP_GUIDES,
  findHelpGuide,
  searchHelpGuides,
} from "@/content/help/guides";
import { HELP_EXAMPLES, findHelpExample } from "@/content/help/examples";

describe("complete help content", () => {
  it("ships unique articles for every major feature category and all read-only examples", () => {
    expect(new Set(HELP_ARTICLES.map((article) => article.id)).size).toBe(
      HELP_ARTICLES.length,
    );
    expect(
      HELP_CATEGORIES.every((category) =>
        HELP_ARTICLES.some((article) => article.category === category),
      ),
    ).toBe(true);
    expect(HELP_ARTICLES.length).toBeGreaterThanOrEqual(25);
    expect(
      HELP_ARTICLES.every(
        (article) => article.steps.length >= 3 && article.keywords.length > 0,
      ),
    ).toBe(true);
    expect(
      HELP_EXAMPLES.every((example) =>
        Boolean(findHelpArticle(example.articleId)),
      ),
    ).toBe(true);
    expect(findHelpExample("nonsense")).toBeUndefined();
  });
  it("consolidates all 27 legacy sections into eight discoverable process guides", () => {
    expect(HELP_GUIDES).toHaveLength(8);
    const sectionIds = HELP_GUIDES.flatMap((guide) => guide.articleIds);
    expect(new Set(sectionIds).size).toBe(HELP_ARTICLES.length);
    expect(new Set(sectionIds)).toEqual(
      new Set(HELP_ARTICLES.map((item) => item.id)),
    );
    expect(findHelpGuide("review")?.id).toBe("guide-submission");
    expect(findHelpGuide("guide-submission")?.articles.length).toBe(3);
    expect(
      searchHelpGuides("主负责人").some(
        (guide) => guide.id === "guide-task-team",
      ),
    ).toBe(true);
    expect(
      searchHelpGuides("回滚").some((guide) => guide.id === "guide-files"),
    ).toBe(true);
  });
  it("searches by goals, function and keywords and handles unknown deep links", () => {
    expect(
      searchHelpArticles("回滚").some(
        (article) => article.id === "file-rollback",
      ),
    ).toBe(true);
    expect(searchHelpArticles("Pro", "Pro 高级功能").length).toBeGreaterThan(1);
    expect(searchHelpArticles("   ")).toHaveLength(HELP_ARTICLES.length);
    expect(findHelpArticle("does-not-exist")).toBeUndefined();
  });
});
