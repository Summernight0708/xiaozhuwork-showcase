import { App } from "@capacitor/app";
import { showToast } from "vant";
import type { Router } from "vue-router";

import {
  hasSafeInAppHistoryBack,
  projectBackTarget,
} from "@/domain/project-navigation";
import { installExternalLinkGuard } from "@/platform/external-links";
import { isNativeAndroid } from "@/platform/downloads";
import { runNativeBackHandlers } from "@/platform/native-back";

const EXIT_CONFIRM_WINDOW_MS = 1_800;
const directExitRoutes = new Set(["projects", "login", "download"]);
let lastExitBackAt = 0;
let initialized = false;

async function routeBack(router: Router, canGoBack: boolean): Promise<boolean> {
  const back = router.options.history.state.back;
  if (hasSafeInAppHistoryBack(back)) {
    router.back();
    return true;
  }

  const current = router.currentRoute.value;
  const projectId = current.params.projectId;
  const fallback = projectBackTarget(current.name);
  if (fallback && typeof projectId === "string") {
    await router.replace({ name: fallback.routeName, params: { projectId } });
    return true;
  }

  if (canGoBack && window.history.length > 1) {
    router.back();
    return true;
  }

  if (!directExitRoutes.has(String(current.name ?? ""))) {
    await router.replace({ name: "projects" });
    return true;
  }
  return false;
}

export async function initializeNativeApp(router: Router): Promise<void> {
  if (!isNativeAndroid() || initialized) return;
  initialized = true;
  document.documentElement.dataset.nativePlatform = "android";
  installExternalLinkGuard();

  await App.addListener("backButton", async ({ canGoBack }) => {
    if (await runNativeBackHandlers()) {
      lastExitBackAt = 0;
      return;
    }
    if (await routeBack(router, canGoBack)) {
      lastExitBackAt = 0;
      return;
    }

    const now = Date.now();
    if (now - lastExitBackAt <= EXIT_CONFIRM_WINDOW_MS) {
      lastExitBackAt = 0;
      await App.exitApp();
      return;
    }
    lastExitBackAt = now;
    showToast("再按一次返回退出小猪作业");
  });

  await App.addListener("appStateChange", ({ isActive }) => {
    window.dispatchEvent(
      new CustomEvent("xiaozhu:app-state-change", { detail: { isActive } }),
    );
  });

  await App.addListener("appRestoredResult", (result) => {
    window.dispatchEvent(
      new CustomEvent("xiaozhu:app-restored-result", { detail: result }),
    );
  });
}
