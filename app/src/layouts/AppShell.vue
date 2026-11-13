<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";

import pigLogo from "@/assets/brand/pig.svg";
import { isNativeAndroid } from "@/platform/downloads";
import TaskDetailDrawer from "@/components/task/TaskDetailDrawer.vue";
import { PLAN_BENEFITS } from "@/components/upgrade/planBenefits";
import { ROLE_LABELS } from "@/domain/access-control";
import { vDismissibleDetails } from "@/directives/dismissible-details";
import {
  hasSafeInAppHistoryBack,
  projectBackTarget,
} from "@/domain/project-navigation";
import { useAuthStore } from "@/stores/auth";
import { useNotificationsStore } from "@/stores/notifications";
import { useProjectsStore } from "@/stores/projects";
import { clearSessionScopedState } from "@/stores/session-state";
import { useWorkspaceStore } from "@/stores/workspace";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const notifications = useNotificationsStore();
const projects = useProjectsStore();
const workspace = useWorkspaceStore();
const showDownloadEntry = !isNativeAndroid();
const accountMenuRef = ref<HTMLDetailsElement | null>(null);
const mobileMoreRef = ref<HTMLDetailsElement | null>(null);

watch(
  () => route.fullPath,
  () => {
    if (accountMenuRef.value) accountMenuRef.value.open = false;
    if (mobileMoreRef.value) mobileMoreRef.value.open = false;
    void notifications.load(true);
  },
);

const projectId = computed(() =>
  route.meta.project ? String(route.params.projectId || "") : "",
);
const inProject = computed(() => !!projectId.value);
function phase2NavLabel(name: string, label: string) {
  return PLAN_BENEFITS.find((benefit) => benefit.name === name)?.status ===
    "released"
    ? label
    : `${label} · 待发布`;
}
const projectTitle = computed(
  () =>
    workspace.project?.name ||
    projects.activeItems.find((item) => item.project.id === projectId.value)
      ?.project.name ||
    "当前项目",
);
const accountLabel = computed(
  () => auth.profile?.display_name || auth.user?.email || "账号",
);

const primaryProjectNav = computed(() => {
  if (!projectId.value) return [];
  const id = projectId.value;
  return [
    {
      label: "概览",
      name: "project-overview",
      activeNames: ["project-overview"],
      to: { name: "project-overview", params: { projectId: id } },
    },
    {
      label: "工作",
      name: "project-todos",
      activeNames: ["project-todos"],
      to: { name: "project-todos", params: { projectId: id } },
    },
    {
      label: "任务",
      name: "project-tasks",
      activeNames: ["project-tasks", "task-create", "task-detail"],
      to: { name: "project-tasks", params: { projectId: id } },
    },
    {
      label: "文件",
      name: "project-files",
      activeNames: ["project-files", "file-detail"],
      to: { name: "project-files", params: { projectId: id } },
    },
    {
      label: "验收",
      name: "project-reviews",
      activeNames: ["project-reviews", "review-detail"],
      to: { name: "project-reviews", params: { projectId: id } },
    },
  ];
});

const showLeaderOnlyNavigation = computed(
  () =>
    workspace.project?.id === projectId.value &&
    workspace.membership?.member_state === "active" &&
    workspace.membership?.role === "leader" &&
    workspace.role === "leader",
);

const secondaryProjectNav = computed(() => {
  if (!projectId.value) return [];
  const id = projectId.value;
  return [
    {
      label: "成员",
      name: "project-members",
      activeNames: ["project-members"],
      to: { name: "project-members", params: { projectId: id } },
    },
    {
      label: "邀请",
      name: "project-invitations",
      activeNames: ["project-invitations"],
      to: { name: "project-invitations", params: { projectId: id } },
    },
    {
      label: "贡献与报告",
      name: "project-contributions",
      activeNames: ["project-contributions", "contribution-detail"],
      to: { name: "project-contributions", params: { projectId: id } },
    },
    {
      label: phase2NavLabel("项目统计", "项目统计"),
      name: "project-analytics",
      activeNames: ["project-analytics"],
      to: { name: "project-analytics", params: { projectId: id } },
    },
    ...(showLeaderOnlyNavigation.value
      ? [
          {
            label: phase2NavLabel("高级权限", "高级权限"),
            name: "project-permissions",
            activeNames: ["project-permissions"],
            to: { name: "project-permissions", params: { projectId: id } },
          },
          {
            label: phase2NavLabel("外部集成", "日历订阅"),
            name: "project-integrations",
            activeNames: ["project-integrations"],
            to: { name: "project-integrations", params: { projectId: id } },
          },
        ]
      : []),
    {
      label: "项目设置",
      name: "project-settings",
      activeNames: ["project-settings"],
      to: { name: "project-settings", params: { projectId: id } },
    },
  ];
});

const mobilePrimaryNav = computed(() => primaryProjectNav.value.slice(0, 4));

const mobileContextBackTarget = computed(() => {
  if (route.name === "task-detail") return null;
  return projectBackTarget(route.name);
});

function navActive(activeNames: string[]) {
  return activeNames.includes(String(route.name || ""));
}

async function goMobileContextBack() {
  const target = mobileContextBackTarget.value;
  if (!target || !projectId.value) return;

  if (hasSafeInAppHistoryBack(router.options.history.state.back)) {
    router.back();
    return;
  }

  await router.replace({
    name: target.routeName,
    params: { projectId: projectId.value },
  });
}

async function switchProject(event: Event) {
  const nextId = (event.target as HTMLSelectElement).value;
  if (!nextId) return;
  await router.push({
    name: "project-overview",
    params: { projectId: nextId },
  });
}

async function logout() {
  await auth.logout();
  await router.replace({ name: "login" });
}

onMounted(() => {
  void projects.load();
  void notifications.load();
});

watch(
  () => auth.user?.id ?? null,
  (nextUserId, previousUserId) => {
    if (previousUserId && nextUserId !== previousUserId) {
      clearSessionScopedState();
    }
  },
  { flush: "sync" },
);

watch(
  projectId,
  (id) => {
    if (id) void workspace.loadBase(id);
  },
  { immediate: true },
);
</script>

<template>
  <div class="app-shell">
    <header class="topbar">
      <div class="topbar-inner">
        <RouterLink class="brand" to="/projects" aria-label="小猪作业项目">
          <span class="brand-mark" aria-hidden="true">
            <img :src="pigLogo" alt="" />
          </span>
          <strong>小猪作业</strong>
        </RouterLink>

        <nav class="global-nav" aria-label="全局导航">
          <RouterLink
            to="/projects"
            :class="{ active: route.name === 'projects' }"
          >
            项目
          </RouterLink>
          <RouterLink
            to="/projects/todos"
            :class="{ active: route.name === 'projects-todos' }"
          >
            我的工作
          </RouterLink>
          <RouterLink
            to="/workspace/cross-project"
            :class="{ active: route.name === 'cross-project-overview' }"
          >
            {{ phase2NavLabel("跨项目总览与搜索", "跨项目") }}
          </RouterLink>
          <RouterLink
            to="/upgrade"
            :class="{ active: route.name === 'upgrade' }"
          >
            方案与升级
          </RouterLink>
        </nav>

        <div class="topbar-actions">
          <RouterLink
            v-if="showDownloadEntry"
            class="download-link"
            :class="{ active: route.name === 'download' }"
            to="/download"
          >
            下载客户端
          </RouterLink>
          <RouterLink
            class="notification-link"
            to="/notifications"
            :aria-label="
              notifications.unreadCount > 0
                ? `通知，${notifications.unreadCount} 条未读`
                : '通知'
            "
            :class="{ active: route.name === 'notifications' }"
          >
            <span>通知</span>
            <span
              v-if="notifications.unreadCount > 0"
              class="notification-badge"
              aria-hidden="true"
            >
              {{
                notifications.unreadCount > 99
                  ? "99+"
                  : notifications.unreadCount
              }}
            </span>
          </RouterLink>

          <details
            v-if="auth.user"
            ref="accountMenuRef"
            v-dismissible-details
            class="account-menu"
          >
            <summary aria-label="打开账号菜单">
              <span class="account-avatar" aria-hidden="true">{{
                accountLabel.slice(0, 1).toUpperCase()
              }}</span>
              <span class="account-label">{{ accountLabel }}</span>
              <span aria-hidden="true">⌄</span>
            </summary>
            <nav class="account-panel" aria-label="账号导航">
              <RouterLink to="/profile">个人资料</RouterLink>
              <RouterLink to="/help">使用帮助</RouterLink>
              <RouterLink
                v-if="showDownloadEntry"
                class="account-download-link"
                to="/download"
                >下载 Android 客户端</RouterLink
              >
              <button type="button" @click="logout">退出登录</button>
            </nav>
          </details>
          <RouterLink v-else to="/login">登录</RouterLink>
        </div>
      </div>
    </header>

    <div class="shell-body" :class="{ 'shell-body--project': inProject }">
      <aside v-if="inProject" class="project-sidebar" aria-label="项目导航">
        <div class="project-context">
          <label class="project-switcher">
            <span class="sr-only">切换项目</span>
            <select :value="projectId" @change="switchProject">
              <option
                v-for="item in projects.activeItems"
                :key="item.project.id"
                :value="item.project.id"
              >
                {{ item.project.name }}
              </option>
            </select>
          </label>
          <strong class="project-title">{{ projectTitle }}</strong>
          <span v-if="workspace.membership" class="project-role">
            {{ ROLE_LABELS[workspace.role] }}
          </span>
        </div>

        <nav class="sidebar-nav" aria-label="项目主要导航">
          <RouterLink
            v-for="item in primaryProjectNav"
            :key="item.name"
            :to="item.to"
            :class="{ active: navActive(item.activeNames) }"
          >
            {{ item.label }}
          </RouterLink>
        </nav>

        <div class="sidebar-divider" aria-hidden="true"></div>

        <nav
          class="sidebar-nav sidebar-nav--secondary"
          aria-label="项目管理导航"
        >
          <RouterLink
            v-for="item in secondaryProjectNav"
            :key="item.name"
            :to="item.to"
            :class="{ active: navActive(item.activeNames) }"
          >
            {{ item.label }}
          </RouterLink>
        </nav>
      </aside>

      <main class="shell-main">
        <div
          v-if="inProject && mobileContextBackTarget"
          class="mobile-context-bar"
        >
          <button type="button" @click="goMobileContextBack">
            ← {{ mobileContextBackTarget.label }}
          </button>
        </div>
        <RouterView v-slot="{ Component, route: childRoute }">
          <KeepAlive
            :max="8"
            include="ProjectsView,ProjectsTodosView,ProjectOverviewView,ProjectTodosView,ProjectTasksView,ProjectFilesView,ProjectReviewsView,ProjectContributionsView"
          >
            <component
              :is="Component"
              v-if="childRoute.meta.keepAlive"
              :key="String(childRoute.meta.cacheKey || childRoute.name)"
            />
          </KeepAlive>
          <component
            :is="Component"
            v-if="!childRoute.meta.keepAlive"
            :key="childRoute.fullPath"
          />
        </RouterView>
      </main>
    </div>

    <nav v-if="inProject" class="mobile-project-nav" aria-label="项目移动导航">
      <RouterLink
        v-for="item in mobilePrimaryNav"
        :key="item.name"
        :to="item.to"
        :class="{ active: navActive(item.activeNames) }"
      >
        {{ item.label }}
      </RouterLink>
      <details ref="mobileMoreRef" v-dismissible-details class="mobile-more">
        <summary
          :class="{
            active: [
              ...primaryProjectNav.slice(4),
              ...secondaryProjectNav,
            ].some((item) => navActive(item.activeNames)),
          }"
        >
          更多
        </summary>
        <div class="mobile-more-panel">
          <RouterLink
            v-for="item in [
              ...primaryProjectNav.slice(4),
              ...secondaryProjectNav,
            ]"
            :key="item.name"
            :to="item.to"
            :class="{ active: navActive(item.activeNames) }"
          >
            {{ item.label }}
          </RouterLink>
        </div>
      </details>
    </nav>

    <TaskDetailDrawer />
  </div>
</template>

<style scoped>
.app-shell {
  min-height: 100vh;
  min-height: 100dvh;
  --shell-warm-bg: var(--tu-bg);
  --shell-warm-surface: var(--tu-surface);
  --shell-warm-ink: var(--tu-ink);
  --shell-warm-muted: var(--tu-muted);
  --shell-warm-border: var(--tu-border);
  background: var(--shell-warm-bg);
}

/* Preserve a readable foreground across route transitions and nested views. */
.shell-main {
  color: var(--tu-ink);
}

html[data-native-platform="android"] .topbar {
  padding-top: env(safe-area-inset-top);
}

.topbar {
  position: sticky;
  top: 0;
  z-index: 30;
  border-bottom: 1px solid var(--shell-warm-border);
  background: var(--shell-warm-surface);
}

.topbar-inner {
  width: 100%;
  min-height: 60px;
  margin: 0 auto;
  padding: 0 var(--space-lg);
  display: flex;
  align-items: center;
  gap: 30px;
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: 9px;
  flex: 0 0 auto;
  color: var(--shell-warm-ink);
  font-size: 17px;
  letter-spacing: -0.02em;
}

.brand-mark {
  width: 31px;
  height: 31px;
  display: grid;
  place-items: center;
  border: 1px solid var(--shell-warm-border);
  border-radius: var(--radius-control);
  background: var(--tu-subtle-surface);
}

.brand-mark img {
  width: 19px;
  height: 19px;
}

.global-nav {
  display: flex;
  align-items: stretch;
  align-self: stretch;
  gap: 22px;
}

.global-nav a,
.notification-link {
  position: relative;
  display: inline-flex;
  align-items: center;
  min-height: 44px;
  color: var(--shell-warm-muted);
  font-size: 14px;
}

.global-nav a.active,
.notification-link.active {
  color: var(--shell-warm-ink);
  font-weight: 700;
}

.global-nav a.active::after,
.notification-link.active::after {
  content: "";
  position: absolute;
  right: 0;
  bottom: 0;
  left: 0;
  height: 2px;
  background: var(--shell-warm-ink);
}

.topbar-actions {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 18px;
}

.download-link {
  display: inline-flex;
  align-items: center;
  min-height: 44px;
  padding: 0 3px;
  color: var(--shell-warm-muted);
  font-size: 14px;
  white-space: nowrap;
}

.download-link:hover,
.download-link:focus-visible {
  color: var(--shell-warm-ink);
  text-decoration: underline;
  text-underline-offset: 4px;
}

.notification-link {
  gap: 6px;
}

.notification-badge {
  min-width: 18px;
  height: 18px;
  display: inline-grid;
  place-items: center;
  padding: 0 5px;
  border-radius: 999px;
  background: var(--tu-danger);
  color: var(--color-accent-ink);
  font-size: 11px;
  font-weight: 700;
}

.account-menu {
  position: relative;
}

.account-menu summary {
  min-height: 44px;
  display: inline-flex;
  align-items: center;
  gap: 7px;
  color: var(--shell-warm-muted);
  list-style: none;
  cursor: pointer;
  font-size: 13px;
}

.account-menu summary::-webkit-details-marker,
.mobile-more summary::-webkit-details-marker {
  display: none;
}

.account-avatar {
  width: 29px;
  height: 29px;
  display: grid;
  place-items: center;
  border: 1px solid var(--shell-warm-border);
  border-radius: 50%;
  background: var(--tu-subtle-surface);
  color: var(--shell-warm-ink);
  font-size: 12px;
  font-weight: 750;
}

.account-label {
  max-width: 160px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.account-panel,
.mobile-more-panel {
  position: absolute;
  z-index: 45;
  display: grid;
  padding: 7px;
  border: 1px solid var(--shell-warm-border);
  border-radius: var(--radius-panel);
  background: var(--shell-warm-surface);
  box-shadow: var(--tu-shadow);
}

.account-panel {
  top: 48px;
  right: 0;
  min-width: 170px;
}

.account-panel a,
.account-panel button,
.mobile-more-panel a {
  min-height: 42px;
  display: flex;
  align-items: center;
  padding: 8px 10px;
  border: 0;
  border-radius: var(--radius-control);
  background: transparent;
  color: var(--shell-warm-ink);
  font: inherit;
  font-size: 14px;
  text-align: left;
  cursor: pointer;
}

.account-panel a:hover,
.account-panel button:hover,
.mobile-more-panel a:hover {
  background: var(--tu-subtle-surface);
}

.shell-body {
  min-height: calc(100vh - 61px);
}

.shell-body--project {
  min-width: 0;
  width: 100%;
  margin: 0 auto;
  display: grid;
  grid-template-columns: 248px minmax(0, 1fr);
}

.project-sidebar {
  position: sticky;
  top: 61px;
  align-self: start;
  height: calc(100vh - 61px);
  padding: var(--space-lg) var(--space-sm) var(--space-xl) var(--space-sm);
  border-right: 1px solid var(--shell-warm-border);
  background: var(--shell-warm-bg);
  overflow-y: auto;
}

.project-context {
  display: grid;
  gap: 6px;
  padding: 0 var(--space-sm) var(--space-md);
}

.project-switcher select {
  width: 100%;
  min-height: 28px;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--shell-warm-muted);
  font-size: 12px;
  cursor: pointer;
}

.project-title {
  overflow: hidden;
  color: var(--shell-warm-ink);
  font-size: 14px;
  line-height: 1.35;
  text-overflow: ellipsis;
}

.project-role {
  color: var(--shell-warm-muted);
  font-size: 12px;
}

.sidebar-nav {
  display: grid;
  gap: 2px;
}

.sidebar-nav a {
  position: relative;
  min-height: 38px;
  display: flex;
  align-items: center;
  padding: 7px 12px 7px 15px;
  border-radius: var(--radius-control);
  color: var(--shell-warm-muted);
  font-size: 14px;
}

.sidebar-nav a:hover {
  background: var(--tu-subtle-surface);
  color: var(--shell-warm-ink);
}

.sidebar-nav a.active {
  background: var(--tu-subtle-surface);
  color: var(--shell-warm-ink);
  font-weight: 700;
}

.sidebar-nav a.active::before {
  content: "";
  position: absolute;
  top: 8px;
  bottom: 8px;
  left: 0;
  width: 2px;
  border-radius: 1px;
  background: var(--shell-warm-ink);
}

.sidebar-divider {
  height: 1px;
  margin: 14px 12px;
  background: var(--shell-warm-border);
}

.sidebar-nav--secondary a {
  font-size: 13px;
}

.shell-main {
  min-width: 0;
  width: 100%;
  min-height: calc(100vh - 61px);
}

.mobile-context-bar,
.mobile-project-nav {
  display: none;
}

html[data-theme="dark"] .brand-mark img {
  filter: invert(1);
}
@media (max-width: 767px) {
  .topbar-inner {
    min-height: 56px;
    padding: 0 14px;
    gap: 12px;
  }

  .brand {
    font-size: 16px;
  }

  .brand-mark {
    width: 30px;
    height: 30px;
  }

  .global-nav,
  .account-label {
    display: none;
  }

  .download-link {
    display: none;
  }

  .account-panel .account-download-link {
    display: none;
  }

  .topbar-actions {
    gap: 10px;
  }

  .notification-link {
    padding: 0 4px;
    font-size: 13px;
  }

  .notification-badge {
    min-width: 7px;
    width: 7px;
    height: 7px;
    padding: 0;
    font-size: 0;
    line-height: 0;
  }

  .account-menu summary {
    min-width: 38px;
    justify-content: flex-end;
  }

  .shell-body--project {
    display: block;
    width: 100%;
  }

  .project-sidebar {
    display: none;
  }

  .shell-main {
    min-height: calc(100vh - 56px);
    padding-bottom: calc(70px + env(safe-area-inset-bottom));
  }

  .mobile-context-bar {
    min-height: 44px;
    display: flex;
    align-items: center;
    padding: 4px 14px;
    border-bottom: 1px solid var(--shell-warm-border);
    background: var(--shell-warm-surface);
  }

  .mobile-context-bar button {
    min-height: 36px;
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--shell-warm-ink);
    cursor: pointer;
    font-weight: 700;
  }

  .mobile-context-bar button:hover {
    text-decoration: underline;
  }

  .mobile-project-nav {
    position: fixed;
    z-index: 35;
    right: 0;
    bottom: 0;
    left: 0;
    min-height: calc(64px + env(safe-area-inset-bottom));
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    padding-bottom: env(safe-area-inset-bottom);
    border-top: 1px solid var(--shell-warm-border);
    background: var(--shell-warm-surface);
  }

  .mobile-project-nav > a,
  .mobile-more > summary {
    position: relative;
    min-height: 64px;
    display: grid;
    place-items: center;
    color: var(--shell-warm-muted);
    font-size: 12px;
  }

  .mobile-project-nav > a.active,
  .mobile-more > summary.active {
    color: var(--shell-warm-ink);
    font-weight: 750;
  }

  .mobile-project-nav > a.active::before,
  .mobile-more > summary.active::before {
    content: "";
    position: absolute;
    top: 8px;
    width: 18px;
    height: 2px;
    border-radius: 1px;
    background: var(--shell-warm-ink);
  }

  .mobile-more {
    position: relative;
    min-width: 0;
  }

  .mobile-more summary {
    list-style: none;
    cursor: pointer;
  }

  .mobile-more-panel {
    right: 8px;
    bottom: calc(58px + env(safe-area-inset-bottom));
    min-width: 176px;
  }

  .mobile-more-panel a.active {
    background: var(--tu-subtle-surface);
    font-weight: 700;
  }
}
</style>
