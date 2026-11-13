import { createRouter, createWebHistory, type RouterHistory } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { getAccountLifecycleStatus } from "@/features/account-lifecycle/repository";
import {
  profileNeedsCompletion,
  safeReturnPath,
} from "@/domain/profile-completion";

const AppShell = () => import("@/layouts/AppShell.vue");
const LoginView = () => import("@/views/LoginView.vue");
const RegisterView = () => import("@/views/RegisterView.vue");
const ForgotPasswordView = () => import("@/views/ForgotPasswordView.vue");
const DownloadView = () => import("@/views/DownloadView.vue");
const ProjectsView = () => import("@/views/ProjectsView.vue");
const ProjectsTodosView = () => import("@/views/ProjectsTodosView.vue");
const ProjectCreateView = () => import("@/views/ProjectCreateView.vue");
const ProjectOverviewView = () => import("@/views/ProjectOverviewView.vue");
const ProjectTodosView = () => import("@/views/ProjectTodosView.vue");
const ProjectTasksView = () => import("@/views/ProjectTasksView.vue");
const TaskCreateView = () => import("@/views/TaskCreateView.vue");
const AiTaskBreakdownView = () => import("@/views/AiTaskBreakdownView.vue");
const TaskDetailPage = () => import("@/views/TaskDetailPage.vue");
const ProjectFilesView = () => import("@/views/ProjectFilesView.vue");
const ProjectReviewsView = () => import("@/views/ProjectReviewsView.vue");
const ProjectContributionsView = () =>
  import("@/views/ProjectContributionsView.vue");
const ProjectMembersView = () => import("@/views/ProjectMembersView.vue");
const ProjectInvitationsView = () =>
  import("@/views/ProjectInvitationsView.vue");
const ProjectSettingsView = () => import("@/views/ProjectSettingsView.vue");
const InviteTokenView = () => import("@/views/InviteTokenView.vue");
const NotificationsView = () => import("@/views/NotificationsView.vue");
const SettingsView = () => import("@/views/SettingsView.vue");
const AccountDeletionView = () => import("@/views/AccountDeletionView.vue");
const UpgradeView = () => import("@/views/UpgradeView.vue");
const ProjectAnalyticsView = () => import("@/views/ProjectAnalyticsView.vue");
const ProjectPermissionsView = () =>
  import("@/views/ProjectPermissionsView.vue");
const ProjectIntegrationsView = () =>
  import("@/views/ProjectIntegrationsView.vue");
const CrossProjectOverviewView = () =>
  import("@/views/CrossProjectOverviewView.vue");
const HelpCenterView = () => import("@/views/HelpCenterView.vue");
const HelpArticleView = () => import("@/views/HelpArticleView.vue");

export function createAppRouter(history: RouterHistory = createWebHistory()) {
  const router = createRouter({
    history,
    routes: [
      {
        path: "/login",
        name: "login",
        component: LoginView,
        meta: { public: true, bare: true },
      },
      {
        path: "/register",
        name: "register",
        component: RegisterView,
        meta: { public: true, bare: true },
      },
      {
        path: "/forgot-password",
        name: "forgot-password",
        component: ForgotPasswordView,
        meta: { public: true, bare: true },
      },
      {
        path: "/invite/:token",
        name: "invite-token",
        component: InviteTokenView,
        meta: { public: true, bare: true },
      },
      {
        path: "/",
        component: AppShell,
        children: [
          { path: "", redirect: "/projects" },
          {
            path: "download",
            name: "download",
            component: DownloadView,
            meta: { public: true },
          },
          {
            path: "help",
            name: "help-center",
            component: HelpCenterView,
          },
          {
            path: "help/:articleId",
            name: "help-article",
            component: HelpArticleView,
          },
          {
            path: "projects",
            name: "projects",
            component: ProjectsView,
            meta: { keepAlive: true },
          },
          {
            path: "workspace/todo",
            alias: "/projects/todos",
            name: "projects-todos",
            component: ProjectsTodosView,
            meta: { keepAlive: true },
          },
          {
            path: "workspace/cross-project",
            name: "cross-project-overview",
            component: CrossProjectOverviewView,
          },
          {
            path: "projects/create",
            name: "project-create",
            component: ProjectCreateView,
          },
          {
            path: "projects/:projectId",
            name: "project-overview",
            component: ProjectOverviewView,
            meta: { keepAlive: true, project: true },
          },
          {
            path: "projects/:projectId/todos",
            name: "project-todos",
            component: ProjectTodosView,
            meta: { keepAlive: true, project: true },
          },
          {
            path: "projects/:projectId/tasks",
            name: "project-tasks",
            component: ProjectTasksView,
            meta: { keepAlive: true, project: true },
          },
          {
            path: "projects/:projectId/tasks/new",
            name: "task-create",
            component: TaskCreateView,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/ai-breakdown",
            name: "ai-task-breakdown",
            component: AiTaskBreakdownView,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/tasks/:taskId",
            name: "task-detail",
            component: TaskDetailPage,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/files",
            name: "project-files",
            component: ProjectFilesView,
            meta: { keepAlive: true, project: true, cacheKey: "project-files" },
          },
          {
            path: "projects/:projectId/files/:fileId",
            name: "file-detail",
            component: ProjectFilesView,
            meta: { keepAlive: true, project: true, cacheKey: "project-files" },
          },
          {
            path: "projects/:projectId/reviews",
            name: "project-reviews",
            component: ProjectReviewsView,
            meta: {
              keepAlive: true,
              project: true,
              cacheKey: "project-reviews",
            },
          },
          {
            path: "projects/:projectId/reviews/:reviewRoundId",
            name: "review-detail",
            component: ProjectReviewsView,
            meta: {
              keepAlive: true,
              project: true,
              cacheKey: "project-reviews",
            },
          },
          {
            path: "projects/:projectId/contributions",
            name: "project-contributions",
            component: ProjectContributionsView,
            meta: {
              keepAlive: true,
              project: true,
              cacheKey: "project-contributions",
            },
          },
          {
            path: "projects/:projectId/contributions/:reportId",
            name: "contribution-detail",
            component: ProjectContributionsView,
            meta: {
              keepAlive: true,
              project: true,
              cacheKey: "project-contributions",
            },
          },
          {
            path: "projects/:projectId/members",
            name: "project-members",
            component: ProjectMembersView,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/analytics",
            name: "project-analytics",
            component: ProjectAnalyticsView,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/permissions",
            name: "project-permissions",
            component: ProjectPermissionsView,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/integrations",
            name: "project-integrations",
            component: ProjectIntegrationsView,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/invitations",
            name: "project-invitations",
            component: ProjectInvitationsView,
            meta: { project: true },
          },
          {
            path: "projects/:projectId/settings",
            name: "project-settings",
            component: ProjectSettingsView,
            meta: { project: true },
          },
          {
            path: "notifications",
            name: "notifications",
            component: NotificationsView,
          },
          {
            path: "account/settings",
            name: "account-settings",
            component: SettingsView,
          },
          {
            path: "account/deletion",
            name: "account-deletion",
            component: AccountDeletionView,
          },
          {
            path: "upgrade",
            name: "upgrade",
            component: UpgradeView,
          },
          {
            path: "profile",
            redirect: (to) => ({
              name: "account-settings",
              query: to.query,
            }),
          },
          {
            path: "settings",
            redirect: (to) => ({
              name: "account-settings",
              query: to.query,
            }),
          },
        ],
      },
      { path: "/:pathMatch(.*)*", redirect: "/projects" },
    ],
    scrollBehavior(to, _from, savedPosition) {
      if (savedPosition) return savedPosition;
      if (to.meta.keepAlive) return false;
      return { top: 0 };
    },
  });

  router.beforeEach(async (to) => {
    const auth = useAuthStore();
    await auth.initialize();

    if (!auth.isAuthenticated) {
      if (to.meta.public) return true;
      return {
        name: "login",
        query: { return: to.fullPath },
      };
    }

    if (["login", "register", "forgot-password"].includes(String(to.name))) {
      return safeReturnPath(to.query.return);
    }

    // Default OFF until legal-retention and irreversible privacy release gates.
    const accountDeletionEnabled =
      import.meta.env.VITE_ACCOUNT_DELETION_ENABLED === "true";
    if (to.name === "account-deletion") {
      return accountDeletionEnabled ? true : { name: "account-settings" };
    }
    if (accountDeletionEnabled) {
      const lifecycle = await getAccountLifecycleStatus().catch(() => null);
      if (lifecycle && !["active", "canceled"].includes(lifecycle.state)) {
        return { name: "account-deletion" };
      }
    }

    const incomplete = profileNeedsCompletion(auth.profile);
    const completingProfile =
      to.name === "account-settings" && to.query.mode === "complete";

    if (incomplete && !completingProfile) {
      return {
        name: "account-settings",
        query: {
          mode: "complete",
          return:
            to.fullPath === "/account/settings" ? "/projects" : to.fullPath,
        },
      };
    }

    if (!incomplete && completingProfile) {
      return safeReturnPath(to.query.return);
    }

    return true;
  });

  return router;
}

export const router = createAppRouter();
