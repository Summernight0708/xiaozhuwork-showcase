import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import MemberTaskFlow from "@/components/member/MemberTaskFlow.vue";
import type {
  MemberFlowMember,
  MemberFlowTask,
} from "@/domain/member-team-work";

const members: MemberFlowMember[] = [
  {
    id: "member-a",
    userId: "user-a",
    displayName: "张三",
    roleLabel: "组长",
    primaryCount: 4,
    collaboratorCount: 2,
  },
  {
    id: "member-b",
    userId: "user-b",
    displayName: "李四",
    roleLabel: "成员",
    primaryCount: 0,
    collaboratorCount: 1,
  },
];

const tasks: MemberFlowTask[] = [1, 2, 3, 4].map((index) => ({
  id: `task-${index}`,
  title: `任务 ${index}`,
  primaryUserId: "user-a",
  createdAt: "2026-10-01T00:00:00Z",
  acceptedAt: "2026-10-01T00:00:00Z",
  deadlineAt: `2026-10-${10 + index}T00:00:00Z`,
  status: "in_progress",
  statusLabel: "进行中",
  collaboratorCount: 2,
}));

function mountFlow(overrides: Record<string, unknown> = {}) {
  return mount(MemberTaskFlow, {
    props: {
      members,
      tasks,
      range: "all",
      expandedMemberId: null,
      remainingExpandedMemberId: null,
      ...overrides,
    },
  });
}

describe("MemberTaskFlow component", () => {
  it("starts collapsed and renders primary tasks only on the primary row", () => {
    const wrapper = mountFlow();
    const tracks = wrapper.findAll("[data-member-track]");
    expect(tracks).toHaveLength(2);
    expect(tracks[0]!.findAll(".task-bar")).toHaveLength(4);
    expect(tracks[1]!.findAll(".task-bar")).toHaveLength(0);
    expect(tracks[0]!.attributes("style")).toContain("min-height: 58px");
    const tops = tracks[0]!
      .findAll(".task-bar")
      .map((task) => task.attributes("style"));
    expect(tops[0]).toContain("top: 16px");
    expect(tops[1]).toContain("top: 21px");
    expect(tops[2]).toContain("top: 26px");
    expect(tops[3]).toContain("top: 31px");
  });

  it("clicking a task opens it without emitting a member expansion", async () => {
    const wrapper = mountFlow();
    await wrapper.find(".task-bar").trigger("click");
    expect(wrapper.emitted("open-task")).toHaveLength(1);
    expect(wrapper.emitted("toggle-member")).toBeUndefined();
  });

  it("clicking the member surface requests one-member expansion", async () => {
    const wrapper = mountFlow();
    await wrapper.find(".member-name").trigger("click");
    expect(wrapper.emitted("toggle-member")?.[0]).toEqual(["member-a"]);
  });

  it("clicking lane blank space toggles the member, while remaining controls do not", async () => {
    const wrapper = mountFlow({ expandedMemberId: "member-a" });
    await wrapper.find("[data-member-track='member-a'] .rail").trigger("click");
    expect(wrapper.emitted("toggle-member")?.[0]).toEqual(["member-a"]);

    const remainingWrapper = mountFlow({ expandedMemberId: "member-a" });
    await remainingWrapper.find(".remaining-toggle").trigger("click");
    expect(remainingWrapper.emitted("toggle-remaining")?.[0]).toEqual([
      "member-a",
    ]);
    expect(remainingWrapper.emitted("toggle-member")).toBeUndefined();
  });

  it("uses two recent rows plus a stacked third row before expanding all remaining", () => {
    const wrapper = mountFlow({
      expandedMemberId: "member-a",
      remainingExpandedMemberId: null,
    });
    const bars = wrapper.findAll("[data-member-track='member-a'] .task-bar");
    expect(bars[0]!.attributes("style")).toContain("top: 10px");
    expect(bars[1]!.attributes("style")).toContain("top: 54px");
    expect(bars[2]!.attributes("style")).toContain("top: 98px");
    expect(bars[3]!.attributes("style")).toContain("top: 103px");
    expect(wrapper.text()).toContain("展开剩余 2 个任务");
  });

  it("expands remaining tasks into individual DDL-ordered rows", () => {
    const wrapper = mountFlow({
      expandedMemberId: "member-a",
      remainingExpandedMemberId: "member-a",
    });
    const bars = wrapper.findAll("[data-member-track='member-a'] .task-bar");
    expect(bars[0]!.attributes("style")).toContain("top: 10px");
    expect(bars[1]!.attributes("style")).toContain("top: 54px");
    expect(bars[2]!.attributes("style")).toContain("top: 98px");
    expect(bars[3]!.attributes("style")).toContain("top: 136px");
    expect(wrapper.text()).toContain("收起剩余任务");
  });

  it("maps the approved task statuses to stable visual classes and tooltip text", () => {
    const statuses = [
      ["in_progress", "进行中"],
      ["awaiting_review", "待验收"],
      ["blocked", "阻塞"],
      ["completed", "已完成"],
      ["not_started", "未开始"],
      ["canceled", "已取消"],
    ] as const;
    const statusTasks: MemberFlowTask[] = statuses.map(
      ([status, statusLabel], index) => ({
        id: `status-${index}`,
        title: `状态任务 ${index}`,
        primaryUserId: "user-a",
        createdAt: "2026-10-01T00:00:00Z",
        acceptedAt: "2026-10-01T00:00:00Z",
        deadlineAt: `2026-10-${10 + index}T00:00:00Z`,
        status,
        statusLabel,
      }),
    );
    const wrapper = mountFlow({ tasks: statusTasks });
    const bars = wrapper.findAll("[data-member-track='member-a'] .task-bar");

    for (const [index, [status, statusLabel]] of statuses.entries()) {
      expect(bars[index]!.classes()).toContain(`is-${status}`);
      expect(bars[index]!.attributes("aria-label")).toContain(statusLabel);
      expect(bars[index]!.attributes("data-task-tooltip")).toContain(
        statusLabel,
      );
    }
  });

  it("exposes full task context to keyboard focus, including collaborator count", () => {
    const wrapper = mountFlow();
    const task = wrapper.find(".task-bar");
    expect(task.attributes("aria-label")).toContain("任务 1");
    expect(task.attributes("aria-label")).toContain("进行中");
    expect(task.attributes("aria-label")).toContain("2 名协作者");
  });
});
