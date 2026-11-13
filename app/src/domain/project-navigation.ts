export interface ProjectBackTarget {
  label: string;
  routeName: string;
}

const projectBackTargets: Record<string, ProjectBackTarget> = {
  "task-create": { label: "返回任务", routeName: "project-tasks" },
  "task-detail": { label: "返回任务列表", routeName: "project-tasks" },
  "file-detail": { label: "返回文件", routeName: "project-files" },
  "review-detail": { label: "返回验收", routeName: "project-reviews" },
  "contribution-detail": {
    label: "返回贡献与报告",
    routeName: "project-contributions",
  },
  "project-members": { label: "返回项目概览", routeName: "project-overview" },
  "project-invitations": {
    label: "返回项目概览",
    routeName: "project-overview",
  },
  "project-contributions": {
    label: "返回项目概览",
    routeName: "project-overview",
  },
  "project-analytics": { label: "返回项目概览", routeName: "project-overview" },
  "project-permissions": { label: "返回成员", routeName: "project-members" },
  "project-integrations": {
    label: "返回项目概览",
    routeName: "project-overview",
  },
  "project-settings": { label: "返回项目概览", routeName: "project-overview" },
};

export function projectBackTarget(routeName: unknown) {
  if (typeof routeName !== "string") return null;
  return projectBackTargets[routeName] ?? null;
}

export function hasSafeInAppHistoryBack(back: unknown) {
  if (typeof back !== "string") return false;
  const trimmed = back.trim();
  return trimmed.startsWith("/") && !trimmed.startsWith("//");
}
