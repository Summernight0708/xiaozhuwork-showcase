import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import TaskListRow from "@/components/task/TaskListRow.vue";

function mountRow(overrides: Record<string, unknown> = {}) {
  return mount(TaskListRow, {
    props: {
      title: "数据分析",
      status: "in_progress",
      primaryName: "张三",
      collaboratorCount: 2,
      weight: 3,
      deadlineAt: "2026-10-06T12:00:00Z",
      alert: "需要修改",
      ...overrides,
    },
  });
}

describe("TaskListRow", () => {
  it("shows only the approved compact task facts and accessible difficulty label", () => {
    const wrapper = mountRow();
    const text = wrapper.text();

    expect(text).toContain("数据分析");
    expect(text).toContain("进行中");
    expect(text).toContain("张三 · 主负责");
    expect(text).toContain("+2 协作者");
    expect(text).toContain("需要修改");
    expect(wrapper.find('[aria-label="任务难度 3/5"]').exists()).toBe(true);
    expect(text).not.toContain("共同负责人");
  });

  it("shows current-user responsibility semantics without changing collaborator into Primary", () => {
    const primary = mountRow({ currentUserIsPrimary: true });
    expect(primary.text()).toContain("你 · 主负责");

    const collaborator = mountRow({
      primaryName: "张三",
      currentUserIsCollaborator: true,
      collaboratorCount: 0,
    });
    expect(collaborator.text()).toContain("张三 · 主负责");
    expect(collaborator.text()).toContain("你参与协作");
    expect(collaborator.text()).not.toContain("共同负责人");
  });

  it("hides selection checkbox until selection mode is activated", async () => {
    const wrapper = mountRow();
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
    expect(wrapper.classes()).not.toContain("selection-mode");

    await wrapper.setProps({ selectionMode: true, selected: true });
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(true);
    expect(wrapper.classes()).toContain("selection-mode");
    expect(wrapper.attributes("aria-selected")).toBe("true");
  });

  it("de-emphasizes completed tasks and emits open from the whole task action", async () => {
    const wrapper = mountRow({
      status: "completed",
      completed: true,
      alert: null,
    });
    expect(wrapper.classes()).toContain("completed");
    await wrapper.find(".task-main").trigger("click");
    expect(wrapper.emitted("open")).toHaveLength(1);
  });
});
