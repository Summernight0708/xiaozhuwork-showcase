import { describe, expect, it } from "vitest";

import {
  hasSafeInAppHistoryBack,
  projectBackTarget,
} from "@/domain/project-navigation";

describe("project navigation back policy", () => {
  it("maps detail and secondary project routes to project-local fallbacks", () => {
    expect(projectBackTarget("task-detail")).toEqual({
      label: "返回任务列表",
      routeName: "project-tasks",
    });
    expect(projectBackTarget("file-detail")?.routeName).toBe("project-files");
    expect(projectBackTarget("review-detail")?.routeName).toBe(
      "project-reviews",
    );
    expect(projectBackTarget("project-members")?.routeName).toBe(
      "project-overview",
    );
    expect(projectBackTarget("project-settings")?.routeName).toBe(
      "project-overview",
    );
  });

  it("allows only router-local history entries for explicit back buttons", () => {
    expect(hasSafeInAppHistoryBack("/projects/project-1/tasks")).toBe(true);
    expect(hasSafeInAppHistoryBack("/notifications?project=project-1")).toBe(
      true,
    );
    expect(hasSafeInAppHistoryBack(null)).toBe(false);
    expect(hasSafeInAppHistoryBack("https://example.com/previous")).toBe(false);
    expect(hasSafeInAppHistoryBack("//example.com/previous")).toBe(false);
  });
});
