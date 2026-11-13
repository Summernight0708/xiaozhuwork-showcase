const STATUS_LABELS: Record<string, string> = {
  claimable: "待认领",
  pending_acceptance: "待接受",
  assigned: "已分配",
  pending: "待处理",
  not_started: "待开始",
  todo: "待开始",
  in_progress: "进行中",
  waiting_upstream: "等待上游",
  blocked: "阻塞",
  awaiting_review: "待验收",
  under_review: "审核中",
  completed: "已完成",
  completed_without_review: "无需验收 · 已完成",
  canceled: "已取消",
  approved: "已通过",
  rejected: "已拒绝",
  request_changes: "需修改",
  draft: "草稿",
  formal: "已正式确认",
  active: "进行中",
  inactive: "未启用",
  reserved: "待最终化",
  finalized: "已最终化",
  archived: "已归档",
  open: "待处理",
  withdrawn: "已撤回",
  abandoned: "已放弃",
  submitted: "已提交",
  accepted: "已接受",
  declined: "已拒绝",
  expired: "已过期",
  revoked: "已撤销",
  canceled_by_owner: "已取消",
};

const REVIEW_LABELS: Record<string, string> = {
  pending: "待验收",
  awaiting_review: "待验收",
  approved: "已通过",
  accepted: "已通过",
  rejected: "已拒绝",
  request_changes: "需修改",
  changes_requested: "需修改",
  superseded: "已被后续轮次替代",
  canceled: "已取消",
};

export function displayStatusLabel(
  value: string | null | undefined,
  fallback = "状态待确认",
): string {
  const key = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!key) return fallback;
  return STATUS_LABELS[key] ?? fallback;
}

export function displayReviewLabel(
  decision: string | null | undefined,
  state?: string | null,
): string {
  const decisionKey = String(decision ?? "")
    .trim()
    .toLowerCase();
  if (decisionKey && REVIEW_LABELS[decisionKey])
    return REVIEW_LABELS[decisionKey];
  const stateKey = String(state ?? "")
    .trim()
    .toLowerCase();
  if (stateKey && REVIEW_LABELS[stateKey]) return REVIEW_LABELS[stateKey];
  return displayStatusLabel(decisionKey || stateKey, "验收状态待确认");
}

export function displayMemberStateLabel(
  value: string | null | undefined,
): string {
  const key = String(value ?? "")
    .trim()
    .toLowerCase();
  if (key === "active") return "正常";
  if (key === "left") return "已退出";
  if (key === "removed") return "已移除";
  if (key === "pending") return "待加入";
  return "成员状态待确认";
}
