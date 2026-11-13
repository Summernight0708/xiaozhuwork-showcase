import { describe, expect, it } from "vitest";
import { capabilitiesForRole } from "@/domain/access-control";
import { findHelpArticle } from "@/content/help/articles";
import { resolveHelpDestination } from "@/domain/help-navigation";
const help = (id: string) => findHelpArticle(id)!;
function ctx(
  overrides: Partial<Parameters<typeof resolveHelpDestination>[1]> = {},
): Parameters<typeof resolveHelpDestination>[1] {
  return {
    projectId: "project-1",
    activeMember: true,
    role: "leader",
    capabilities: capabilitiesForRole("leader"),
    pro: true,
    archived: false,
    released: true,
    ...overrides,
  };
}
describe("help destination security", () => {
  it("rejects unseen projects and higher-privilege links", () => {
    expect(
      resolveHelpDestination(help("task-create"), ctx({ activeMember: false }))
        .kind,
    ).toBe("choose-project");
    expect(
      resolveHelpDestination(
        help("project-settings"),
        ctx({
          role: "observer",
          capabilities: capabilitiesForRole("observer"),
        }),
      ).kind,
    ).toBe("unavailable");
  });
  it("blocks unreleased actions and free pro CTAs", () => {
    expect(
      resolveHelpDestination(help("advanced-permissions"), ctx({ pro: false }))
        .kind,
    ).toBe("upgrade");
    expect(
      resolveHelpDestination(help("calendar"), ctx({ released: false })).kind,
    ).toBe("unavailable");
    expect(
      resolveHelpDestination(help("dependencies"), ctx({ projectId: null }))
        .kind,
    ).toBe("choose-project");
  });
  it("navigates only via known existing route names", () => {
    expect(resolveHelpDestination(help("submission"), ctx())).toEqual({
      kind: "navigate",
      to: { name: "project-tasks", params: { projectId: "project-1" } },
      label: expect.any(String),
    });
  });
});
