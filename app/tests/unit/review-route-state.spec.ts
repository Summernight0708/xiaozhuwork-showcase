import { flushPromises, mount } from "@vue/test-utils";
import { createMemoryHistory, createRouter } from "vue-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  reviews: [] as Array<Record<string, unknown>>,
  loadReviews: vi.fn().mockResolvedValue(undefined),
  loadTaskFiles: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("@/composables/useWorkspaceRoute", () => ({
  useWorkspaceRoute: () => ({
    reload: vi.fn(),
    workspace: {
      loading: false,
      error: null,
      project: { id: "project-1" },
      membership: { id: "membership-1" },
      role: "leader",
      currentUserId: "leader-1",
      get reviews() {
        return mocks.reviews;
      },
      taskFiles: {},
      findTask: (taskId: string) => ({
        id: taskId,
        title: `Task ${taskId}`,
        deadline_at: "2026-10-10T00:00:00Z",
        weight: 2,
        created_by: "member-1",
      }),
      memberName: (userId: string) => userId,
      downstreamTasks: () => [],
      loadReviews: mocks.loadReviews,
      loadTaskFiles: mocks.loadTaskFiles,
      reviewSubmission: vi.fn(),
      actionError: null,
      pendingAction: null,
    },
  }),
}));

import ProjectReviewsView from "@/views/ProjectReviewsView.vue";

function round(id: string, number: number, state = "pending") {
  return {
    id,
    project_id: "project-1",
    task_id: `task-${number}`,
    round_number: number,
    state,
    decision: state === "pending" ? null : "approve",
    rejection_reason: null,
    submitted_by: "member-1",
    submitted_file_version_id: `version-${number}`,
    submitted_at: "2026-09-30T01:00:00Z",
    reviewed_by: state === "pending" ? null : "leader-1",
    reviewed_at: state === "pending" ? null : "2026-09-30T02:00:00Z",
    version: 1,
  };
}

async function mountAt(path: string) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: "/projects/:projectId/reviews",
        name: "project-reviews",
        component: { template: "<div />" },
      },
      {
        path: "/projects/:projectId/reviews/:reviewRoundId",
        name: "review-detail",
        component: { template: "<div />" },
      },
    ],
  });
  await router.push(path);
  await router.isReady();
  const wrapper = mount(ProjectReviewsView, {
    global: {
      plugins: [router],
      stubs: {
        PageState: { template: "<div><slot /></div>" },
        StatusBadge: { template: "<span />" },
        VanButton: { template: "<button><slot /></button>" },
        VanField: { template: "<textarea />" },
      },
    },
  });
  await flushPromises();
  return { router, wrapper };
}

describe("review route state", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.reviews = [round("round-1", 1), round("round-2", 2, "completed")];
  });

  it("honors a completed review-round deep link even when the default tab would hide it", async () => {
    const { wrapper } = await mountAt("/projects/project-1/reviews/round-2");
    expect(wrapper.get(".review-detail").text()).toContain("第 2 轮验收");
  });

  it("follows browser navigation between review detail URLs", async () => {
    mocks.reviews = [round("round-1", 1), round("round-2", 2)];
    const { router, wrapper } = await mountAt(
      "/projects/project-1/reviews/round-1",
    );

    await router.push("/projects/project-1/reviews/round-2");
    await flushPromises();

    expect(wrapper.get(".review-detail").text()).toContain("第 2 轮验收");
  });

  it("updates the stable detail URL when selecting a review round", async () => {
    mocks.reviews = [round("round-1", 1), round("round-2", 2)];
    const { router, wrapper } = await mountAt("/projects/project-1/reviews");
    const buttons = wrapper.findAll(".review-list button");
    await buttons[1]!.trigger("click");
    await flushPromises();
    expect(router.currentRoute.value.params.reviewRoundId).toBe("round-2");
  });
});
