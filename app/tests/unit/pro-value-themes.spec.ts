import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import ProValueThemes from "@/components/upgrade/ProValueThemes.vue";

describe("ProValueThemes", () => {
  it("presents exactly three equal-weight shipped value themes", () => {
    const wrapper = mount(ProValueThemes);

    const section = wrapper.get("section.pro-value-themes");
    const articles = section.findAll("article.pro-value-theme");
    expect(articles).toHaveLength(3);

    expect(section.get("h2").text()).toBe("Pro 能带来什么");
    expect(articles.map((article) => article.get("h3").text())).toEqual([
      "更大空间",
      "更安心的成果管理",
      "更强的项目管理",
    ]);

    expect(articles[0]?.findAll("li").map((item) => item.text())).toEqual([
      "更大单文件",
      "更多项目存储",
      "更多成员",
      "更多并发任务",
    ]);
    expect(articles[1]?.findAll("li").map((item) => item.text())).toEqual([
      "完整历史",
      "版本比较",
      "批量回滚",
      "恢复点",
    ]);
    expect(articles[2]?.findAll("li").map((item) => item.text())).toEqual([
      "增强报告",
      "项目统计",
      "跨项目工作台",
      "高级权限",
      "日历订阅",
    ]);
  });

  it("does not introduce package, price, ranking, or purchase claims", () => {
    const text = mount(ProValueThemes).text();

    for (const forbidden of [
      "推荐",
      "热门",
      "月付",
      "年付",
      "套餐",
      "立即购买",
      "最划算",
    ]) {
      expect(text).not.toContain(forbidden);
    }
    expect(text).not.toMatch(/¥\s*\d/);
    expect(text).not.toMatch(/￥\s*\d/);
  });
});
