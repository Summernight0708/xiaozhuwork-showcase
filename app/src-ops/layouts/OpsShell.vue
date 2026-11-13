<script setup lang="ts">
import { RouterLink, RouterView, useRouter } from "vue-router";

import { useOpsAuthStore } from "@ops/stores/auth";

const auth = useOpsAuthStore();
const router = useRouter();

const nav = [
  { to: { name: "ops-overview" }, label: "总览" },
  { to: { name: "ops-users" }, label: "用户与使用" },
  { to: { name: "ops-projects" }, label: "项目与协作" },
  { to: { name: "ops-system" }, label: "商业与系统" },
] as const;

async function logout() {
  await auth.logout();
  await router.replace({ name: "ops-login" });
}
</script>

<template>
  <div class="ops-shell">
    <aside class="ops-sidebar">
      <div class="ops-sidebar__brand">
        <strong>XiaozhuWork Ops</strong>
        <span>内部运营</span>
      </div>
      <nav class="ops-nav" aria-label="运营后台导航">
        <RouterLink
          v-for="item in nav"
          :key="item.label"
          :to="item.to"
          class="ops-nav__link"
        >
          {{ item.label }}
        </RouterLink>
      </nav>
      <button class="ops-sidebar__logout" type="button" @click="logout">
        退出内部后台
      </button>
    </aside>
    <main class="ops-main">
      <RouterView />
    </main>
  </div>
</template>
