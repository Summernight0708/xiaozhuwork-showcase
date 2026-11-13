export type BenefitReleaseStatus =
  "released" | "integration_pending" | "planned";

export interface PlanBenefit {
  name: string;
  free: string;
  pro: string;
  status: BenefitReleaseStatus;
}

export const PLAN_BENEFITS: readonly PlanBenefit[] = [
  {
    name: "活跃 Free 项目",
    free: "最多 5 个",
    pro: "不限",
    status: "released",
  },
  {
    name: "项目成员",
    free: "Free 项目最多 8 人",
    pro: "Pro 项目最多 20 人",
    status: "released",
  },
  {
    name: "并发任务",
    free: "Free 项目最多 20 个",
    pro: "Pro 项目最多 100 个",
    status: "released",
  },
  {
    name: "单文件大小",
    free: "最大 50 MiB / 文件",
    pro: "最大 200 MiB / 文件",
    status: "released",
  },
  {
    name: "项目文件存储空间",
    free: "约 0.5 GiB / 项目",
    pro: "约 5 GiB / 项目",
    status: "released",
  },
  {
    name: "完整文件历史",
    free: "最近 10 个版本",
    pro: "完整版本历史",
    status: "released",
  },
  {
    name: "批量回滚",
    free: "—",
    pro: "支持批量回滚",
    status: "released",
  },
  {
    name: "版本比较",
    free: "—",
    pro: "文件版本比较",
    status: "released",
  },
  {
    name: "项目文件恢复点",
    free: "—",
    pro: "支持项目文件恢复点",
    status: "released",
  },
  {
    name: "增强报告",
    free: "基础报告 / 基础导出",
    pro: "增强报告",
    status: "released",
  },
  {
    name: "高级权限",
    free: "基础项目权限",
    pro: "高级权限控制",
    status: "released",
  },
  {
    name: "项目统计",
    free: "基础视图",
    pro: "高级项目统计",
    status: "released",
  },
  {
    name: "跨项目总览与搜索",
    free: "基础项目列表",
    pro: "跨项目总览与搜索",
    status: "released",
  },
  {
    name: "跨项目汇总与统计",
    free: "—",
    pro: "跨项目汇总与统计",
    status: "released",
  },
  {
    name: "外部集成",
    free: "—",
    pro: "外部工具集成",
    status: "released",
  },
];

const BENEFIT_STATUS_LABELS: Record<BenefitReleaseStatus, string> = {
  released: "已上线",
  integration_pending: "待集成",
  planned: "规划中",
};

export function benefitStatusLabel(status: BenefitReleaseStatus) {
  return BENEFIT_STATUS_LABELS[status];
}

export function shouldShowBenefitStatus(benefits: readonly PlanBenefit[]) {
  return benefits.some((benefit) => benefit.status !== "released");
}
