<script setup lang="ts">
import { ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showToast } from "vant";

import AuthLayout from "@/components/auth/AuthLayout.vue";

import { safeReturnPath } from "@/domain/profile-completion";
import { useAuthStore } from "@/stores/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const email = ref("");
const password = ref("");

function loginErrorMessage(code: string) {
  if (code === "INVALID_EMAIL") return "请输入有效邮箱地址";
  if (code === "INVALID_PASSWORD") return "请输入密码";
  if (code === "RATE_LIMITED") return "操作过于频繁，请稍后再试";
  return "邮箱或密码错误";
}

async function submitLogin() {
  if (auth.loading || !auth.configured) return;
  const result = await auth.loginWithPassword(email.value, password.value);
  if (!result.ok) {
    showToast(loginErrorMessage(result.code));
    return;
  }
  await router.replace(safeReturnPath(route.query.return));
}
</script>

<template>
  <AuthLayout
    summary="从任务分工、文件版本到成果验收与贡献确认，把课程项目里容易丢失的过程放回一条可追溯的协作线上。"
    note="专为课程小组与轻量项目团队设计。"
    card-labelledby="login-title"
  >
    <div class="login-card-heading">
      <p class="eyebrow">账号登录</p>
      <h2 id="login-title">进入你的协作空间</h2>
      <p class="muted">使用邮箱和密码登录。验证码仅用于注册和找回密码。</p>
    </div>

    <div v-if="!auth.configured" class="config-warning" role="alert">
      登录服务暂时不可用。请稍后再试。
    </div>

    <form
      class="login-form"
      :aria-busy="auth.loading"
      @submit.prevent="submitLogin"
    >
      <van-field
        v-model="email"
        type="email"
        label="邮箱"
        autocomplete="email"
        placeholder="student@example.edu"
      />
      <van-field
        v-model="password"
        type="password"
        label="密码"
        autocomplete="current-password"
        placeholder="输入密码"
      />
      <van-button
        block
        type="primary"
        native-type="submit"
        :loading="auth.loading"
        :disabled="auth.loading || !auth.configured"
      >
        登录
      </van-button>
    </form>

    <div class="secondary-actions auth-entry-links">
      <RouterLink
        class="text-action auth-link"
        :to="{ name: 'forgot-password', query: route.query }"
        >忘记密码？</RouterLink
      >
      <RouterLink
        class="text-action auth-link"
        :to="{ name: 'register', query: route.query }"
        >前往注册</RouterLink
      >
    </div>
  </AuthLayout>
</template>
