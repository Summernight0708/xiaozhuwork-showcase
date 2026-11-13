import type { User } from "@supabase/supabase-js";
import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  listProjectSummaries: vi.fn(),
  createProject: vi.fn(),
}));

vi.mock("@/services/backend", () => ({
  getBackend: () => ({
    commands: { createProject: mocks.createProject },
    client: {},
  }),
}));

vi.mock("@/services/repository", () => ({
  createRepository: () => ({
    listProjectSummaries: mocks.listProjectSummaries,
  }),
}));

import { useAuthStore } from "@/stores/auth";
import { useProjectsStore } from "@/stores/projects";

function authUser(id: string) {
  return { id } as unknown as User;
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

describe("projects store account isolation", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mocks.listProjectSummaries.mockReset();
    mocks.createProject.mockReset();
  });

  it("reloads project summaries when the authenticated user changes", async () => {
    mocks.listProjectSummaries
      .mockResolvedValueOnce([{ project: { id: "project-a" } }])
      .mockResolvedValueOnce([{ project: { id: "project-b" } }]);

    const auth = useAuthStore();
    const projects = useProjectsStore();

    auth.$patch({ user: authUser("user-a") });
    await projects.load();
    expect(projects.items[0]?.project.id).toBe("project-a");

    auth.$patch({ user: authUser("user-b") });
    await projects.load();

    expect(mocks.listProjectSummaries).toHaveBeenCalledTimes(2);
    expect(projects.items[0]?.project.id).toBe("project-b");
  });

  it("forwards project identity requirements to the authoritative create command", async () => {
    mocks.createProject.mockResolvedValue({
      ok: true,
      data: {
        projectId: "project-1",
        leaderMembershipId: "membership-1",
      },
      requestId: "request-1",
      replayed: false,
      aggregateType: "project",
      aggregateId: "project-1",
      aggregateVersion: 1,
    });
    mocks.listProjectSummaries.mockResolvedValue([]);

    const auth = useAuthStore();
    const projects = useProjectsStore();
    auth.$patch({ user: authUser("user-a") });

    await projects.createProject({
      name: "课程设计",
      startAt: "2026-10-10T00:00:00.000Z",
      deadlineAt: "2026-10-20T00:00:00.000Z",
      timezone: "Asia/Shanghai",
      requireRealName: true,
      requireStudentNumber: true,
      allowMemberTaskCreation: false,
      contributionMode: "facts_only",
    });

    expect(mocks.createProject).toHaveBeenCalledWith(
      expect.objectContaining({
        name: "课程设计",
        startAt: "2026-10-10T00:00:00.000Z",
        deadlineAt: "2026-10-20T00:00:00.000Z",
        requireRealName: true,
        requireStudentNumber: true,
        allowMemberTaskCreation: false,
        contributionMode: "facts_only",
      }),
    );
  });

  it("does not let a slower previous-user load overwrite the current user", async () => {
    const slowA = deferred<Array<{ project: { id: string } }>>();
    mocks.listProjectSummaries
      .mockReturnValueOnce(slowA.promise)
      .mockResolvedValueOnce([{ project: { id: "project-b" } }]);

    const auth = useAuthStore();
    const projects = useProjectsStore();

    auth.$patch({ user: authUser("user-a") });
    const loadingA = projects.load();
    auth.$patch({ user: authUser("user-b") });
    const loadingB = projects.load();
    await loadingB;

    expect(projects.items[0]?.project.id).toBe("project-b");

    slowA.resolve([{ project: { id: "project-a" } }]);
    await loadingA;

    expect(projects.items[0]?.project.id).toBe("project-b");
  });
});
