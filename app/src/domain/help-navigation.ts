import type { ProjectCapabilities, ProjectRole } from "@/domain/access-control";
import type { HelpArticle } from "@/content/help/articles";

type RouteTarget = { name: string; params?: { projectId: string } };
export type HelpDestination =
  | { kind: "navigate"; to: RouteTarget; label: string }
  | { kind: "choose-project"; reason: string }
  | { kind: "upgrade"; reason: string }
  | { kind: "unavailable"; reason: string };

const globalRoutes = new Set([
  "projects",
  "project-create",
  "notifications",
  "account-settings",
  "upgrade",
  "cross-project-overview",
]);
const knownRoutes = new Set([
  ...globalRoutes,
  "project-overview",
  "project-todos",
  "project-tasks",
  "project-files",
  "project-reviews",
  "project-contributions",
  "project-members",
  "project-settings",
  "project-analytics",
  "project-permissions",
  "project-integrations",
  "project-invitations",
]);

export interface HelpActionContext {
  projectId: string | null;
  activeMember: boolean;
  role: ProjectRole;
  capabilities: ProjectCapabilities;
  pro: boolean;
  archived: boolean;
  released: boolean;
}

export function resolveHelpDestination(
  article: HelpArticle,
  context: HelpActionContext,
): HelpDestination {
  if (article.status !== "released" || !context.released) {
    return { kind: "unavailable", reason: "该功能目前尚未在当前环境发布。" };
  }
  if (!knownRoutes.has(article.routeName)) {
    return { kind: "unavailable", reason: "找不到该功能的安全操作入口。" };
  }
  if (
    article.routeName === "upgrade" ||
    article.routeName === "account-settings" ||
    article.routeName === "notifications" ||
    article.routeName === "projects" ||
    article.routeName === "project-create"
  ) {
    return {
      kind: "navigate",
      to: { name: article.routeName },
      label: "前往对应页面",
    };
  }
  if (!context.projectId || !context.activeMember) {
    return { kind: "choose-project", reason: "请先选择一个你可以访问的项目。" };
  }
  if (article.pro && !context.pro) {
    return {
      kind: "upgrade",
      reason: "可阅读完整教程，实际使用需要当前有效的 Pro 权益。",
    };
  }
  if (article.routeName === "cross-project-overview") {
    return {
      kind: "navigate",
      to: { name: article.routeName },
      label: "前往跨项目总览",
    };
  }
  if (article.minimumRole === "leader" && context.role !== "leader") {
    return {
      kind: "unavailable",
      reason: "这项管理操作要求当前项目组长权限。",
    };
  }
  const capabilityForRoute: Partial<Record<string, keyof ProjectCapabilities>> =
    {
      "project-tasks": undefined,
      "project-invitations": "canManageInvites",
      "project-settings": "canUpdateProjectSettings",
      "project-permissions": "canUpdateProjectSettings",
    };
  const requirement = capabilityForRoute[article.routeName];
  if (requirement && !context.capabilities[requirement]) {
    return {
      kind: "unavailable",
      reason: "当前项目角色没有执行该操作的权限。",
    };
  }
  if (context.archived && (article.minimumRole === "leader" || requirement)) {
    return { kind: "unavailable", reason: "项目已归档，相关操作可能不可用。" };
  }
  return {
    kind: "navigate",
    to: { name: article.routeName, params: { projectId: context.projectId } },
    label: "前往对应页面（实际操作仍须验权）",
  };
}
