import { describe, expect, it, vi } from "vitest";

import { createTaskWorkflowRepository } from "@/services/task-workflow-repository";
import type { Database } from "@/types/database.generated";
import type { SupabaseClient } from "@supabase/supabase-js";

const PROJECT_ID = "11111111-1111-4111-8111-111111111111";
const OTHER_PROJECT_ID = "22222222-2222-4222-8222-222222222222";
const TASK_ID = "33333333-3333-4333-8333-333333333333";
const UPSTREAM_ID = "44444444-4444-4444-8444-444444444444";

describe("task help and rework repository", () => {
  it("scopes help history by both project and task", async () => {
    const row = { id: "help-1", project_id: PROJECT_ID, task_id: TASK_ID };
    const order = vi.fn().mockResolvedValue({ data: [row], error: null });
    const eqTask = vi.fn().mockReturnValue({ order });
    const eqProject = vi.fn().mockReturnValue({ eq: eqTask });
    const select = vi.fn().mockReturnValue({ eq: eqProject });
    const from = vi.fn().mockReturnValue({ select });
    const repository = createTaskWorkflowRepository({
      from,
    } as unknown as SupabaseClient<Database>);

    await expect(
      repository.listTaskHelpRequests(PROJECT_ID, TASK_ID),
    ).resolves.toEqual([row]);
    expect(from).toHaveBeenCalledWith("task_help_requests");
    expect(eqProject).toHaveBeenCalledWith("project_id", PROJECT_ID);
    expect(eqTask).toHaveBeenCalledWith("task_id", TASK_ID);
  });

  it("scopes rework history to the project and either side of the task relation", async () => {
    const row = {
      id: "rework-1",
      project_id: PROJECT_ID,
      downstream_task_id: TASK_ID,
      upstream_task_id: UPSTREAM_ID,
    };
    const order = vi.fn().mockResolvedValue({ data: [row], error: null });
    const or = vi.fn().mockReturnValue({ order });
    const eq = vi.fn().mockReturnValue({ or });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    const repository = createTaskWorkflowRepository({
      from,
    } as unknown as SupabaseClient<Database>);

    await expect(
      repository.listRelatedUpstreamReworkRequests(PROJECT_ID, TASK_ID),
    ).resolves.toEqual([row]);
    expect(from).toHaveBeenCalledWith("upstream_rework_requests");
    expect(eq).toHaveBeenCalledWith("project_id", PROJECT_ID);
    expect(or).toHaveBeenCalledWith(
      `downstream_task_id.eq.${TASK_ID},upstream_task_id.eq.${TASK_ID}`,
    );
  });

  it("rejects malformed task ids before building a raw PostgREST or filter", async () => {
    const from = vi.fn();
    const repository = createTaskWorkflowRepository({
      from,
    } as unknown as SupabaseClient<Database>);

    await expect(
      repository.listRelatedUpstreamReworkRequests(PROJECT_ID, "bad),id.eq.*"),
    ).rejects.toThrow("Invalid task id");
    expect(from).not.toHaveBeenCalled();
  });

  it("rejects cross-project rows even if a mocked backend returns them", async () => {
    const row = {
      id: "rework-1",
      project_id: OTHER_PROJECT_ID,
      downstream_task_id: TASK_ID,
      upstream_task_id: UPSTREAM_ID,
    };
    const order = vi.fn().mockResolvedValue({ data: [row], error: null });
    const or = vi.fn().mockReturnValue({ order });
    const eq = vi.fn().mockReturnValue({ or });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    const repository = createTaskWorkflowRepository({
      from,
    } as unknown as SupabaseClient<Database>);

    await expect(
      repository.listRelatedUpstreamReworkRequests(PROJECT_ID, TASK_ID),
    ).rejects.toThrow("Cross-project workflow response");
  });
});
