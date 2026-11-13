import { describe, expect, it, vi } from "vitest";
import { createRepository } from "@/services/repository";
import type { Database } from "@/types/database.generated";
import type { SupabaseClient } from "@supabase/supabase-js";

describe("task dependency repository", () => {
  it("reads only the current project's dependency facts", async () => {
    const dependency = {
      project_id: "project-1",
      upstream_task_id: "task-a",
      downstream_task_id: "task-b",
      created_by: "user-1",
      created_at: "2026-09-30T00:00:00Z",
    };
    const order = vi
      .fn()
      .mockResolvedValue({ data: [dependency], error: null });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    const repository = createRepository({
      from,
    } as unknown as SupabaseClient<Database>);

    await expect(repository.listTaskDependencies("project-1")).resolves.toEqual(
      [dependency],
    );
    expect(from).toHaveBeenCalledWith("task_dependencies");
    expect(eq).toHaveBeenCalledWith("project_id", "project-1");
  });
});
