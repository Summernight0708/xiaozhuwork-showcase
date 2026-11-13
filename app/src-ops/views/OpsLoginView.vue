<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";

import { useOpsAuthStore } from "@ops/stores/auth";

const auth = useOpsAuthStore();
const router = useRouter();
const email = ref("");
const password = ref("");
const error = ref("");

async function submit() {
  error.value = "";
  const result = await auth.login(email.value, password.value);
  if (result.ok) {
    await router.replace({ name: "ops-overview" });
    return;
  }
  error.value =
    result.code === "FORBIDDEN"
      ? "该 XiaozhuWork 账号没有内部运营权限。"
      : result.code === "UNAUTHENTICATED"
        ? "邮箱或密码错误。"
        : "登录暂时不可用。";
}
</script>

<template>
  <main class="ops-login">
    <section class="ops-login__intro">
      <p class="ops-eyebrow">XiaozhuWork 内部运营</p>
      <h1>看业务事实，不看用户内容。</h1>
      <p>
        这里用于 Beta 运营、产品指标和精确账号支持。普通项目角色与 Pro
        权益都不会授予访问权限。
      </p>
    </section>

    <form class="ops-login__form" @submit.prevent="submit">
      <h2>内部登录</h2>
      <label for="ops-email">邮箱</label>
      <input
        id="ops-email"
        v-model="email"
        type="email"
        autocomplete="username"
        required
      />
      <label for="ops-password">密码</label>
      <input
        id="ops-password"
        v-model="password"
        type="password"
        autocomplete="current-password"
        required
      />
      <p v-if="error" class="form-error" role="alert">{{ error }}</p>
      <button type="submit" :disabled="auth.loading">
        {{ auth.loading ? "验证中…" : "登录 Ops" }}
      </button>
    </form>
  </main>
</template>
