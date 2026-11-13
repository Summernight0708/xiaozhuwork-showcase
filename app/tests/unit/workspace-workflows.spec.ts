import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { User } from "@supabase/supabase-js";
import { CommandTransportError } from "@/lib/command-adapter";

const mocks = vi.hoisted(() => {
  const commands = {
    reviewTaskSubmission: vi.fn(),
    submitTaskForReview: vi.fn(),
    confirmContributionReport: vi.fn(),
    updateProjectSettings: vi.fn(),
    setTaskDependencies: vi.fn(),
    proposeTaskChange: vi.fn(),
    respondToTaskChange: vi.fn(),
    correctTaskReviewRequestChanges: vi.fn(),
    requestTaskPrimaryHandoff: vi.fn(),
    respondTaskPrimaryHandoff: vi.fn(),
    cancelTaskPrimaryHandoff: vi.fn(),
    unassignTaskPrimary: vi.fn(),
  };
  const repository = {
    listTasks: vi.fn().mockResolvedValue([]),
    listTaskDependencies: vi.fn().mockResolvedValue([]),
    getProject: vi.fn(),
    getMembership: vi.fn(),
    getProjectEntitlement: vi.fn().mockResolvedValue({
      projectId: "project-1",
      plan: "free",
      state: "free",
      source: "none",
      graceExpiresAt: null,
    }),
    listMembers: vi.fn().mockResolvedValue([]),
    listAssignmentOffers: vi.fn().mockResolvedValue([]),
    listTaskCollaborators: vi.fn().mockResolvedValue([]),
    listTaskPrimaryHandoffs: vi.fn().mockResolvedValue([]),
    listTaskChangeProposals: vi.fn().mockResolvedValue([]),
    listReviews: vi.fn().mockResolvedValue([]),
    listReviewFiles: vi.fn().mockResolvedValue([]),
    getProjectContributionReport: vi.fn(),
    getContributionReport: vi.fn(),
    listContributionConfirmations: vi.fn().mockResolvedValue([]),
    exportContributionReport: vi.fn(),
  };
  return { commands, repository };
});

vi.mock("@/services/backend", () => ({
  getBackend: () => ({ commands: mocks.commands, client: {} }),
}));

vi.mock("@/services/repository", () => ({
  createRepository: () => mocks.repository,
}));

import { useWorkspaceStore } from "@/stores/workspace";
import { useAuthStore } from "@/stores/auth";
import type { ProjectRow, ReviewRoundRow, TaskRow } from "@/types/ui";

const task = {
  id: "task-1",
  project_id: "project-1",
  title: "Write report",
  description: null,
  deadline_at: "2026-10-10T00:00:00Z",
  weight: 3,
  assignment_state: "assigned",
  status: "in_progress",
  assignee_id: "user-1",
  accepted_at: "2026-09-30T00:00:00Z",
  progress_text: "",
  blocked_reason: null,
  created_by: "leader-1",
  created_at: "2026-09-30T00:00:00Z",
  updated_at: "2026-09-30T00:00:00Z",
  version: 3,
} as TaskRow;

function round(id: string, number: number, version: number): ReviewRoundRow {
  return {
    id,
    project_id: "project-1",
    task_id: "task-1",
    round_number: number,
    state: "pending",
    decision: null,
    rejection_reason: null,
    submitted_by: "user-1",
    submitted_file_version_id: "version-1",
    submission_text_snapshot: null,
    required_submission_file_type_snapshot: null,
    required_submission_file_types_snapshot: [],
    correction_of_review_round_id: null,
    delegation_required: false,
    delegated_reviewer_id: null,
    submitted_at: "2026-09-30T01:00:00Z",
    reviewed_by: null,
    reviewed_at: null,
    created_at: "2026-09-30T01:00:00Z",
    updated_at: "2026-09-30T01:00:00Z",
    version,
  };
}

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

describe("workspace project context isolation", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mocks.repository.listMembers.mockResolvedValue([]);
    mocks.repository.listTasks.mockResolvedValue([]);
    mocks.repository.listTaskDependencies.mockResolvedValue([]);
    mocks.repository.listAssignmentOffers.mockResolvedValue([]);
    mocks.repository.listTaskCollaborators.mockResolvedValue([]);
    mocks.repository.listTaskPrimaryHandoffs.mockResolvedValue([]);
    mocks.repository.listTaskChangeProposals.mockResolvedValue([]);
  });

  it("reacts to the project setting without disabling existing member work", async () => {
    useAuthStore().$patch({ user: authUser("user-1") });
    mocks.repository.getProject.mockResolvedValue({
      id: "project-1",
      allow_member_task_creation: true,
    });
    mocks.repository.getMembership.mockResolvedValue({
      id: "membership-1",
      role: "member",
      is_observer: false,
    });
    const workspace = useWorkspaceStore();
    await workspace.loadBase("project-1");
    expect(workspace.capabilities.canCreateTask).toBe(true);
    workspace.project!.allow_member_task_creation = false;
    expect(workspace.capabilities.canCreateTask).toBe(false);
    expect(workspace.capabilities.canUploadFile).toBe(true);
    expect(workspace.capabilities.canReviewSubmission).toBe(true);
    workspace.membership!.role = "admin";
    expect(workspace.capabilities.canCreateTask).toBe(true);
    expect(workspace.capabilities.canUpdateProjectSettings).toBe(false);
  });

  it("loads the authoritative entitlement with the project context", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-1") });
    mocks.repository.getProject.mockResolvedValue({ id: "project-1" });
    mocks.repository.getMembership.mockResolvedValue({
      id: "membership-1",
      project_id: "project-1",
    });
    mocks.repository.getProjectEntitlement.mockResolvedValue({
      projectId: "project-1",
      plan: "pro",
      state: "active",
      source: "account_member",
      graceExpiresAt: null,
    });

    const workspace = useWorkspaceStore();
    await workspace.loadBase("project-1");

    expect(mocks.repository.getProjectEntitlement).toHaveBeenCalledWith(
      "project-1",
    );
    expect(workspace.entitlement?.plan).toBe("pro");
  });

  it("does not let a slower previous-project load overwrite the active project", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-1") });
    const slowA = deferred<{ id: string }>();
    mocks.repository.getProject.mockImplementation((projectId: string) =>
      projectId === "project-a"
        ? slowA.promise
        : Promise.resolve({ id: "project-b" }),
    );
    mocks.repository.getMembership.mockImplementation((projectId: string) =>
      Promise.resolve({ id: `membership-${projectId}`, project_id: projectId }),
    );

    const workspace = useWorkspaceStore();
    const loadingA = workspace.loadBase("project-a");
    const loadingB = workspace.loadBase("project-b");
    await loadingB;

    expect(workspace.projectId).toBe("project-b");
    expect(workspace.project?.id).toBe("project-b");

    slowA.resolve({ id: "project-a" });
    await loadingA;

    expect(workspace.projectId).toBe("project-b");
    expect(workspace.project?.id).toBe("project-b");
  });

  it("does not let a slower task refresh from the previous project overwrite the active project", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-1") });
    mocks.repository.getProject.mockImplementation((projectId: string) =>
      Promise.resolve({ id: projectId }),
    );
    mocks.repository.getMembership.mockImplementation((projectId: string) =>
      Promise.resolve({ id: `membership-${projectId}`, project_id: projectId }),
    );

    const workspace = useWorkspaceStore();
    await workspace.loadBase("project-a");

    const slowTasks = deferred<TaskRow[]>();
    mocks.repository.listTasks
      .mockReturnValueOnce(slowTasks.promise)
      .mockResolvedValueOnce([
        { ...task, id: "task-b", project_id: "project-b" },
      ]);
    const refreshingA = workspace.refreshTasks();
    await workspace.loadBase("project-b");

    expect(workspace.tasks[0]?.id).toBe("task-b");

    slowTasks.resolve([{ ...task, id: "task-a", project_id: "project-a" }]);
    await refreshingA;

    expect(workspace.projectId).toBe("project-b");
    expect(workspace.tasks[0]?.id).toBe("task-b");
  });

  it("does not reuse a previous user's project cache for the same route", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-a") });
    mocks.repository.getProject
      .mockResolvedValueOnce({ id: "project-1" })
      .mockResolvedValueOnce(null);
    mocks.repository.getMembership
      .mockResolvedValueOnce({ id: "membership-a", project_id: "project-1" })
      .mockResolvedValueOnce(null);

    const workspace = useWorkspaceStore();
    await workspace.loadBase("project-1");
    expect(workspace.project?.id).toBe("project-1");

    auth.$patch({ user: authUser("user-b") });
    await workspace.loadBase("project-1");

    expect(mocks.repository.getProject).toHaveBeenCalledTimes(2);
    expect(workspace.project).toBeNull();
    expect(workspace.membership).toBeNull();
  });
});

describe("workspace command context stability", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mocks.repository.listMembers.mockResolvedValue([]);
    mocks.repository.listTasks.mockResolvedValue([]);
    mocks.repository.listTaskDependencies.mockResolvedValue([]);
    mocks.repository.listAssignmentOffers.mockResolvedValue([]);
    mocks.repository.listTaskCollaborators.mockResolvedValue([]);
    mocks.repository.listTaskPrimaryHandoffs.mockResolvedValue([]);
    mocks.repository.listTaskChangeProposals.mockResolvedValue([]);
  });

  it("retries a logical project command with the same project and version payload", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-1") });
    mocks.repository.getProject.mockResolvedValue({
      id: "project-a",
      version: 3,
    } as unknown as ProjectRow);
    mocks.repository.getMembership.mockResolvedValue({
      id: "membership-a",
      project_id: "project-a",
    });

    const workspace = useWorkspaceStore();
    await workspace.loadBase("project-a");

    mocks.commands.updateProjectSettings
      .mockImplementationOnce((input: { requestId: string }) => {
        workspace.$patch({
          projectId: "project-b",
          project: { id: "project-b", version: 9 } as unknown as ProjectRow,
        });
        throw new CommandTransportError(input.requestId, true);
      })
      .mockResolvedValueOnce({
        ok: true,
        data: { projectId: "project-a", projectVersion: 4, changed: true },
        requestId: "request-retry",
        replayed: true,
        aggregateType: "project",
        aggregateId: "project-a",
        aggregateVersion: 4,
      });

    await workspace.updateProjectSettings({
      name: "Project A",
      deadlineAt: "2026-12-31T00:00:00Z",
      timezone: "Asia/Tokyo",
      contributionMode: "weighted",
      allowMemberTaskCreation: false,
      autoPenaltyEnabled: false,
      requireRealName: false,
      requireStudentNumber: false,
    });

    expect(mocks.commands.updateProjectSettings).toHaveBeenCalledTimes(2);
    const first = mocks.commands.updateProjectSettings.mock.calls[0]?.[0];
    const second = mocks.commands.updateProjectSettings.mock.calls[1]?.[0];
    expect(first).toMatchObject({
      projectId: "project-a",
      expectedVersion: 3,
      allowMemberTaskCreation: false,
    });
    expect(second).toMatchObject({
      projectId: "project-a",
      expectedVersion: 3,
      allowMemberTaskCreation: false,
    });
    expect(second.requestId).toBe(first.requestId);
    expect(workspace.projectId).toBe("project-b");
  });
});

describe("workspace authoritative workflows", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mocks.repository.listTasks.mockResolvedValue([]);
    mocks.repository.listTaskDependencies.mockResolvedValue([]);
    mocks.repository.listAssignmentOffers.mockResolvedValue([]);
    mocks.repository.listTaskCollaborators.mockResolvedValue([]);
    mocks.repository.listTaskPrimaryHandoffs.mockResolvedValue([]);
    mocks.repository.listTaskChangeProposals.mockResolvedValue([]);
    mocks.repository.listReviews.mockResolvedValue([]);
    mocks.repository.listContributionConfirmations.mockResolvedValue([]);
  });

  it("loads dependency facts and writes replacements through the command adapter", async () => {
    const auth = useAuthStore();
    auth.$patch({ user: authUser("user-1") });
    mocks.repository.getProject.mockResolvedValue({
      id: "project-1",
      version: 2,
    } as unknown as ProjectRow);
    mocks.repository.getMembership.mockResolvedValue({
      id: "membership-1",
      project_id: "project-1",
      role: "leader",
      member_state: "active",
      is_observer: false,
    });
    mocks.repository.listMembers.mockResolvedValue([]);
    mocks.repository.listTasks.mockResolvedValue([
      { ...task, id: "task-a", status: "in_progress" },
      { ...task, id: "task-b", version: 3 },
    ]);
    mocks.repository.listTaskDependencies.mockResolvedValue([
      {
        project_id: "project-1",
        upstream_task_id: "task-a",
        downstream_task_id: "task-b",
        created_by: "user-1",
        created_at: "2026-09-30T00:00:00Z",
      },
    ]);
    mocks.commands.setTaskDependencies.mockResolvedValue({
      ok: true,
      data: {
        taskId: "task-b",
        taskVersion: 4,
        changed: true,
        upstreamTaskIds: [],
      },
      requestId: "dependency-request",
      replayed: false,
      aggregateType: "task",
      aggregateId: "task-b",
      aggregateVersion: 4,
    });

    const workspace = useWorkspaceStore();
    await workspace.loadBase("project-1");

    expect(workspace.dependencyState("task-b").blocked).toBe(true);
    expect(workspace.upstreamTasks("task-b").map((item) => item.id)).toEqual([
      "task-a",
    ]);
    const downstream = workspace.findTask("task-b");
    expect(downstream).not.toBeNull();
    const result = await workspace.setTaskDependencies(downstream!, []);
    expect(result.ok).toBe(true);
    expect(mocks.commands.setTaskDependencies).toHaveBeenCalledWith(
      expect.objectContaining({
        projectId: "project-1",
        downstreamTaskId: "task-b",
        upstreamTaskIds: [],
        expectedVersion: 3,
      }),
    );
  });

  it("supports request-changes, resubmit, then approve through command RPCs", async () => {
    mocks.commands.correctTaskReviewRequestChanges.mockReset();

    mocks.commands.reviewTaskSubmission
      .mockResolvedValueOnce({
        ok: true,
        data: {
          taskId: "task-1",
          reviewRoundId: "round-1",
          outcome: "request_changes",
          taskStatus: "in_progress",
          reviewedAt: "2026-09-30T02:00:00Z",
          rejectionReason: "Add evidence",
        },
        requestId: "request-a",
        replayed: false,
        aggregateType: "task_review_round",
        aggregateId: "round-1",
        aggregateVersion: 2,
      })
      .mockResolvedValueOnce({
        ok: true,
        data: {
          taskId: "task-1",
          reviewRoundId: "round-2",
          outcome: "approve",
          taskStatus: "completed",
          reviewedAt: "2026-09-30T04:00:00Z",
        },
        requestId: "request-c",
        replayed: false,
        aggregateType: "task_review_round",
        aggregateId: "round-2",
        aggregateVersion: 2,
      });
    mocks.commands.submitTaskForReview.mockResolvedValue({
      ok: true,
      data: {
        taskId: "task-1",
        reviewRoundId: "round-2",
        roundNumber: 2,
        submittedAt: "2026-09-30T03:00:00Z",
      },
      requestId: "request-b",
      replayed: false,
      aggregateType: "task",
      aggregateId: "task-1",
      aggregateVersion: 4,
    });

    const workspace = useWorkspaceStore();
    const firstRound = round("round-1", 1, 1);
    const secondRound = round("round-2", 2, 1);

    const requested = await workspace.reviewSubmission(
      task,
      firstRound,
      "request_changes",
      "Add evidence",
    );
    expect(requested.ok).toBe(true);
    expect(mocks.commands.reviewTaskSubmission).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        projectId: "project-1",
        taskId: "task-1",
        reviewRoundId: "round-1",
        expectedVersion: 1,
        action: "request_changes",
        rejectionReason: "Add evidence",
      }),
    );

    const resubmitted = await workspace.submitReview(
      { ...task, version: 4 },
      { submissionText: "Updated evidence", fileVersionIds: ["version-2"] },
    );
    expect(resubmitted.ok).toBe(true);
    expect(mocks.commands.submitTaskForReview).toHaveBeenCalledWith(
      expect.objectContaining({
        submissionText: "Updated evidence",
        fileVersionIds: ["version-2"],
        expectedVersion: 4,
      }),
    );

    const approved = await workspace.reviewSubmission(
      { ...task, version: 5 },
      secondRound,
      "approve",
    );
    expect(approved.ok).toBe(true);
    expect(mocks.commands.reviewTaskSubmission).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        reviewRoundId: "round-2",
        action: "approve",
        expectedVersion: 1,
      }),
    );
  });

  it("opens an append-only review correction with both optimistic versions", async () => {
    mocks.commands.correctTaskReviewRequestChanges.mockResolvedValue({
      ok: true,
      data: {
        taskId: "task-1",
        sourceReviewRoundId: "round-1",
        reviewRoundId: "round-2",
        roundNumber: 2,
        taskVersion: 4,
        reviewRoundVersion: 1,
      },
      requestId: "request-correction",
      replayed: false,
      aggregateType: "task_review_round",
      aggregateId: "round-2",
      aggregateVersion: 1,
    });

    const workspace = useWorkspaceStore();
    const source = {
      ...round("round-1", 1, 2),
      state: "rejected",
      decision: "request_changes",
    };
    const result = await workspace.correctReviewRequestChanges(task, source);

    expect(result.ok).toBe(true);
    expect(mocks.commands.correctTaskReviewRequestChanges).toHaveBeenCalledWith(
      expect.objectContaining({
        projectId: "project-1",
        taskId: "task-1",
        reviewRoundId: "round-1",
        expectedTaskVersion: 3,
        expectedReviewVersion: 2,
      }),
    );
  });

  it("passes task and handoff versions through primary responsibility commands", async () => {
    const handoff = {
      id: "handoff-1",
      project_id: "project-1",
      task_id: "task-1",
      version: 2,
    };
    const success = {
      ok: true,
      data: {
        taskId: "task-1",
        handoffId: "handoff-1",
        fromUserId: "user-1",
        toUserId: "user-2",
        state: "pending",
        handoffVersion: 2,
        taskVersion: 3,
      },
      requestId: "request-handoff",
      replayed: false,
      aggregateType: "task_primary_handoff",
      aggregateId: "handoff-1",
      aggregateVersion: 2,
    };
    mocks.commands.requestTaskPrimaryHandoff.mockResolvedValue(success);
    mocks.commands.respondTaskPrimaryHandoff.mockResolvedValue({
      ...success,
      data: { ...success.data, state: "accepted" },
    });
    mocks.commands.cancelTaskPrimaryHandoff.mockResolvedValue({
      ...success,
      data: { ...success.data, state: "canceled" },
    });
    mocks.commands.unassignTaskPrimary.mockResolvedValue({
      ok: true,
      data: {
        taskId: "task-1",
        taskVersion: 4,
        assignmentState: "claimable",
      },
      requestId: "request-unassign",
      replayed: false,
      aggregateType: "task",
      aggregateId: "task-1",
      aggregateVersion: 4,
    });

    const workspace = useWorkspaceStore();
    await workspace.requestTaskPrimaryHandoff(task, "user-2");
    await workspace.respondTaskPrimaryHandoff(task, handoff as never, "accept");
    await workspace.cancelTaskPrimaryHandoff(task, handoff as never);
    await workspace.unassignTaskPrimary(task);

    expect(mocks.commands.requestTaskPrimaryHandoff).toHaveBeenCalledWith(
      expect.objectContaining({
        expectedTaskVersion: 3,
        targetUserId: "user-2",
      }),
    );
    expect(mocks.commands.respondTaskPrimaryHandoff).toHaveBeenCalledWith(
      expect.objectContaining({
        expectedTaskVersion: 3,
        expectedHandoffVersion: 2,
        action: "accept",
      }),
    );
    expect(mocks.commands.cancelTaskPrimaryHandoff).toHaveBeenCalledWith(
      expect.objectContaining({
        expectedTaskVersion: 3,
        expectedHandoffVersion: 2,
      }),
    );
    expect(mocks.commands.unassignTaskPrimary).toHaveBeenCalledWith(
      expect.objectContaining({ expectedTaskVersion: 3 }),
    );
  });

  it("confirms a contribution report and exports the formal authoritative snapshot", async () => {
    const workspace = useWorkspaceStore();
    workspace.$patch({
      projectId: "project-1",
      contributionReport: {
        projectId: "project-1",
        reportId: "report-1",
        state: "draft",
        contributionMode: "weighted",
        version: 2,
        eligibleCount: 3,
        confirmedCount: 1,
        requiredCount: 2,
        items: [],
      },
    });

    mocks.commands.confirmContributionReport.mockResolvedValue({
      ok: true,
      data: {
        projectId: "project-1",
        reportId: "report-1",
        state: "formal",
        confirmedCount: 2,
        eligibleCount: 3,
        requiredCount: 2,
        formalized: true,
      },
      requestId: "request-d",
      replayed: false,
      aggregateType: "contribution_report",
      aggregateId: "report-1",
      aggregateVersion: 3,
    });
    mocks.repository.getContributionReport.mockResolvedValue({
      projectId: "project-1",
      reportId: "report-1",
      state: "formal",
      contributionMode: "weighted",
      version: 3,
      eligibleCount: 3,
      confirmedCount: 2,
      requiredCount: 2,
      items: [],
    });
    const exported = new Blob(["csv"], { type: "text/csv" });
    mocks.repository.exportContributionReport.mockResolvedValue(exported);

    const result = await workspace.confirmContributionReport();
    expect(result.ok).toBe(true);
    expect(mocks.commands.confirmContributionReport).toHaveBeenCalledWith(
      expect.objectContaining({
        projectId: "project-1",
        reportId: "report-1",
        expectedVersion: 2,
      }),
    );

    const blob = await workspace.exportReport("csv");
    expect(blob).toBe(exported);
    expect(mocks.repository.exportContributionReport).toHaveBeenCalledWith(
      "report-1",
      "csv",
    );
  });
});
