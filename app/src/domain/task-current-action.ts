import type {
  TaskAlertPresentation,
  TaskCurrentAction,
} from "@/types/frontend-integration";

export interface TaskCurrentActionInput {
  pendingChangeConfirmation: boolean;
  pendingCollaborationInvite: boolean;
  canReview: boolean;
  isPrimary: boolean;
  needsChanges: boolean;
  canFinalSubmit: boolean;
  isAcceptedCollaborator: boolean;
  canUpload: boolean;
}

export function selectTaskCurrentAction(
  input: TaskCurrentActionInput,
): TaskCurrentAction | null {
  if (input.pendingChangeConfirmation) {
    return { kind: "confirm-change", label: "查看并确认" };
  }
  if (input.pendingCollaborationInvite) {
    return { kind: "respond-collaboration", label: "响应协作邀请" };
  }
  if (input.canReview) return { kind: "open-review", label: "前往验收" };
  if (input.isPrimary && input.needsChanges && input.canFinalSubmit) {
    return { kind: "resubmit", label: "重新提交" };
  }
  if (input.isPrimary && input.canFinalSubmit) {
    return { kind: "submit-review", label: "提交验收" };
  }
  if (input.isAcceptedCollaborator && input.canUpload) {
    return { kind: "upload-file", label: "上传文件" };
  }
  return null;
}

export function taskDetailAlerts(input: {
  needsChanges?: boolean;
  rejectionReason?: string | null;
  waitingUpstream?: boolean;
  newUpstreamArtifact?: boolean;
  pendingCollaborationInvite?: boolean;
  pendingChangeConfirmation?: boolean;
  activeIssueCount?: number;
}): TaskAlertPresentation[] {
  const alerts: TaskAlertPresentation[] = [];
  if (input.needsChanges) {
    alerts.push({
      id: "needs-changes",
      label: "需要修改",
      detail: input.rejectionReason || undefined,
      tone: "warning",
    });
  }
  if (input.waitingUpstream) {
    alerts.push({
      id: "waiting-upstream",
      label: "等待上游",
      detail: "直接上游任务尚未全部完成。",
      tone: "info",
    });
  }
  if (input.newUpstreamArtifact) {
    alerts.push({
      id: "new-upstream-artifact",
      label: "上游成果有新版本",
      tone: "info",
    });
  }
  if (input.pendingCollaborationInvite) {
    alerts.push({
      id: "pending-collaboration",
      label: "协作邀请待响应",
      tone: "warning",
    });
  }
  if (input.pendingChangeConfirmation) {
    alerts.push({
      id: "pending-change",
      label: "任务变更待确认",
      tone: "warning",
    });
  }
  if ((input.activeIssueCount ?? 0) > 0) {
    alerts.push({
      id: "active-issues",
      label: "协作问题待处理",
      detail: String(input.activeIssueCount) + " 个进行中的求助或返工事项。",
      tone: "warning",
    });
  }
  return alerts;
}
