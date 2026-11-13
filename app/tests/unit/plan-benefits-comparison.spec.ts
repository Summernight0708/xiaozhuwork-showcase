import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import PlanBenefitsComparison from "@/components/upgrade/PlanBenefitsComparison.vue";
import { PLAN_BENEFITS } from "@/components/upgrade/planBenefits";

type TestBenefitStatus = "released" | "integration_pending" | "planned";

function benefit(status: TestBenefitStatus, name: string = status) {
  return {
    name,
    free: "Free value",
    pro: "Pro value",
    status,
  };
}

describe("PlanBenefitsComparison", () => {
  it("matches the staged Phase 2 release state after Stage 8", () => {
    const byName = new Map(PLAN_BENEFITS.map((item) => [item.name, item]));

    for (const name of [
      "活跃 Free 项目",
      "项目成员",
      "并发任务",
      "完整文件历史",
      "批量回滚",
      "版本比较",
      "项目文件恢复点",
      "单文件大小",
      "项目文件存储空间",
      "增强报告",
      "高级权限",
      "项目统计",
      "外部集成",
      "跨项目总览与搜索",
      "跨项目汇总与统计",
    ]) {
      expect(byName.get(name)?.status).toBe("released");
    }
  });

  it.each(["planned", "integration_pending"] as const)(
    "keeps the desktop status column and mobile badges when a %s benefit exists",
    (status) => {
      const wrapper = mount(PlanBenefitsComparison, {
        props: {
          benefits: [benefit("released"), benefit(status)],
        },
      });

      expect(
        wrapper.findAll(".benefits-table thead th").map((node) => node.text()),
      ).toEqual(["权益", "Free", "Pro", "状态"]);
      expect(wrapper.findAll(".benefit-card .release-status")).toHaveLength(2);
    },
  );

  it("maps every benefit release status to visible text", () => {
    const wrapper = mount(PlanBenefitsComparison, {
      props: {
        benefits: [
          benefit("released", "released item"),
          benefit("integration_pending", "pending item"),
          benefit("planned", "planned item"),
        ],
      },
    });

    expect(
      wrapper
        .findAll(".benefits-table tbody .release-status")
        .map((node) => node.text()),
    ).toEqual(["已上线", "待集成", "规划中"]);
  });

  it("removes the entire desktop status column and every mobile badge when all benefits are released", () => {
    const wrapper = mount(PlanBenefitsComparison, {
      props: {
        benefits: [
          benefit("released", "first released"),
          benefit("released", "second released"),
        ],
      },
    });

    expect(
      wrapper.findAll(".benefits-table thead th").map((node) => node.text()),
    ).toEqual(["权益", "Free", "Pro"]);
    expect(
      wrapper
        .findAll(".benefits-table tbody tr")
        .every((row) => row.findAll("td").length === 2),
    ).toBe(true);
    expect(wrapper.find(".benefits-table .release-status").exists()).toBe(
      false,
    );
    expect(wrapper.find(".benefits-mobile .release-status").exists()).toBe(
      false,
    );
  });
});
