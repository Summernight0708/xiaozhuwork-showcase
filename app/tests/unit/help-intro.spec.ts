import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import { createMemoryHistory, createRouter } from "vue-router";
import HelpIntroCard from "@/components/help/HelpIntroCard.vue";
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { name: "help-center", path: "/help", component: { template: "<div />" } },
    ...[
      "project-invitations",
      "project-tasks",
      "project-reviews",
      "project-todos",
      "project-contributions",
      "project-files",
      "project-members",
    ].map((name) => ({
      name,
      path: "/projects/:projectId/" + name,
      component: { template: "<div />" },
    })),
  ],
});
describe("role-aware help intro", () => {
  it("shows leader-specific checklist and fires dismiss without side-effects", async () => {
    const dismiss = vi.fn();
    const wrapper = mount(HelpIntroCard, {
      props: {
        role: "leader",
        memberCount: 1,
        taskCount: 0,
        projectId: "p1",
        archived: false,
        syncError: false,
        onDismiss: dismiss,
      },
      global: { plugins: [router] },
    });
    expect(wrapper.text()).toContain("组长入门");
    expect(wrapper.text()).toContain("邀请同学");
    await wrapper.get(".intro-dismiss").trigger("click");
    expect(dismiss).toHaveBeenCalledOnce();
  });
  it("keeps observers on read-only checklist", () => {
    const wrapper = mount(HelpIntroCard, {
      props: {
        role: "observer",
        memberCount: 3,
        taskCount: 2,
        projectId: "p1",
        archived: false,
        syncError: false,
      },
      global: { plugins: [router] },
    });
    expect(wrapper.text()).toContain("观察者入门");
    expect(wrapper.text()).not.toContain("邀请同学");
  });
});
