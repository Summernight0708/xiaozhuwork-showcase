import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import TaskStars from "@/components/common/TaskStars.vue";

describe("TaskStars", () => {
  it("exposes the frozen difficulty meaning to assistive technology", () => {
    const wrapper = mount(TaskStars, { props: { value: 3 } });

    expect(wrapper.text()).toBe("★★★☆☆");
    expect(wrapper.get("[role='img']").attributes("aria-label")).toBe(
      "任务难度 3/5",
    );
  });

  it("clamps display values into the 1–5 task-weight range", () => {
    expect(
      mount(TaskStars, { props: { value: 9 } })
        .get("[role='img']")
        .attributes("aria-label"),
    ).toBe("任务难度 5/5");
  });
});
