import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import UnclaimedTasksSection from "@/components/task/UnclaimedTasksSection.vue";
import type { TaskRow } from "@/types/ui";

function candidate(index: number, blocked = false) {
  const task = {
    id: `task-${index}`,
    project_id: "project-1",
    title: `待认领 ${index}`,
    deadline_at: `2026-10-${String(10 + index).padStart(2, "0")}T00:00:00Z`,
    weight: index % 5 || 5,
    assignment_state: "claimable",
    status: "not_started",
    assignee_id: null,
  } as TaskRow;
  return {
    task,
    dependency: {
      blocked,
      upstreamCount: blocked ? 1 : 0,
      incompleteUpstreamCount: blocked ? 1 : 0,
      effectiveStartAt: null,
    },
  };
}

describe("UnclaimedTasksSection", () => {
  it("appears only with candidates and caps the default list at five", () => {
    const empty = mount(UnclaimedTasksSection, {
      props: { candidates: [], canClaim: true },
    });
    expect(empty.find("section").exists()).toBe(false);

    const wrapper = mount(UnclaimedTasksSection, {
      props: {
        candidates: Array.from({ length: 7 }, (_, index) => candidate(index)),
        canClaim: true,
      },
    });
    expect(wrapper.findAll(".unclaimed-grid article")).toHaveLength(5);
    expect(wrapper.text()).toContain("查看全部 7 个");
  });

  it("does not offer claim to an observer/read-only consumer", () => {
    const wrapper = mount(UnclaimedTasksSection, {
      props: { candidates: [candidate(1)], canClaim: false },
    });
    expect(
      wrapper.findAll("button").some((button) => button.text() === "认领"),
    ).toBe(false);
  });

  it("still allows claiming a waiting-upstream task when backend authority allows claim", async () => {
    const wrapper = mount(UnclaimedTasksSection, {
      props: { candidates: [candidate(1, true)], canClaim: true },
    });
    expect(wrapper.text()).toContain("等待上游");
    const claim = wrapper
      .findAll("button")
      .find((button) => button.text() === "认领");
    expect(claim).toBeDefined();
    expect(claim!.attributes("disabled")).toBeUndefined();
    await claim!.trigger("click");
    expect(wrapper.emitted("claim")?.[0]).toEqual(["task-1"]);
  });

  it("switches to the full unclaimed filter through its single view-all event", async () => {
    const wrapper = mount(UnclaimedTasksSection, {
      props: {
        candidates: Array.from({ length: 6 }, (_, index) => candidate(index)),
        canClaim: true,
      },
    });
    const viewAll = wrapper
      .findAll("button")
      .find((button) => button.text().includes("查看全部"));
    await viewAll!.trigger("click");
    expect(wrapper.emitted("viewAll")).toHaveLength(1);
  });
});
