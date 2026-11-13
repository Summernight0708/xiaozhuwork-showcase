import type { PreviewProjectInviteData } from "@/types/commands";

export function inviteJoinExpectedVersion(
  preview: Pick<PreviewProjectInviteData, "mode" | "invitationVersion">,
) {
  return preview.mode === "approval" ? 0 : preview.invitationVersion;
}

export function inviteJoinCommandSnapshot(
  token: string,
  preview: Pick<PreviewProjectInviteData, "mode" | "invitationVersion">,
) {
  return {
    token,
    expectedVersion: inviteJoinExpectedVersion(preview),
  } as const;
}
