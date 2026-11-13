import { describe, expect, it, vi } from "vitest";

import { createCommandAdapter } from "@/lib/command-adapter";

function rpcSuccess(
  data: unknown,
  aggregateType = "task",
  aggregateId = "aggregate-1",
  aggregateVersion = 2,
) {
  const rpc = vi.fn().mockResolvedValue({
    data: {
      ok: true,
      data,
      requestId: "request-1",
      replayed: false,
      aggregateType,
      aggregateId,
      aggregateVersion,
    },
    error: null,
  });
  return { port: { rpc }, rpc };
}

describe("strict Day 4 command adapter", () => {
  it("maps file upload reservation to snake_case RPC parameters", async () => {
    const rpc = rpcSuccess(
      {
        reservationId: "reservation-1",
        objectPath: "pending/project/reservation/file.pdf",
        expiresAt: "2026-09-29T00:00:00Z",
      },
      "file_upload_reservation",
      "reservation-1",
      1,
    );
    const adapter = createCommandAdapter(rpc.port);

    const result = await adapter.reserveTaskFileUpload({
      projectId: "project-1",
      taskId: "task-1",
      requestId: "request-1",
      expectedVersion: 3,
      mode: "new_version",
      targetFileId: "file-1",
      originalName: "report.pdf",
      declaredMimeType: "application/pdf",
      declaredSizeBytes: 1024,
    });

    expect(rpc.rpc).toHaveBeenCalledWith("cmd_reserve_task_file_upload", {
      p_project_id: "project-1",
      p_task_id: "task-1",
      p_request_id: "request-1",
      p_expected_version: 3,
      p_mode: "new_version",
      p_target_file_id: "file-1",
      p_original_name: "report.pdf",
      p_declared_mime_type: "application/pdf",
      p_declared_size_bytes: 1024,
    });
    expect(result).toMatchObject({
      ok: true,
      data: { reservationId: "reservation-1" },
    });
  });

  it("maps submit/review/contribution commands and decodes their results", async () => {
    const submitRpc = rpcSuccess({
      taskId: "task-1",
      reviewRoundId: "round-1",
      roundNumber: 2,
      submittedAt: "2026-09-28T00:00:00Z",
    });
    const submit = createCommandAdapter(submitRpc.port);
    await expect(
      submit.submitTaskForReview({
        projectId: "project-1",
        taskId: "task-1",
        submissionText: "Done",
        fileVersionIds: ["version-1", "version-2"],
        requestId: "request-1",
        expectedVersion: 4,
      }),
    ).resolves.toMatchObject({
      ok: true,
      data: { reviewRoundId: "round-1", roundNumber: 2 },
    });
    expect(submitRpc.rpc).toHaveBeenCalledWith("cmd_submit_task_for_review", {
      p_project_id: "project-1",
      p_task_id: "task-1",
      p_submission_text: "Done",
      p_file_version_ids: ["version-1", "version-2"],
      p_request_id: "request-1",
      p_expected_version: 4,
    });

    const reviewRpc = rpcSuccess(
      {
        taskId: "task-1",
        reviewRoundId: "round-1",
        outcome: "request_changes",
        taskStatus: "in_progress",
        reviewedAt: "2026-09-28T01:00:00Z",
        rejectionReason: "Please add evidence",
      },
      "task_review_round",
      "round-1",
      2,
    );
    const review = createCommandAdapter(reviewRpc.port);
    await expect(
      review.reviewTaskSubmission({
        projectId: "project-1",
        taskId: "task-1",
        reviewRoundId: "round-1",
        action: "request_changes",
        rejectionReason: "Please add evidence",
        requestId: "request-1",
        expectedVersion: 1,
      }),
    ).resolves.toMatchObject({
      ok: true,
      data: { outcome: "request_changes", taskStatus: "in_progress" },
    });
    expect(reviewRpc.rpc).toHaveBeenCalledWith("cmd_review_task_submission", {
      p_project_id: "project-1",
      p_task_id: "task-1",
      p_review_round_id: "round-1",
      p_action: "request_changes",
      p_rejection_reason: "Please add evidence",
      p_request_id: "request-1",
      p_expected_version: 1,
    });

    const createReportRpc = rpcSuccess(
      {
        projectId: "project-1",
        reportId: "report-1",
        reportVersion: 1,
        itemCount: 3,
        state: "draft",
      },
      "project",
      "project-1",
      8,
    );
    const createReport = createCommandAdapter(createReportRpc.port);
    await expect(
      createReport.createContributionReport({
        projectId: "project-1",
        requestId: "request-1",
        expectedVersion: 7,
      }),
    ).resolves.toMatchObject({
      ok: true,
      data: { reportId: "report-1", itemCount: 3 },
    });

    const confirmRpc = rpcSuccess(
      {
        projectId: "project-1",
        reportId: "report-1",
        state: "formal",
        confirmedCount: 2,
        eligibleCount: 3,
        requiredCount: 2,
        formalized: true,
      },
      "contribution_report",
      "report-1",
      3,
    );
    const confirm = createCommandAdapter(confirmRpc.port);
    await expect(
      confirm.confirmContributionReport({
        projectId: "project-1",
        reportId: "report-1",
        requestId: "request-1",
        expectedVersion: 2,
      }),
    ).resolves.toMatchObject({
      ok: true,
      data: { formalized: true, state: "formal" },
    });
  });

  it("accepts the strict Day 4 domain error codes", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        ok: false,
        code: "STORAGE_QUOTA_EXCEEDED",
        requestId: "request-1",
        replayed: false,
        details: { scope: "project", limitBytes: 536870912 },
      },
      error: null,
    });

    await expect(
      createCommandAdapter({ rpc }).reserveTaskFileUpload({
        projectId: "project-1",
        taskId: "task-1",
        requestId: "request-1",
        expectedVersion: 1,
        mode: "new_file",
        originalName: "report.pdf",
        declaredMimeType: "application/pdf",
        declaredSizeBytes: 1024,
      }),
    ).resolves.toMatchObject({ ok: false, code: "STORAGE_QUOTA_EXCEEDED" });
  });

  it.each([
    "ACTIVE_FREE_PROJECT_LIMIT_REACHED",
    "PROJECT_MEMBER_LIMIT_REACHED",
    "CONCURRENT_TASK_LIMIT_REACHED",
  ] as const)("accepts the P1 quota error code %s", async (code) => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        ok: false,
        code,
        requestId: "request-1",
        replayed: false,
        details: { limit: 5, current: 5, effectiveState: "free" },
      },
      error: null,
    });

    await expect(
      createCommandAdapter({ rpc }).createProject({
        requestId: "request-1",
        expectedVersion: 0,
        name: "Quota test",
        deadlineAt: "2026-12-31T00:00:00Z",
      }),
    ).resolves.toMatchObject({ ok: false, code });
  });

  it.each([
    {
      name: "approved review that leaves the task in progress",
      data: {
        taskId: "task-1",
        reviewRoundId: "round-1",
        outcome: "approve",
        taskStatus: "in_progress",
        reviewedAt: "2026-09-28T01:00:00Z",
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.reviewTaskSubmission({
          projectId: "project-1",
          taskId: "task-1",
          reviewRoundId: "round-1",
          action: "approve",
          requestId: "request-1",
          expectedVersion: 1,
        }),
    },
    {
      name: "formalized contribution report that is still draft",
      data: {
        projectId: "project-1",
        reportId: "report-1",
        state: "draft",
        confirmedCount: 2,
        eligibleCount: 3,
        requiredCount: 2,
        formalized: true,
      },
      invoke: (adapter: ReturnType<typeof createCommandAdapter>) =>
        adapter.confirmContributionReport({
          projectId: "project-1",
          reportId: "report-1",
          requestId: "request-1",
          expectedVersion: 2,
        }),
    },
  ])("rejects contradictory $name payloads", async ({ data, invoke }) => {
    const rpc = rpcSuccess(data);

    await expect(invoke(createCommandAdapter(rpc.port))).rejects.toMatchObject({
      name: "CommandTransportError",
      requestId: "request-1",
      retryable: false,
    });
  });

  it("rejects malformed new-command payloads as transport errors", async () => {
    const rpc = rpcSuccess({
      projectId: "project-1",
      reportId: "report-1",
      reportVersion: 0,
      itemCount: -1,
      state: "draft",
    });

    await expect(
      createCommandAdapter(rpc.port).createContributionReport({
        projectId: "project-1",
        requestId: "request-1",
        expectedVersion: 3,
      }),
    ).rejects.toMatchObject({
      name: "CommandTransportError",
      requestId: "request-1",
      retryable: false,
    });
  });
});
