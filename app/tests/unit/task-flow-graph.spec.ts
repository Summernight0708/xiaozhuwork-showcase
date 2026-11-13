import { flushPromises, mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { beforeEach, describe, expect, it, vi } from "vitest";

import TaskFlowGraph from "@/components/TaskFlowGraph.vue";
import type {
  TaskGraphDependency,
  TaskGraphTask,
} from "@/domain/task-dependency-graph";

function task(
  id: string,
  status = "in_progress",
  assigneeId: string | null = "user-1",
): TaskGraphTask {
  return {
    id,
    title: `任务 ${id}`,
    status,
    assignee_id: assigneeId,
    assignment_state: "assigned",
    deadline_at: "2026-10-10T00:00:00.000Z",
  };
}

function dependency(upstream: string, downstream: string): TaskGraphDependency {
  return {
    upstream_task_id: upstream,
    downstream_task_id: downstream,
  };
}

const dependencies = [
  dependency("A", "B"),
  dependency("B", "C"),
  dependency("C", "D"),
];

function mountGraph(
  tasks: TaskGraphTask[] = [
    task("history", "completed"),
    task("A", "completed"),
    task("B"),
    task("C", "blocked"),
    task("D"),
  ],
) {
  return mount(TaskFlowGraph, {
    props: {
      tasks,
      dependencies,
      currentUserId: "user-1",
      memberName: (id: string | null | undefined) =>
        id === "user-2" ? "李四" : "张三",
      collaboratorCounts: { B: 2 },
      newArtifactTaskIds: ["B"],
    },
  });
}

describe("TaskFlowGraph v3", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders SVG dependencies, accessible nodes, and folds unrelated completed history", () => {
    const wrapper = mountGraph();

    expect(wrapper.find(".task-flow__edges").exists()).toBe(true);
    expect(wrapper.findAll(".task-flow__edges path").length).toBe(3);
    expect(wrapper.text()).toContain("更早已完成 · 1");

    const nodeB = wrapper.get('[data-task-id="B"]');
    expect(nodeB.attributes("aria-label")).toContain("任务 B");
    expect(nodeB.attributes("aria-label")).toContain("主负责人：我");
    expect(nodeB.attributes("aria-label")).toContain("2 名协作者");
    expect(nodeB.attributes("aria-label")).toContain("有新成果");
  });

  it("switches semantic content at the approved 82% and 58% thresholds", async () => {
    const wrapper = mountGraph();
    const range = wrapper.get('input[aria-label="缩放比例"]');

    await range.setValue("70");
    await nextTick();
    expect(wrapper.attributes("data-zoom-tier")).toBe("2");
    expect(
      wrapper.get('[data-task-id="B"]').find(".task-flow__node-owner").exists(),
    ).toBe(false);
    expect(
      wrapper
        .get('[data-task-id="B"]')
        .find(".task-flow__node-status")
        .exists(),
    ).toBe(true);

    await range.setValue("50");
    await nextTick();
    expect(wrapper.attributes("data-zoom-tier")).toBe("3");
    expect(
      wrapper
        .get('[data-task-id="B"]')
        .find(".task-flow__node-status")
        .exists(),
    ).toBe(false);
    expect(wrapper.get('[data-task-id="B"]').text()).toBe("任务 B");

    await range.setValue("82");
    await nextTick();
    expect(wrapper.attributes("data-zoom-tier")).toBe("1");
    expect(wrapper.get('[data-task-id="B"]').text()).toContain("主负责 我");
  });

  it("grows typography and cards together above 100%", async () => {
    const wrapper = mountGraph();
    const range = wrapper.get('input[aria-label="缩放比例"]');
    const node = wrapper.get('[data-task-id="B"]');

    const beforeWidth = Number.parseInt(
      node.attributes("style")?.match(/width:\s*(\d+)px/)?.[1] ?? "0",
    );
    const beforeFont = Number.parseFloat(
      node.attributes("style")?.match(/--node-title-size:\s*([\d.]+)px/)?.[1] ??
        "0",
    );

    await range.setValue("150");
    await nextTick();

    const after = wrapper.get('[data-task-id="B"]').attributes("style") ?? "";
    const afterWidth = Number.parseInt(
      after.match(/width:\s*(\d+)px/)?.[1] ?? "0",
    );
    const afterFont = Number.parseFloat(
      after.match(/--node-title-size:\s*([\d.]+)px/)?.[1] ?? "0",
    );
    expect(afterWidth).toBeGreaterThan(beforeWidth);
    expect(afterFont).toBeGreaterThan(beforeFont);
  });

  it("searches without deleting context and can clear the search", async () => {
    const wrapper = mountGraph();
    const input = wrapper.get('input[aria-label="搜索任务"]');

    await input.setValue("任务 B");
    await nextTick();
    expect(wrapper.findAll(".task-flow__node").length).toBe(4);
    expect(wrapper.get('[data-task-id="B"]').classes()).toContain(
      "is-search-match",
    );
    expect(wrapper.get('[data-task-id="C"]').classes()).toContain(
      "is-search-dimmed",
    );

    await input.setValue("");
    await nextTick();
    expect(wrapper.find(".is-search-dimmed").exists()).toBe(false);
  });

  it("focuses the clicked task and direct relations while still opening task detail", async () => {
    const wrapper = mountGraph([task("A"), task("B"), task("C"), task("D")]);

    await wrapper.get('[data-task-id="B"]').trigger("click");
    await flushPromises();

    const opened = wrapper.emitted("open-task") ?? [];
    expect(opened[opened.length - 1]).toEqual(["B"]);
    expect(wrapper.text()).toContain("聚焦：任务 B");
    expect(wrapper.findAll(".task-flow__node")).toHaveLength(3);
    expect(wrapper.find('[data-task-id="D"]').exists()).toBe(false);

    await wrapper.get(".focus-banner button").trigger("click");
    await nextTick();
    expect(wrapper.findAll(".task-flow__node")).toHaveLength(4);
  });

  it("expands folded history and switches scopes", async () => {
    const wrapper = mountGraph();

    await wrapper.get(".history-toggle").trigger("click");
    await nextTick();
    expect(wrapper.find('[data-task-id="history"]').exists()).toBe(true);

    await wrapper.get('select[aria-label="流程图范围"]').setValue("blocked");
    await nextTick();
    expect(wrapper.find('[data-task-id="C"]').exists()).toBe(true);
    expect(wrapper.find('[data-task-id="B"]').exists()).toBe(true);
    expect(wrapper.find('[data-task-id="history"]').exists()).toBe(false);
  });

  it("renders a compact dependency view from the same graph facts", () => {
    const wrapper = mountGraph([task("A"), task("B"), task("C"), task("D")]);
    const compact = wrapper.get(".task-flow__compact");

    expect(compact.findAll(".task-flow__compact-stage")).toHaveLength(4);
    expect(compact.get('[data-compact-task-id="B"]').text()).toContain(
      "任务 B",
    );
    expect(compact.get('[data-compact-task-id="B"]').text()).toContain(
      "上游 任务 A",
    );
    expect(compact.get('[data-compact-task-id="B"]').text()).toContain(
      "下游 任务 C",
    );
  });

  it("keeps long task names available in desktop and compact renderings", () => {
    const longTask = task("long");
    longTask.title =
      "这是一个非常非常长的任务名称用于验证流程图在窄屏与桌面布局中都不会因为标题长度而撑破容器";
    const wrapper = mountGraph([longTask]);

    expect(wrapper.get('[data-task-id="long"]').text()).toContain(
      "这是一个非常非常长的任务名称",
    );
    expect(wrapper.get('[data-compact-task-id="long"]').text()).toContain(
      "这是一个非常非常长的任务名称",
    );
  });

  it("provides best readable view, pan/zoom interaction and a desktop minimap", async () => {
    const many = Array.from({ length: 24 }, (_, index) =>
      task(String(index + 1)),
    );
    const wrapper = mountGraph(many);

    expect(wrapper.find(".task-flow__minimap").exists()).toBe(true);
    await wrapper.get(".best-view").trigger("click");
    expect(wrapper.attributes("data-zoom")).toBe("58");

    const canvas = wrapper.get(".task-flow__canvas");
    const before = Number(wrapper.attributes("data-zoom"));
    await canvas.trigger("wheel", { deltaY: -120 });
    await nextTick();
    expect(Number(wrapper.attributes("data-zoom"))).toBeGreaterThan(before);

    const panBefore = canvas.attributes("data-pan-x");
    await canvas.trigger("pointerdown", {
      pointerId: 1,
      clientX: 20,
      clientY: 20,
    });
    await canvas.trigger("pointermove", {
      pointerId: 1,
      clientX: 60,
      clientY: 35,
    });
    await canvas.trigger("pointerup", {
      pointerId: 1,
      clientX: 60,
      clientY: 35,
    });
    await nextTick();
    expect(canvas.attributes("data-pan-x")).not.toBe(panBefore);
  });

  it("shows a safe empty graph state", () => {
    const wrapper = mountGraph([]);
    expect(wrapper.text()).toContain("还没有任务");
    expect(wrapper.find(".task-flow__canvas").exists()).toBe(false);
  });
});
