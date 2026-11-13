import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

import { createRepository } from "@/services/repository";
import type { Database } from "@/types/database.generated";

describe("task change proposal repository", () => {
  it("loads project-scoped proposal truth in newest-first order", async () => {
    const proposal = {
      id: "proposal-1",
      project_id: "project-1",
      task_id: "task-1",
      state: "pending",
      base_task_version: 1,
      proposed_by: "user-1",
      required_confirmer_id: "user-2",
      old_deadline_at: "2026-10-11T00:00:00Z",
      new_deadline_at: "2026-10-12T00:00:00Z",
      created_at: "2026-10-11T00:00:00Z",
      updated_at: "2026-10-11T00:00:00Z",
      version: 1,
    };
    const order = vi.fn().mockResolvedValue({ data: [proposal], error: null });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    const repository = createRepository({
      from,
    } as unknown as SupabaseClient<Database>);

    await expect(
      repository.listTaskChangeProposals("project-1"),
    ).resolves.toEqual([proposal]);
    expect(from).toHaveBeenCalledWith("task_change_proposals_visible");
    expect(eq).toHaveBeenCalledWith("project_id", "project-1");
    expect(order).toHaveBeenCalledWith("created_at", { ascending: false });
  });
});
