import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import TaskFilters from "@/components/task/TaskFilters.vue";

const props = {
  members: [],
  selectionMode: false,
  search: "",
  status: "all" as const,
  assignee: "all",
  mine: false,
};

describe("mobile task filter disclosure", () => {
  it("defaults to an accessible collapsed secondary filter group", async () => {
    const wrapper = mount(TaskFilters, { props });
    const toggle = wrapper.get(".task-more-toggle");
    expect(toggle.attributes("aria-expanded")).toBe("false");
    expect(toggle.attributes("aria-controls")).toBe("task-extra-filters");
    expect(wrapper.find("#task-extra-filters").exists()).toBe(true);
    await toggle.trigger("click");
    expect(toggle.attributes("aria-expanded")).toBe("true");
    expect(wrapper.find(".filters-open").exists()).toBe(true);
  });

  it("preserves explicit multiselect and correctly reports active filters", async () => {
    const wrapper = mount(TaskFilters, {
      props: { ...props, mine: true, selectionMode: true },
    });
    expect(wrapper.get(".task-more-toggle").text()).toContain("已启用");
    await wrapper.get(".selection-toggle").trigger("click");
    expect(wrapper.emitted("toggleSelectionMode")).toHaveLength(1);
  });
});
