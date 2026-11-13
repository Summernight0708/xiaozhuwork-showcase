import { describe, expect, it, vi } from "vitest";

import {
  CommandTransportError,
  createCommandAdapter,
  newRequestId,
  type RpcPort,
} from "@/lib/command-adapter";

function createRpcPort(
  data: unknown,
  error: unknown = null,
): { port: RpcPort; rpc: ReturnType<typeof vi.fn> } {
  const rpc = vi.fn().mockResolvedValue({ data, error });
  return { port: { rpc }, rpc };
}

const successEnvelope = {
  ok: true,
  requestId: "request-1",
  replayed: false,
  aggregateType: "project",
  aggregateId: "project-1",
  aggregateVersion: 1,
};

describe("command adapter", () => {
  it("forwards disabled member creation and facts-only mode without replacing false with defaults", async () => {
    const { port, rpc } = createRpcPort({
      ...successEnvelope,
      data: { projectId: "project-1", leaderMembershipId: "member-1" },
    });
    await createCommandAdapter(port).createProject({
      requestId: "request-1",
      expectedVersion: 0,
      name: "Project",
      deadlineAt: "2099-01-01T00:00:00Z",
      allowMemberTaskCreation: false,
      contributionMode: "facts_only",
    });
    expect(rpc).toHaveBeenCalledWith(
      "cmd_create_project",
      expect.objectContaining({
        p_allow_member_task_creation: false,
        p_contribution_mode: "facts_only",
      }),
    );
  });

  it("forwards requiresReview=false rather than silently defaulting to true", async () => {
    const { port, rpc } = createRpcPort({
      ...successEnvelope,
      data: { taskId: "task-1", taskVersion: 1 },
    });
    await createCommandAdapter(port).createTask({
      projectId: "project-1",
      requestId: "request-1",
      expectedVersion: 2,
      title: "Research",
      deadlineAt: "2099-01-01T00:00:00Z",
      assignmentMode: "claimable",
      requiresReview: false,
    });
    expect(rpc).toHaveBeenCalledWith(
      "cmd_create_task_v2",
      expect.objectContaining({
        p_requires_review: false,
        p_required_submission_file_types: [],
      }),
    );
  });

  it("keeps RPC names and argument types correlated", () => {
    const assertRpcArgumentCorrelation = (port: RpcPort) => {
      // @ts-expect-error preview args must not be accepted for cmd_create_project
      void port.rpc("cmd_create_project", { p_token: "invite-token" });
    };

    expect(assertRpcArgumentCorrelation).toBeTypeOf("function");
  });

  it("maps dependency replacement to the authoritative RPC", async () => {
    const { port, rpc } = createRpcPort({
      ...successEnvelope,
      aggregateType: "task",
      aggregateId: "task-b",
      aggregateVersion: 4,
      data: {
        taskId: "task-b",
        taskVersion: 4,
        changed: true,
        upstreamTaskIds: ["task-a"],
      },
    });
    const result = await createCommandAdapter(port).setTaskDependencies({
      projectId: "project-1",
      downstreamTaskId: "task-b",
      upstreamTaskIds: ["task-a"],
      requestId: "request-1",
      expectedVersion: 3,
    });

    expect(rpc).toHaveBeenCalledWith("cmd_set_task_dependencies", {
      p_project_id: "project-1",
      p_downstream_task_id: "task-b",
      p_upstream_task_ids: ["task-a"],
      p_request_id: "request-1",
      p_expected_version: 3,
    });
    expect(result).toMatchObject({
      ok: true,
      data: { taskId: "task-b", taskVersion: 4, upstreamTaskIds: ["task-a"] },
    });
  });

  it.each([
    {
      method: "createProject" as const,
      input: {
        requestId: "request-1",
        expectedVersion: 0 as const,
        name: "XiaozhuWork",
        startAt: "2026-09-20T00:00:00Z",
        deadlineAt: "2026-10-01T00:00:00Z",
      },
      fn: "cmd_create_project",
      args: {
        p_request_id: "request-1",
        p_expected_version: 0,
        p_name: "XiaozhuWork",
        p_course_name: null,
        p_description: null,
        p_deadline_at: "2026-10-01T00:00:00Z",
        p_timezone: null,
        p_contribution_mode: null,
        p_allow_member_task_creation: true,
        p_require_real_name: null,
        p_require_student_number: null,
        p_start_at: "2026-09-20T00:00:00Z",
      },
      data: { projectId: "project-1", leaderMembershipId: "membership-1" },
    },
    {
      method: "createProjectInvite" as const,
      input: {
        projectId: "project-1",
        requestId: "request-1",
        expectedVersion: 3,
        mode: "approval" as const,
      },
      fn: "cmd_create_project_invite",
      args: {
        p_project_id: "project-1",
        p_request_id: "request-1",
        p_expected_version: 3,
        p_mode: "approval",
        p_expires_in_days: null,
        p_max_uses: null,
      },
      data: {
        invitationId: "invite-1",
        token: "secret-token",
        expiresAt: "2026-10-01T00:00:00Z",
        invitationVersion: 1,
      },
    },
    {
      method: "revokeProjectInvite" as const,
      input: {
        projectId: "project-1",
        invitationId: "invite-1",
        requestId: "request-1",
        expectedVersion: 1,
      },
      fn: "cmd_revoke_project_invite",
      args: {
        p_project_id: "project-1",
        p_invitation_id: "invite-1",
        p_request_id: "request-1",
        p_expected_version: 1,
      },
      data: {
        invitationId: "invite-1",
        revokedAt: "2026-09-26T00:00:00Z",
        canceledJoinRequestCount: 2,
      },
    },
    {
      method: "joinProjectViaInvite" as const,
      input: {
        token: "secret-token",
        requestId: "request-1",
        expectedVersion: 1,
      },
      fn: "cmd_join_project_via_invite",
      args: {
        p_token: "secret-token",
        p_request_id: "request-1",
        p_expected_version: 1,
      },
      data: {
        projectId: "project-1",
        outcome: "pending_approval" as const,
        joinRequestId: "join-1",
        invitationVersion: 2,
      },
    },
    {
      method: "reviewProjectJoinRequest" as const,
      input: {
        projectId: "project-1",
        joinRequestId: "join-1",
        action: "approve" as const,
        requestId: "request-1",
        expectedVersion: 1,
      },
      fn: "cmd_review_project_join_request",
      args: {
        p_project_id: "project-1",
        p_join_request_id: "join-1",
        p_action: "approve",
        p_request_id: "request-1",
        p_expected_version: 1,
      },
      data: {
        projectId: "project-1",
        joinRequestId: "join-1",
        state: "approved" as const,
        membershipId: "membership-2",
      },
    },
    {
      method: "createTask" as const,
      input: {
        projectId: "project-1",
        requestId: "request-1",
        expectedVersion: 2,
        title: "Research",
        deadlineAt: "2026-10-01T00:00:00Z",
        assignmentMode: "direct" as const,
      },
      fn: "cmd_create_task_v2",
      args: {
        p_project_id: "project-1",
        p_request_id: "request-1",
        p_expected_version: 2,
        p_title: "Research",
        p_description: null,
        p_deadline_at: "2026-10-01T00:00:00Z",
        p_weight: null,
        p_assignment_mode: "direct",
        p_assignee_id: null,
        p_required_submission_file_types: [],
        p_requires_review: true,
      },
      data: {
        taskId: "task-1",
        taskVersion: 1,
        assignmentOfferId: "offer-1",
        assignmentOfferVersion: 1,
      },
    },
    {
      method: "claimTask" as const,
      input: {
        projectId: "project-1",
        taskId: "task-1",
        requestId: "request-1",
        expectedVersion: 1,
      },
      fn: "cmd_claim_task",
      args: {
        p_project_id: "project-1",
        p_task_id: "task-1",
        p_request_id: "request-1",
        p_expected_version: 1,
      },
      data: {
        taskId: "task-1",
        assigneeId: "user-1",
        acceptedAt: "2026-09-26T00:00:00Z",
      },
    },
    {
      method: "respondToTaskAssignment" as const,
      input: {
        projectId: "project-1",
        taskId: "task-1",
        assignmentOfferId: "offer-1",
        requestId: "request-1",
        expectedVersion: 1,
        action: "reject" as const,
      },
      fn: "cmd_respond_to_task_assignment",
      args: {
        p_project_id: "project-1",
        p_task_id: "task-1",
        p_assignment_offer_id: "offer-1",
        p_request_id: "request-1",
        p_expected_version: 1,
        p_action: "reject",
      },
      data: {
        taskId: "task-1",
        assignmentOfferId: "offer-1",
        outcome: "rejected" as const,
        taskVersion: 2,
      },
    },
    {
      method: "updateTaskProgress" as const,
      input: {
        projectId: "project-1",
        taskId: "task-1",
        requestId: "request-1",
        expectedVersion: 2,
        status: "in_progress" as const,
        progressText: "Draft complete",
      },
      fn: "cmd_update_task_progress",
      args: {
        p_project_id: "project-1",
        p_task_id: "task-1",
        p_request_id: "request-1",
        p_expected_version: 2,
        p_status: "in_progress",
        p_progress_text: "Draft complete",
        p_blocked_reason: null,
      },
      data: {
        taskId: "task-1",
        status: "in_progress" as const,
        progressText: "Draft complete",
        updatedAt: "2026-09-26T00:00:00Z",
      },
    },
  ])(
    "maps $method to $fn and decodes success",
    async ({ method, input, fn, args, data }) => {
      const rpc = createRpcPort({ ...successEnvelope, data });
      const adapter = createCommandAdapter(rpc.port);

      const result = await adapter[method](input as never);

      expect(rpc.rpc).toHaveBeenCalledWith(fn, args);
      expect(result).toEqual({ ...successEnvelope, data });
    },
  );

  it.each([
    {
      method: "updateProjectMemberRole" as const,
      input: {
        projectId: "project-1",
        membershipId: "membership-2",
        targetRole: "admin" as const,
        requestId: "request-1",
        expectedVersion: 2,
      },
      fn: "cmd_update_project_member_role",
      args: {
        p_project_id: "project-1",
        p_membership_id: "membership-2",
        p_target_role: "admin",
        p_request_id: "request-1",
        p_expected_version: 2,
      },
      data: {
        membershipId: "membership-2",
        role: "admin" as const,
        membershipVersion: 3,
        projectVersion: 4,
        changed: true,
      },
    },
    {
      method: "removeProjectMember" as const,
      input: {
        projectId: "project-1",
        membershipId: "membership-2",
        requestId: "request-1",
        expectedVersion: 3,
      },
      fn: "cmd_remove_project_member",
      args: {
        p_project_id: "project-1",
        p_membership_id: "membership-2",
        p_request_id: "request-1",
        p_expected_version: 3,
      },
      data: {
        membershipId: "membership-2",
        state: "removed" as const,
        membershipVersion: 4,
        projectVersion: 5,
        releasedTaskCount: 1,
      },
    },
    {
      method: "leaveProject" as const,
      input: {
        projectId: "project-1",
        requestId: "request-1",
        expectedVersion: 4,
      },
      fn: "cmd_leave_project",
      args: {
        p_project_id: "project-1",
        p_request_id: "request-1",
        p_expected_version: 4,
      },
      data: {
        membershipId: "membership-2",
        state: "left" as const,
        membershipVersion: 5,
        projectVersion: 6,
        releasedTaskCount: 0,
      },
    },
    {
      method: "transferProjectLeadership" as const,
      input: {
        projectId: "project-1",
        targetMembershipId: "membership-2",
        requestId: "request-1",
        expectedVersion: 5,
      },
      fn: "cmd_transfer_project_leadership",
      args: {
        p_project_id: "project-1",
        p_target_membership_id: "membership-2",
        p_request_id: "request-1",
        p_expected_version: 5,
      },
      data: {
        projectId: "project-1",
        leaderUserId: "user-2",
        leaderMembershipId: "membership-2",
        projectVersion: 6,
      },
    },
    {
      method: "editTask" as const,
      input: {
        projectId: "project-1",
        taskId: "task-1",
        requestId: "request-1",
        expectedVersion: 2,
        title: "Renamed",
        description: "Updated",
        deadlineAt: "2026-10-02T00:00:00Z",
        weight: 4,
      },
      fn: "cmd_edit_task_v2",
      args: {
        p_project_id: "project-1",
        p_task_id: "task-1",
        p_request_id: "request-1",
        p_expected_version: 2,
        p_title: "Renamed",
        p_description: "Updated",
        p_deadline_at: "2026-10-02T00:00:00Z",
        p_weight: 4,
        p_required_submission_file_types: [],
      },
      data: {
        taskId: "task-1",
        taskVersion: 3,
        changed: true,
        title: "Renamed",
        description: "Updated",
        deadlineAt: "2026-10-02T00:00:00Z",
        weight: 4,
      },
    },
    {
      method: "setTaskFileVersionFinal" as const,
      input: {
        projectId: "project-1",
        fileVersionId: "file-version-1",
        requestId: "request-1",
        expectedVersion: 0,
        isFinal: true,
      },
      fn: "cmd_set_task_file_version_final",
      args: {
        p_project_id: "project-1",
        p_file_version_id: "file-version-1",
        p_request_id: "request-1",
        p_expected_version: 0,
        p_is_final: true,
      },
      data: {
        fileVersionId: "file-version-1",
        fileId: "file-1",
        taskId: "task-1",
        isFinal: true,
        designationVersion: 1,
        changed: true,
      },
    },
    {
      method: "updateProjectSettings" as const,
      input: {
        projectId: "project-1",
        requestId: "request-1",
        expectedVersion: 6,
        name: "Renamed project",
        courseName: "Course",
        description: "Description",
        startAt: "2026-09-20T00:00:00Z",
        deadlineAt: "2026-10-10T00:00:00Z",
        timezone: "Asia/Tokyo",
        contributionMode: "weighted" as const,
        autoPenaltyEnabled: false,
        requireRealName: false,
        requireStudentNumber: false,
      },
      fn: "cmd_update_project_settings",
      args: {
        p_project_id: "project-1",
        p_request_id: "request-1",
        p_expected_version: 6,
        p_name: "Renamed project",
        p_course_name: "Course",
        p_description: "Description",
        p_deadline_at: "2026-10-10T00:00:00Z",
        p_timezone: "Asia/Tokyo",
        p_contribution_mode: "weighted",
        p_auto_penalty_enabled: false,
        p_require_real_name: false,
        p_require_student_number: false,
        p_start_at: "2026-09-20T00:00:00Z",
      },
      data: {
        projectId: "project-1",
        projectVersion: 7,
        changed: true,
      },
    },
  ])(
    "maps new capability command $method to $fn",
    async ({ method, input, fn, args, data }) => {
      const rpc = createRpcPort({ ...successEnvelope, data });
      const adapter = createCommandAdapter(rpc.port);

      const result = await adapter[method](input as never);

      expect(rpc.rpc).toHaveBeenCalledWith(fn, args);
      expect(result).toEqual({ ...successEnvelope, data });
    },
  );

  it("accepts currentVersion zero for an absent versioned designation", async () => {
    const failure = {
      ok: false,
      code: "STALE_VERSION",
      requestId: "request-1",
      replayed: false,
      currentVersion: 0,
    };
    const rpc = createRpcPort(failure);

    await expect(
      createCommandAdapter(rpc.port).setTaskFileVersionFinal({
        projectId: "project-1",
        fileVersionId: "file-version-1",
        requestId: "request-1",
        expectedVersion: 1,
        isFinal: true,
      }),
    ).resolves.toEqual(failure);
  });

  it("preserves a replayed success envelope", async () => {
    const rpc = createRpcPort({
      ...successEnvelope,
      replayed: true,
      data: { projectId: "project-1", leaderMembershipId: "membership-1" },
    });

    await expect(
      createCommandAdapter(rpc.port).createProject({
        requestId: "request-1",
        expectedVersion: 0,
        name: "XiaozhuWork",
        deadlineAt: "2026-10-01T00:00:00Z",
      }),
    ).resolves.toMatchObject({ ok: true, replayed: true });
  });

  it("decodes a domain failure including safe details", async () => {
    const failure = {
      ok: false,
      code: "VALIDATION_FAILED",
      requestId: "request-1",
      replayed: false,
      field: "name",
      details: { minimumLength: 2, retryAllowed: false, hint: "short" },
    };
    const rpc = createRpcPort(failure);

    await expect(
      createCommandAdapter(rpc.port).createProject({
        requestId: "request-1",
        expectedVersion: 0,
        name: "T",
        deadlineAt: "2026-10-01T00:00:00Z",
      }),
    ).resolves.toEqual(failure);
  });

  it("decodes stale version failures", async () => {
    const failure = {
      ok: false,
      code: "STALE_VERSION",
      requestId: "request-1",
      replayed: false,
      currentVersion: 4,
    };
    const rpc = createRpcPort(failure);

    await expect(
      createCommandAdapter(rpc.port).claimTask({
        projectId: "project-1",
        taskId: "task-1",
        requestId: "request-1",
        expectedVersion: 3,
      }),
    ).resolves.toEqual(failure);
  });

  it.each([
    {
      name: "zero aggregate version",
      response: {
        ...successEnvelope,
        aggregateVersion: 0,
        data: {
          projectId: "project-1",
          leaderMembershipId: "membership-1",
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.createProject({
          requestId: "request-1",
          expectedVersion: 0,
          name: "XiaozhuWork",
          deadlineAt: "2026-10-01T00:00:00Z",
        }),
    },
    {
      name: "negative current version",
      response: {
        ok: false,
        code: "STALE_VERSION",
        requestId: "request-1",
        replayed: false,
        currentVersion: -1,
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.createProject({
          requestId: "request-1",
          expectedVersion: 0,
          name: "XiaozhuWork",
          deadlineAt: "2026-10-01T00:00:00Z",
        }),
    },
    {
      name: "fractional invitation version",
      response: {
        ...successEnvelope,
        data: {
          invitationId: "invite-1",
          token: "secret-token",
          expiresAt: "2026-10-01T00:00:00Z",
          invitationVersion: 1.5,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.createProjectInvite({
          projectId: "project-1",
          requestId: "request-1",
          expectedVersion: 1,
          mode: "direct",
        }),
    },
    {
      name: "negative canceled join request count",
      response: {
        ...successEnvelope,
        data: {
          invitationId: "invite-1",
          revokedAt: "2026-09-26T00:00:00Z",
          canceledJoinRequestCount: -1,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.revokeProjectInvite({
          projectId: "project-1",
          invitationId: "invite-1",
          requestId: "request-1",
          expectedVersion: 1,
        }),
    },
    {
      name: "zero task version",
      response: {
        ...successEnvelope,
        data: { taskId: "task-1", taskVersion: 0 },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.createTask({
          projectId: "project-1",
          requestId: "request-1",
          expectedVersion: 1,
          title: "Research",
          deadlineAt: "2026-10-01T00:00:00Z",
          assignmentMode: "claimable",
        }),
    },
    {
      name: "zero assignment offer version",
      response: {
        ...successEnvelope,
        data: {
          taskId: "task-1",
          taskVersion: 1,
          assignmentOfferId: "offer-1",
          assignmentOfferVersion: 0,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.createTask({
          projectId: "project-1",
          requestId: "request-1",
          expectedVersion: 1,
          title: "Research",
          deadlineAt: "2026-10-01T00:00:00Z",
          assignmentMode: "direct",
          assigneeId: "user-1",
        }),
    },
  ])("rejects $name from RPC JSON", async ({ response, invoke }) => {
    const rpc = createRpcPort(response);

    await expect(invoke(createCommandAdapter(rpc.port))).rejects.toMatchObject({
      name: "CommandTransportError",
      requestId: "request-1",
      retryable: false,
    });
  });

  it.each([
    {
      name: "joined invite outcome without a membership",
      response: {
        ...successEnvelope,
        data: {
          projectId: "project-1",
          outcome: "joined",
          invitationVersion: 2,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.joinProjectViaInvite({
          token: "secret-token",
          requestId: "request-1",
          expectedVersion: 1,
        }),
    },
    {
      name: "pending invite outcome without a join request",
      response: {
        ...successEnvelope,
        data: {
          projectId: "project-1",
          outcome: "pending_approval",
          invitationVersion: 2,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.joinProjectViaInvite({
          token: "secret-token",
          requestId: "request-1",
          expectedVersion: 1,
        }),
    },
    {
      name: "approved join request without a membership",
      response: {
        ...successEnvelope,
        data: {
          projectId: "project-1",
          joinRequestId: "join-1",
          state: "approved",
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.reviewProjectJoinRequest({
          projectId: "project-1",
          joinRequestId: "join-1",
          action: "approve",
          requestId: "request-1",
          expectedVersion: 1,
        }),
    },
  ])("rejects $name", async ({ response, invoke }) => {
    const rpc = createRpcPort(response);

    await expect(invoke(createCommandAdapter(rpc.port))).rejects.toMatchObject({
      name: "CommandTransportError",
      requestId: "request-1",
      retryable: false,
    });
  });

  it("accepts a rejected join request without a membership", async () => {
    const rpc = createRpcPort({
      ...successEnvelope,
      data: {
        projectId: "project-1",
        joinRequestId: "join-1",
        state: "rejected",
      },
    });

    await expect(
      createCommandAdapter(rpc.port).reviewProjectJoinRequest({
        projectId: "project-1",
        joinRequestId: "join-1",
        action: "reject",
        requestId: "request-1",
        expectedVersion: 1,
      }),
    ).resolves.toMatchObject({
      ok: true,
      data: { state: "rejected" },
    });
  });

  it.each([
    {
      name: "unused membership on a pending invite",
      response: {
        ...successEnvelope,
        data: {
          projectId: "project-1",
          outcome: "pending_approval",
          membershipId: null,
          joinRequestId: "join-1",
          invitationVersion: 2,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.joinProjectViaInvite({
          token: "secret-token",
          requestId: "request-1",
          expectedVersion: 1,
        }),
      expectedData: {
        projectId: "project-1",
        outcome: "pending_approval",
        joinRequestId: "join-1",
        invitationVersion: 2,
      },
    },
    {
      name: "unused join request on a joined invite",
      response: {
        ...successEnvelope,
        data: {
          projectId: "project-1",
          outcome: "joined",
          membershipId: "membership-1",
          joinRequestId: null,
          invitationVersion: 2,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.joinProjectViaInvite({
          token: "secret-token",
          requestId: "request-1",
          expectedVersion: 1,
        }),
      expectedData: {
        projectId: "project-1",
        outcome: "joined",
        membershipId: "membership-1",
        invitationVersion: 2,
      },
    },
    {
      name: "membership on a rejected join request",
      response: {
        ...successEnvelope,
        data: {
          projectId: "project-1",
          joinRequestId: "join-1",
          state: "rejected",
          membershipId: null,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.reviewProjectJoinRequest({
          projectId: "project-1",
          joinRequestId: "join-1",
          action: "reject",
          requestId: "request-1",
          expectedVersion: 1,
        }),
      expectedData: {
        projectId: "project-1",
        joinRequestId: "join-1",
        state: "rejected",
      },
    },
    {
      name: "assignment offer fields on a claimable task",
      response: {
        ...successEnvelope,
        data: {
          taskId: "task-1",
          taskVersion: 1,
          assignmentOfferId: null,
          assignmentOfferVersion: null,
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.createTask({
          projectId: "project-1",
          requestId: "request-1",
          expectedVersion: 1,
          title: "Research",
          deadlineAt: "2026-10-01T00:00:00Z",
          assignmentMode: "claimable",
        }),
      expectedData: { taskId: "task-1", taskVersion: 1 },
    },
    {
      name: "blocked reason on in-progress task progress",
      response: {
        ...successEnvelope,
        data: {
          taskId: "task-1",
          status: "in_progress",
          progressText: "Drafting",
          blockedReason: null,
          updatedAt: "2026-09-26T00:00:00Z",
        },
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.updateTaskProgress({
          projectId: "project-1",
          taskId: "task-1",
          requestId: "request-1",
          expectedVersion: 1,
          status: "in_progress",
          progressText: "Drafting",
        }),
      expectedData: {
        taskId: "task-1",
        status: "in_progress",
        progressText: "Drafting",
        updatedAt: "2026-09-26T00:00:00Z",
      },
    },
  ])(
    "normalizes nullable optional $name",
    async ({ response, invoke, expectedData }) => {
      const rpc = createRpcPort(response);

      const result = await invoke(createCommandAdapter(rpc.port));

      expect(result).toMatchObject({ ok: true });
      if (!result.ok) throw new Error("Expected command success");
      expect(result.data).toEqual(expectedData);
    },
  );

  it("maps primary handoff response and review correction to authoritative RPCs", async () => {
    const handoffRpc = createRpcPort({
      ...successEnvelope,
      aggregateType: "task_primary_handoff",
      aggregateId: "handoff-1",
      aggregateVersion: 2,
      data: {
        taskId: "task-1",
        handoffId: "handoff-1",
        fromUserId: "user-1",
        toUserId: "user-2",
        state: "accepted",
        handoffVersion: 2,
        taskVersion: 4,
      },
    });
    const handoffResult = await createCommandAdapter(
      handoffRpc.port,
    ).respondTaskPrimaryHandoff({
      projectId: "project-1",
      taskId: "task-1",
      handoffId: "handoff-1",
      action: "accept",
      requestId: "request-1",
      expectedHandoffVersion: 1,
      expectedTaskVersion: 3,
    });
    expect(handoffRpc.rpc).toHaveBeenCalledWith(
      "cmd_respond_task_primary_handoff",
      {
        p_project_id: "project-1",
        p_task_id: "task-1",
        p_handoff_id: "handoff-1",
        p_action: "accept",
        p_request_id: "request-1",
        p_expected_handoff_version: 1,
        p_expected_task_version: 3,
      },
    );
    expect(handoffResult).toMatchObject({
      ok: true,
      data: { state: "accepted", handoffVersion: 2, taskVersion: 4 },
    });

    const correctionRpc = createRpcPort({
      ...successEnvelope,
      aggregateType: "task_review_round",
      aggregateId: "round-2",
      aggregateVersion: 1,
      data: {
        taskId: "task-1",
        sourceReviewRoundId: "round-1",
        reviewRoundId: "round-2",
        roundNumber: 2,
        taskVersion: 5,
        reviewRoundVersion: 1,
      },
    });
    const correctionResult = await createCommandAdapter(
      correctionRpc.port,
    ).correctTaskReviewRequestChanges({
      projectId: "project-1",
      taskId: "task-1",
      reviewRoundId: "round-1",
      requestId: "request-2",
      expectedTaskVersion: 4,
      expectedReviewVersion: 2,
    });
    expect(correctionRpc.rpc).toHaveBeenCalledWith(
      "cmd_correct_task_review_request_changes",
      {
        p_project_id: "project-1",
        p_task_id: "task-1",
        p_review_round_id: "round-1",
        p_request_id: "request-2",
        p_expected_task_version: 4,
        p_expected_review_version: 2,
      },
    );
    expect(correctionResult).toMatchObject({
      ok: true,
      data: { sourceReviewRoundId: "round-1", reviewRoundId: "round-2" },
    });
  });

  it("maps and decodes invite previews without a command envelope", async () => {
    const preview = {
      projectId: "project-1",
      projectName: "XiaozhuWork",
      projectDeadlineAt: "2026-10-01T00:00:00Z",
      requireRealName: true,
      requireStudentNumber: false,
      mode: "direct",
      expiresAt: "2026-09-30T00:00:00Z",
      available: true,
      invitationVersion: 2,
    };
    const rpc = createRpcPort(preview);

    await expect(
      createCommandAdapter(rpc.port).previewProjectInvite({ token: "token-1" }),
    ).resolves.toEqual(preview);
    expect(rpc.rpc).toHaveBeenCalledWith("preview_project_invite", {
      p_token: "token-1",
    });
  });

  it.each([
    null,
    { ...successEnvelope, data: { projectId: 7 } },
    { ...successEnvelope, data: { projectId: "project-1" } },
    {
      ok: false,
      code: "VALIDATION_FAILED",
      requestId: "request-1",
      replayed: false,
      details: { unsafe: { nested: true } },
    },
  ])("throws a transport error for malformed RPC JSON", async (data) => {
    const rpc = createRpcPort(data);

    const promise = createCommandAdapter(rpc.port).createProject({
      requestId: "request-1",
      expectedVersion: 0,
      name: "XiaozhuWork",
      deadlineAt: "2026-10-01T00:00:00Z",
    });

    await expect(promise).rejects.toMatchObject({
      name: "CommandTransportError",
      requestId: "request-1",
      retryable: false,
      diagnosticId: expect.stringMatching(/^cmd_/),
    });
  });

  it("does not mark deterministic Postgres errors as retryable", async () => {
    const rpc = createRpcPort(null, {
      message: "permission denied",
      code: "42501",
    });

    const error = await createCommandAdapter(rpc.port)
      .createProject({
        requestId: "request-1",
        expectedVersion: 0,
        name: "XiaozhuWork",
        deadlineAt: "2026-10-01T00:00:00Z",
      })
      .catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(CommandTransportError);
    expect(error).toMatchObject({
      requestId: "request-1",
      retryable: false,
    });
  });

  it("wraps Supabase errors without leaking their message", async () => {
    const rpc = createRpcPort(null, {
      message: "secret database detail",
      code: "57014",
    });

    const promise = createCommandAdapter(rpc.port).createProject({
      requestId: "request-1",
      expectedVersion: 0,
      name: "XiaozhuWork",
      deadlineAt: "2026-10-01T00:00:00Z",
    });

    const error = await promise.catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(CommandTransportError);
    expect(error).toMatchObject({
      requestId: "request-1",
      retryable: true,
      diagnosticId: expect.stringMatching(/^cmd_/),
    });
    expect(String(error)).not.toContain("secret database detail");
  });

  it("creates UUID request identifiers", () => {
    expect(newRequestId()).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });
});
