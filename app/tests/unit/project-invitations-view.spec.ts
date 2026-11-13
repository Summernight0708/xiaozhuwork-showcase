import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  reload: vi.fn(),
  workspace: {
    project: { id: "project-1", name: "数据库课程设计" },
    membership: { id: "membership-1" },
    capabilities: { canManageInvites: true },
    pendingAction: null,
    actionError: null,
    loading: false,
    error: null,
    joinRequests: [
      {
        id: "join-1",
        invitation_id: "invite-1",
        project_id: "project-1",
        user_id: "11111111-1111-1111-1111-111111111111",
        display_name_snapshot: "小林",
        state: "pending",
        version: 1,
        reviewed_by: null,
        reviewed_at: null,
        created_at: "2026-10-04T03:00:00.000Z",
        updated_at: "2026-10-04T03:00:00.000Z",
      },
      {
        id: "join-2",
        invitation_id: "invite-1",
        project_id: "project-1",
        user_id: "22222222-2222-2222-2222-222222222222",
        display_name_snapshot: null,
        state: "pending",
        version: 1,
        reviewed_by: null,
        reviewed_at: null,
        created_at: "2026-10-04T04:00:00.000Z",
        updated_at: "2026-10-04T04:00:00.000Z",
      },
    ],
    loadInvitations: vi.fn().mockResolvedValue(undefined),
    createInvite: vi.fn(),
    renewInvite: vi.fn(),
    revokeInvite: vi.fn(),
    reviewJoinRequest: vi.fn(),
  },
}));

vi.mock("@/composables/useWorkspaceRoute", () => ({
  useWorkspaceRoute: () => ({
    workspace: mocks.workspace,
    reload: mocks.reload,
  }),
}));

import ProjectInvitationsView from "@/views/ProjectInvitationsView.vue";

describe("ProjectInvitationsView applicant identity", () => {
  it("shows the applicant display-name snapshot without exposing internal user ids", () => {
    const wrapper = mount(ProjectInvitationsView, {
      global: {
        stubs: {
          PageState: { template: "<div><slot /></div>" },
          ActiveInviteLinkCard: true,
          "van-button": { template: "<button><slot /></button>" },
        },
      },
    });

    expect(wrapper.text()).toContain("小林");
    expect(wrapper.text()).toContain("未设置昵称的申请者");
    expect(wrapper.text()).toContain("申请加入");
    expect(wrapper.text()).not.toContain(
      "11111111-1111-1111-1111-111111111111",
    );
    expect(wrapper.text()).not.toContain(
      "22222222-2222-2222-2222-222222222222",
    );
  });
});
