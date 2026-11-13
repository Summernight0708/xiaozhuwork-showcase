import type { CommandFailure, DomainErrorCode } from "@/types/commands";

const DOMAIN_MESSAGES: Record<DomainErrorCode, string> = {
  UNAUTHENTICATED: "登录状态已失效，请重新登录。",
  NOT_FOUND_OR_NOT_AUTHORIZED: "内容不存在，或你没有访问权限。",
  VALIDATION_FAILED: "提交内容不符合要求，请检查后重试。",
  IDEMPOTENCY_KEY_REUSED: "请求标识已用于其他操作，请刷新后重试。",
  INVITE_UNAVAILABLE: "邀请链接不可用或已过期。",
  INVITE_EXHAUSTED: "邀请链接的可用名额已用完。",
  ALREADY_MEMBER: "你已经是该项目成员。",
  JOIN_REQUEST_PENDING: "你的加入申请正在等待审核。",
  TASK_ALREADY_CLAIMED: "任务已被其他成员认领。",
  ASSIGNMENT_NOT_PENDING: "这项任务指派已不再等待响应。",
  STALE_VERSION: "数据已被其他成员更新，已刷新最新内容，请确认后重试。",
  NOT_AUTHORIZED: "你没有执行此操作的权限。",
  INVALID_TRANSITION: "当前状态下不能执行此操作。",
  QUOTA_EXCEEDED: "已达到当前额度上限。",
  ACTIVE_FREE_PROJECT_LIMIT_REACHED: "已达到可参与的 Free 项目数量上限。",
  PROJECT_MEMBER_LIMIT_REACHED: "项目成员数量已达到当前上限。",
  CONCURRENT_TASK_LIMIT_REACHED: "项目并发任务数量已达到当前上限。",
  DDL_NOT_IN_FUTURE: "截止时间必须晚于当前时间。",
  CONFIRMATION_REQUIRED: "该操作需要进一步确认。",
  FEATURE_DISABLED: "该能力当前未启用。",
  UNSAFE_FILE_TYPE: "该文件类型不安全，无法上传。",
  SHARE_EXPIRED: "分享已过期。",
  FILE_TYPE_NOT_ALLOWED: "当前文件类型不允许上传。",
  STORAGE_QUOTA_EXCEEDED: "项目存储空间不足。",
  FILE_VALIDATION_FAILED: "服务端文件校验失败，请检查文件后重试。",
  UPLOAD_NOT_READY: "文件尚未完整上传，请稍后重试。",
  PROJECT_NOT_ACTIVE: "项目当前不是可操作状态。",
  REVIEW_NOT_PENDING: "该验收已被处理，请刷新查看最新结果。",
  REPORT_NOT_READY: "贡献报告尚未准备好。",
};

export function domainErrorMessage(code: string) {
  return DOMAIN_MESSAGES[code as DomainErrorCode] ?? "操作失败，请稍后重试。";
}

export function taskCreateErrorMessage(result: CommandFailure) {
  if (result.code === "NOT_FOUND_OR_NOT_AUTHORIZED") {
    if (result.field === "assigneeId") {
      return "指派成员的项目身份已变化，请刷新成员列表后重试。";
    }
    return "你当前没有在此项目创建任务的权限，成员身份可能已变化。";
  }
  if (result.code === "PROJECT_NOT_ACTIVE") {
    return "项目状态已变化，当前不能再创建任务。";
  }
  if (result.code === "STALE_VERSION") {
    return "项目刚刚发生了变化，请确认最新状态后重新提交。";
  }
  if (result.code === "DDL_NOT_IN_FUTURE" && result.field === "deadlineAt") {
    return "任务截止时间必须晚于当前时间，且不能晚于项目 DDL。";
  }
  return domainErrorMessage(result.code);
}

export function leaveProjectErrorMessage(result: CommandFailure) {
  if (result.code === "INVALID_TRANSITION") {
    if (result.details?.reason === "leader_must_transfer_first") {
      return "请先转让组长身份，再退出项目。";
    }
    if (result.details?.reason === "active_responsibility_requires_handoff") {
      return "你仍负责未完成任务，请先完成或移交后再退出项目。";
    }
  }
  if (result.code === "PROJECT_NOT_ACTIVE") {
    return "项目已进入收口状态，当前不能退出项目。";
  }
  return domainErrorMessage(result.code);
}

export function unknownErrorMessage(error: unknown) {
  if (error instanceof Error && error.name === "CommandTransportError") {
    return "网络或服务暂时不可用，请重试。";
  }
  return "加载失败，请重试。";
}
