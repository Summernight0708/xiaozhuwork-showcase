import {
  createRouter,
  createWebHistory,
  type RouteRecordRaw,
} from "vue-router";

import OpsShell from "@ops/layouts/OpsShell.vue";
import { useOpsAuthStore } from "@ops/stores/auth";
import OpsCommercialSystemView from "@ops/views/OpsCommercialSystemView.vue";
import OpsLoginView from "@ops/views/OpsLoginView.vue";
import OpsOverviewView from "@ops/views/OpsOverviewView.vue";
import OpsProjectsView from "@ops/views/OpsProjectsView.vue";
import OpsUsersView from "@ops/views/OpsUsersView.vue";

const routes: RouteRecordRaw[] = [
  {
    path: "/login",
    name: "ops-login",
    component: OpsLoginView,
  },
  {
    path: "/",
    component: OpsShell,
    children: [
      { path: "", name: "ops-overview", component: OpsOverviewView },
      { path: "users", name: "ops-users", component: OpsUsersView },
      { path: "projects", name: "ops-projects", component: OpsProjectsView },
      {
        path: "system",
        name: "ops-system",
        component: OpsCommercialSystemView,
      },
    ],
  },
  { path: "/:pathMatch(.*)*", redirect: { name: "ops-overview" } },
];

export const opsRouter = createRouter({
  history: createWebHistory(),
  routes,
});

opsRouter.beforeEach(async (to) => {
  const auth = useOpsAuthStore();
  await auth.initialize();

  if (to.name === "ops-login") {
    return auth.isAuthorized ? { name: "ops-overview" } : true;
  }
  return auth.isAuthorized ? true : { name: "ops-login" };
});
