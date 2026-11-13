import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import MobileProjectOverview from "@/components/overview/MobileProjectOverview.vue";
import type { MobileOverviewTodoItem } from "@/domain/mobile-project-overview";

const todoItems: MobileOverviewTodoItem[] = [
  {
    id: "review:1",
    title: "验收「接口实现」",
    reason: "等待你验收",
    detail: "第 2 轮",
    priority: 1,
    target: { kind: "review", reviewRoundId: "round-1" },
  },
  {
    id: "task:1",
    title: "完成报告初稿",
    reason: "已逾期",
    deadlineAt: "2026-10-04T00:00:00.000Z",
    priority: 1,
    target: { kind: "task", taskId: "task-1" },
  },
];

describe("MobileProjectOverview", () => {
  function mountOverview() {
    return mount(MobileProjectOverview, {
      props: {
        projectId: "project-1",
        archived: false,
        projectName: "数据库课程设计",
        courseName: "数据库系统",
        deadlineAt: "2026-10-20T00:00:00.000Z",
        memberCount: 6,
        todoItems,
        flowSummary: { completed: 8, total: 18, stages: 3, blocked: 2 },
        dueSoonMemberCount: 2,
        tasks: [],
        dependencies: [],
        memberName: () => "成员",
        currentUserId: "user-1",
        initialGraphState: {},
      },
      global: {
        stubs: {
          RouterLink: {
            name: "RouterLink",
            props: ["to"],
            template: "<a><slot /></a>",
          },
          TaskFlowGraph: {
            template: '<div data-test="task-flow-graph" />',
          },
        },
      },
    });
  }

  it("uses the approved action-first mobile information hierarchy", () => {
    const wrapper = mountOverview();

    expect(wrapper.get("h1").text()).toBe("数据库课程设计");
    expect(wrapper.text()).toContain("我的待办");
    expect(wrapper.text()).toContain("查看全部我的工作");
    expect(wrapper.text()).toContain("完成 8 / 18 · 3 个阶段 · 2 项受阻");
    expect(wrapper.text()).toContain("6 位成员 · 2 人有临期任务");
    expect(wrapper.text()).not.toContain("创建任务");
    expect(wrapper.text()).not.toContain("邀请成员");
    expect(wrapper.text()).not.toContain("最近通知");
    expect(wrapper.text()).not.toContain("需要关注");
  });

  it("lazy mounts the compact task flow and keeps the collapse control outside it", async () => {
    const wrapper = mountOverview();
    const toggle = wrapper.get(".mobile-overview__toggle");

    expect(toggle.attributes("aria-expanded")).toBe("false");
    expect(wrapper.find('[data-test="task-flow-graph"]').exists()).toBe(false);

    await toggle.trigger("click");

    expect(wrapper.get(".mobile-overview__toggle").text()).toBe("收起任务流程");
    expect(
      wrapper.get(".mobile-overview__toggle").attributes("aria-expanded"),
    ).toBe("true");
    expect(wrapper.find('[data-test="task-flow-graph"]').exists()).toBe(true);
    expect(
      wrapper.get(".mobile-overview__flow-window").attributes("role"),
    ).toBe("region");

    await wrapper.get(".mobile-overview__toggle").trigger("click");
    expect(wrapper.find('[data-test="task-flow-graph"]').exists()).toBe(false);
  });

  it("routes actions to existing destinations and emits tasks to the shared drawer", async () => {
    const wrapper = mountOverview();
    const links = wrapper.findAllComponents({ name: "RouterLink" });
    const reviewLink = links.find((link) =>
      link.text().includes("验收「接口实现」"),
    );

    expect(reviewLink?.props("to")).toEqual({
      name: "review-detail",
      params: { projectId: "project-1", reviewRoundId: "round-1" },
    });

    await wrapper.get("button.mobile-overview__todo").trigger("click");
    expect(wrapper.emitted("openTask")?.[0]?.[0]).toBe("task-1");
  });
});
