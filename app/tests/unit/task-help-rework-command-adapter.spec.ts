import { describe, expect, it, vi } from "vitest";

import { createCommandAdapter, type RpcPort } from "@/lib/command-adapter";

function portFor(data: unknown) {
  const rpc = vi.fn().mockResolvedValue({ data, error: null });
  return { port: { rpc } as RpcPort, rpc };
}

describe("task help and upstream rework command adapter", () => {
  it("maps task help creation and resolution to authoritative RPCs", async () => {
    const create = portFor({
      ok: true,
      requestId: "request-help",
      replayed: false,
      aggregateType: "task_help_request",
      aggregateId: "help-1",
      aggregateVersion: 1,
      data: {
        helpRequestId: "help-1",
        state: "open",
        helpVersion: 1,
        taskVersion: 4,
        taskResumed: false,
      },
    });
    await createCommandAdapter(create.port).createTaskHelpRequest({
      projectId: "project-1",
      taskId: "task-1",
      requestId: "request-help",
      expectedVersion: 3,
      message: "Please help",
      targetUserId: "user-2",
      marksTaskBlocked: true,
    });
    expect(create.rpc).toHaveBeenCalledWith("cmd_create_task_help_request", {
      p_project_id: "project-1",
      p_task_id: "task-1",
      p_request_id: "request-help",
      p_expected_version: 3,
      p_message: "Please help",
      p_target_user_id: "user-2",
      p_marks_task_blocked: true,
    });

    const resolve = portFor({
      ok: true,
      requestId: "request-resolve",
      replayed: false,
      aggregateType: "task_help_request",
      aggregateId: "help-1",
      aggregateVersion: 2,
      data: {
        helpRequestId: "help-1",
        state: "resolved",
        helpVersion: 2,
        taskVersion: 5,
        taskResumed: true,
      },
    });
    const result = await createCommandAdapter(
      resolve.port,
    ).resolveTaskHelpRequest({
      projectId: "project-1",
      helpRequestId: "help-1",
      requestId: "request-resolve",
      expectedVersion: 1,
    });
    expect(resolve.rpc).toHaveBeenCalledWith("cmd_resolve_task_help_request", {
      p_project_id: "project-1",
      p_help_request_id: "help-1",
      p_request_id: "request-resolve",
      p_expected_version: 1,
    });
    expect(result).toMatchObject({ ok: true, data: { taskResumed: true } });
  });

  it("maps member request and leader review for upstream rework", async () => {
    const request = portFor({
      ok: true,
      requestId: "request-rework",
      replayed: false,
      aggregateType: "upstream_rework_request",
      aggregateId: "rework-1",
      aggregateVersion: 1,
      data: {
        reworkRequestId: "rework-1",
        state: "pending",
        requestVersion: 1,
        downstreamTaskVersion: 7,
        upstreamTaskVersion: 5,
      },
    });
    await createCommandAdapter(request.port).requestUpstreamRework({
      projectId: "project-1",
      downstreamTaskId: "task-down",
      upstreamTaskId: "task-up",
      requestId: "request-rework",
      expectedDownstreamVersion: 7,
      expectedUpstreamVersion: 5,
      requirement: "Please revise",
    });
    expect(request.rpc).toHaveBeenCalledWith("cmd_request_upstream_rework", {
      p_project_id: "project-1",
      p_downstream_task_id: "task-down",
      p_upstream_task_id: "task-up",
      p_request_id: "request-rework",
      p_expected_downstream_version: 7,
      p_expected_upstream_version: 5,
      p_requirement: "Please revise",
    });

    const review = portFor({
      ok: true,
      requestId: "request-review",
      replayed: false,
      aggregateType: "upstream_rework_request",
      aggregateId: "rework-1",
      aggregateVersion: 2,
      data: {
        reworkRequestId: "rework-1",
        state: "approved",
        requestVersion: 2,
        downstreamTaskVersion: 7,
        upstreamTaskVersion: 6,
      },
    });
    await createCommandAdapter(review.port).reviewUpstreamRework({
      projectId: "project-1",
      reworkRequestId: "rework-1",
      requestId: "request-review",
      expectedVersion: 1,
      action: "approve",
    });
    expect(review.rpc).toHaveBeenCalledWith("cmd_review_upstream_rework", {
      p_project_id: "project-1",
      p_rework_request_id: "rework-1",
      p_request_id: "request-review",
      p_expected_version: 1,
      p_action: "approve",
    });
  });

  it("rejects malformed workflow success payloads", async () => {
    const { port } = portFor({
      ok: true,
      requestId: "request-bad",
      replayed: false,
      aggregateType: "task_help_request",
      aggregateId: "help-1",
      aggregateVersion: 1,
      data: { helpRequestId: "help-1", state: "resolved" },
    });
    await expect(
      createCommandAdapter(port).createTaskHelpRequest({
        projectId: "project-1",
        taskId: "task-1",
        requestId: "request-bad",
        expectedVersion: 1,
        message: "help",
        marksTaskBlocked: false,
      }),
    ).rejects.toMatchObject({ retryable: false });
  });
});
