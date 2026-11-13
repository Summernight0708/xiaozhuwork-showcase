import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import TaskExpectedShareConsent from "@/components/contributions/TaskExpectedShareConsent.vue";

describe("task expected-share consent", () => {
  const props = {
    projectId: "project-1",
    taskId: "task-1",
    taskVersion: 1,
    acceptedAt: null,
    taskWeight: 4,
    deadlineAt: "2026-10-30T08:00:00Z",
    canConsent: true,
    autoPenaltyEnabled: true,
    userId: null,
  };

  it("supports browser number input without string trim failure and computes four-decimal score", async () => {
    const wrapper = mount(TaskExpectedShareConsent, { props });
    await wrapper.get('input[type="number"]').setValue("100");
    expect(wrapper.text()).toContain("预期贡献基数：4.0000");
    await wrapper.get('input[type="number"]').setValue("65");
    expect(wrapper.text()).toContain("预期贡献基数：2.6000");
  });

  it("does not accept fractional basis points or unsigned consent", async () => {
    const wrapper = mount(TaskExpectedShareConsent, { props });
    await wrapper.get('input[type="number"]').setValue("65.001");
    await wrapper.get('input[type="checkbox"]').setValue(true);
    expect(wrapper.get("button").attributes("disabled")).toBeDefined();
  });
});
