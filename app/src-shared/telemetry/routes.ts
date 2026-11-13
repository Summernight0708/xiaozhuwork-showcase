export interface TelemetryRouteLike {
  name?: string | symbol | null;
  path?: string;
}

export interface TelemetryRouteTemplate {
  url: string;
  title: string;
}

const ROUTE_TEMPLATES: Readonly<Record<string, TelemetryRouteTemplate>> = {
  login: { url: "/login", title: "登录" },
  register: { url: "/register", title: "注册" },
  "forgot-password": { url: "/forgot-password", title: "找回密码" },
  "invite-token": { url: "/invite/:token", title: "邀请加入" },
  download: { url: "/download", title: "下载" },
  "help-center": { url: "/help", title: "使用帮助" },
  "help-article": { url: "/help/:articleId", title: "帮助文章" },
  projects: { url: "/projects", title: "项目列表" },
  "projects-todos": { url: "/workspace/todo", title: "跨项目待办" },
  "cross-project-overview": {
    url: "/workspace/cross-project",
    title: "跨项目工作台",
  },
  "project-create": { url: "/projects/create", title: "创建项目" },
  "project-overview": {
    url: "/projects/:projectId",
    title: "项目概览",
  },
  "project-todos": {
    url: "/projects/:projectId/todos",
    title: "项目待办",
  },
  "project-tasks": {
    url: "/projects/:projectId/tasks",
    title: "项目任务",
  },
  "task-create": {
    url: "/projects/:projectId/tasks/new",
    title: "创建任务",
  },
  "task-detail": {
    url: "/projects/:projectId/tasks/:taskId",
    title: "任务详情",
  },
  "project-files": {
    url: "/projects/:projectId/files",
    title: "项目文件",
  },
  "file-detail": {
    url: "/projects/:projectId/files/:fileId",
    title: "文件详情",
  },
  "project-reviews": {
    url: "/projects/:projectId/reviews",
    title: "项目验收",
  },
  "review-detail": {
    url: "/projects/:projectId/reviews/:reviewRoundId",
    title: "验收详情",
  },
  "project-contributions": {
    url: "/projects/:projectId/contributions",
    title: "项目贡献",
  },
  "contribution-detail": {
    url: "/projects/:projectId/contributions/:reportId",
    title: "贡献详情",
  },
  "project-members": {
    url: "/projects/:projectId/members",
    title: "项目成员",
  },
  "project-analytics": {
    url: "/projects/:projectId/analytics",
    title: "项目统计",
  },
  "project-permissions": {
    url: "/projects/:projectId/permissions",
    title: "项目权限",
  },
  "project-integrations": {
    url: "/projects/:projectId/integrations",
    title: "项目集成",
  },
  "project-invitations": {
    url: "/projects/:projectId/invitations",
    title: "项目邀请",
  },
  "project-settings": {
    url: "/projects/:projectId/settings",
    title: "项目设置",
  },
  notifications: { url: "/notifications", title: "通知" },
  "account-settings": { url: "/account/settings", title: "账号设置" },
  "account-deletion": { url: "/account/deletion", title: "账号注销" },
  upgrade: { url: "/upgrade", title: "方案与升级" },
};

const OTHER_ROUTE: TelemetryRouteTemplate = {
  url: "/other",
  title: "其他页面",
};

export function normalizeRouteTemplate(
  route: TelemetryRouteLike,
): TelemetryRouteTemplate {
  const name = typeof route.name === "string" ? route.name : "";
  return ROUTE_TEMPLATES[name] ?? OTHER_ROUTE;
}
