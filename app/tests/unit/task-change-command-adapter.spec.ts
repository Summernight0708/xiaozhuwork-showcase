import { describe, expect, it, vi } from "vitest";

import { createCommandAdapter, type RpcPort } from "@/lib/command-adapter";

function portFor(data: unknown) {
  const rpc = vi.fn().mockResolvedValue({ data, error: null });
  return { port: { rpc } as RpcPort, rpc };
}

describe("task change command adapter", () => {
  it("maps proposal creation to the authoritative RPC and decodes its envelope", async () => {
    const { port, rpc } = portFor({
      ok: true,
      requestId: "request-1",
      replayed: false,
      aggregateType: "task_change_proposal",
      aggregateId: "proposal-1",
      aggregateVersion: 1,
      data: {
        proposalId: "proposal-1",
        taskId: "task-1",
        state: "pending",
        proposalVersion: 1,
        createdAt: "2026-10-01T00:00:00Z",
      },
    });

    const result = await createCommandAdapter(port).proposeTaskChange({
      projectId: "project-1",
      taskId: "task-1",
      deadlineAt: "2026-10-10T00:00:00Z",
      weight: 4,
      requestId: "request-1",
      expectedTaskVersion: 3,
    });

    expect(rpc).toHaveBeenCalledWith("cmd_propose_task_change_v2", {
      p_project_id: "project-1",
      p_task_id: "task-1",
      p_deadline_at: "2026-10-10T00:00:00Z",
      p_weight: 4,
      p_request_id: "request-1",
      p_expected_task_version: 3,
      p_required_submission_file_types: [],
    });
    expect(result).toMatchObject({
      ok: true,
      data: { proposalId: "proposal-1", state: "pending", proposalVersion: 1 },
    });
  });

  it("maps assignee approval and optional rejection reason without client authority shortcuts", async () => {
    const { port, rpc } = portFor({
      ok: true,
      requestId: "request-2",
      replayed: false,
      aggregateType: "task_change_proposal",
      aggregateId: "proposal-1",
      aggregateVersion: 2,
      data: {
        proposalId: "proposal-1",
        taskId: "task-1",
        state: "approved",
        proposalVersion: 2,
        taskVersion: 4,
        decidedAt: "2026-10-01T01:00:00Z",
      },
    });

    await createCommandAdapter(port).respondToTaskChange({
      projectId: "project-1",
      taskId: "task-1",
      proposalId: "proposal-1",
      action: "approve",
      requestId: "request-2",
      expectedProposalVersion: 1,
    });

    expect(rpc).toHaveBeenCalledWith("cmd_respond_to_task_change", {
      p_project_id: "project-1",
      p_task_id: "task-1",
      p_proposal_id: "proposal-1",
      p_action: "approve",
      p_rejection_reason: null,
      p_request_id: "request-2",
      p_expected_proposal_version: 1,
    });
  });

  it("rejects malformed proposal payloads instead of trusting the browser response shape", async () => {
    const { port } = portFor({
      ok: true,
      requestId: "request-3",
      replayed: false,
      aggregateType: "task_change_proposal",
      aggregateId: "proposal-1",
      aggregateVersion: 1,
      data: { proposalId: "proposal-1", taskId: "task-1", state: "approved" },
    });

    await expect(
      createCommandAdapter(port).proposeTaskChange({
        projectId: "project-1",
        taskId: "task-1",
        deadlineAt: "2026-10-10T00:00:00Z",
        weight: 4,
        requestId: "request-3",
        expectedTaskVersion: 3,
      }),
    ).rejects.toMatchObject({ retryable: false });
  });
});
