<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showToast } from "vant";

import AuthLayout from "@/components/auth/AuthLayout.vue";

import { safeReturnPath } from "@/domain/profile-completion";
import { useAuthStore } from "@/stores/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const email = ref("");
const code = ref("");
const password = ref("");
const confirmation = ref("");
const step = ref<"email" | "code" | "password">("email");
const cooldown = ref(0);
let timer: number | undefined;
let completed = false;

const codeValid = computed(() => /^\d{6}$/.test(code.value.trim()));

function startCooldown() {
  window.clearInterval(timer);
  cooldown.value = 60;
  timer = window.setInterval(() => {
    cooldown.value -= 1;
    if (cooldown.value <= 0) window.clearInterval(timer);
  }, 1000);
}

async function requestCode() {
  if (auth.loading || !auth.configured) return;
  const result = await auth.requestRecoveryCode(email.value);
  if (!result.ok) {
    if (result.code === "INVALID_EMAIL") {
      showToast("请输入有效邮箱地址");
      return;
    }
    if (result.code === "RATE_LIMITED") {
      showToast("操作过于频繁，请稍后再试");
      return;
    }
  }
  step.value = "code";
  startCooldown();
  showToast("如果该邮箱存在，我们已发送验证码");
}

async function verifyCode() {
  if (!codeValid.value) {
    showToast("请输入 6 位验证码");
    return;
  }
  const result = await auth.verifyPasswordSetupCode(email.value, code.value);
  if (!result.ok) {
    showToast(
      result.code === "RATE_LIMITED"
        ? "操作过于频繁，请稍后再试"
        : "验证码无效或已过期",
    );
    return;
  }
  step.value = "password";
  code.value = "";
  window.clearInterval(timer);
}

async function savePassword() {
  const result = await auth.setVerifiedPassword(
    password.value,
    confirmation.value,
  );
  if (!result.ok) {
    if (result.code === "PASSWORD_TOO_SHORT") showToast("密码至少需要 8 位");
    else if (result.code === "PASSWORD_MISMATCH")
      showToast("两次输入的密码不一致");
    else {
      showToast("密码更新失败，请重新验证邮箱后再试");
      step.value = "email";
      password.value = "";
      confirmation.value = "";
    }
    return;
  }
  completed = true;
  await router.replace(safeReturnPath(route.query.return));
}

async function resend() {
  if (auth.loading || cooldown.value > 0) return;
  await requestCode();
}

async function changeEmail() {
  window.clearInterval(timer);
  cooldown.value = 0;
  code.value = "";
  if (auth.pendingPasswordSetup) await auth.abortVerifiedAuth();
  step.value = "email";
}

onBeforeUnmount(() => {
  window.clearInterval(timer);
  if (!completed && auth.pendingPasswordSetup) void auth.abortVerifiedAuth();
});
</script>

<template>
  <AuthLayout
    summary="忘记密码时只需要重新验证邮箱。验证码不会成为日常登录方式。"
    note="为了保护账号隐私，页面不会提示某个邮箱是否已经注册。"
    card-labelledby="recover-title"
  >
    <div class="login-card-heading">
      <p class="eyebrow">找回密码</p>
      <h2 id="recover-title">
        {{
          step === "email"
            ? "验证账号邮箱"
            : step === "code"
              ? "输入 6 位验证码"
              : "设置新密码"
        }}
      </h2>
      <p class="muted">
        {{
          step === "email"
            ? "输入邮箱后，我们会返回一致的安全响应。"
            : step === "code"
              ? "验证码有效后才能设置新密码。"
              : "密码至少 8 位。设置完成后旧密码将失效。"
        }}
      </p>
    </div>

    <div v-if="!auth.configured" class="config-warning" role="alert">
      找回密码服务暂时不可用，请稍后再试。
    </div>

    <form
      v-if="step === 'email'"
      class="login-form"
      :aria-busy="auth.loading"
      @submit.prevent="requestCode"
    >
      <van-field
        v-model="email"
        type="email"
        label="邮箱"
        autocomplete="email"
        placeholder="student@example.edu"
      />
      <van-button
        block
        type="primary"
        native-type="submit"
        :loading="auth.loading"
        :disabled="auth.loading || !auth.configured"
        >发送验证码</van-button
      >
    </form>

    <form
      v-else-if="step === 'code'"
      class="login-form"
      :aria-busy="auth.loading"
      @submit.prevent="verifyCode"
    >
      <label class="code-label" for="otp-code">验证码</label>
      <input
        id="otp-code"
        v-model="code"
        class="code-input"
        inputmode="numeric"
        autocomplete="one-time-code"
        maxlength="6"
        placeholder="000000"
      />
      <van-button
        block
        type="primary"
        native-type="submit"
        :loading="auth.loading"
        :disabled="auth.loading || !codeValid"
        >验证邮箱</van-button
      >
      <div class="secondary-actions">
        <button type="button" class="text-action" @click="changeEmail">
          更换邮箱
        </button>
        <button
          type="button"
          class="text-action"
          :disabled="auth.loading || cooldown > 0"
          @click="resend"
        >
          {{ cooldown > 0 ? cooldown + "s 后重发" : "重新发送" }}
        </button>
      </div>
    </form>

    <form
      v-else
      class="login-form"
      :aria-busy="auth.loading"
      @submit.prevent="savePassword"
    >
      <van-field
        v-model="password"
        type="password"
        label="新密码"
        autocomplete="new-password"
        placeholder="至少 8 位"
      />
      <van-field
        v-model="confirmation"
        type="password"
        label="再次输入"
        autocomplete="new-password"
        placeholder="再次输入新密码"
      />
      <van-button
        block
        type="primary"
        native-type="submit"
        :loading="auth.loading"
        :disabled="auth.loading"
        >更新密码</van-button
      >
    </form>

    <p class="login-footnote">
      <RouterLink class="auth-link" :to="{ name: 'login', query: route.query }"
        >返回登录</RouterLink
      >
    </p>
  </AuthLayout>
</template>
