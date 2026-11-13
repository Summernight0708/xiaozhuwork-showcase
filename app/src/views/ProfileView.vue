<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import {
  displayNameError,
  normalizeDisplayName,
  safeReturnPath,
} from "@/domain/profile-completion";
import { useAuthStore } from "@/stores/auth";

const auth = useAuthStore();
const route = useRoute();
const router = useRouter();
const displayName = ref("");
const realName = ref("");
const studentNumber = ref("");
const nextEmail = ref("");
const saving = ref(false);
const changingEmail = ref(false);
const profileError = ref("");
const completionMode = computed(() => route.query.mode === "complete");
const returnTarget = computed(() => safeReturnPath(route.query.return));

function sync() {
  displayName.value = auth.profile?.display_name ?? "";
  realName.value = auth.profile?.real_name ?? "";
  studentNumber.value = auth.profile?.student_number ?? "";
  nextEmail.value = auth.user?.email ?? "";
}

async function save() {
  profileError.value = displayNameError(displayName.value) ?? "";
  if (profileError.value) return;

  saving.value = true;
  try {
    if (completionMode.value) {
      await auth.saveDisplayName(normalizeDisplayName(displayName.value));
      showToast("昵称已保存");
      await router.replace(returnTarget.value);
      return;
    }
    await auth.saveProfile({
      displayName: normalizeDisplayName(displayName.value),
      realName: realName.value,
      studentNumber: studentNumber.value,
    });
    showToast("资料已保存");
  } catch {
    profileError.value = "资料保存失败，请重试。";
    showToast("资料保存失败");
  } finally {
    saving.value = false;
  }
}

async function changeEmail() {
  const normalized = nextEmail.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
    showToast("请输入有效邮箱地址");
    return;
  }
  if (normalized === auth.user?.email) {
    showToast("邮箱没有变化");
    return;
  }
  changingEmail.value = true;
  try {
    const result = await auth.requestEmailChange(normalized);
    showToast(
      result.ok
        ? "确认邮件已发送，请按邮件提示完成邮箱修改"
        : "邮箱修改请求失败",
    );
  } finally {
    changingEmail.value = false;
  }
}

watch(() => [auth.profile, auth.user], sync, { immediate: true });
onMounted(() => void auth.refreshProfile());
</script>

<template>
  <div class="xiaozhuwork-page profile-page">
    <header class="page-heading">
      <div>
        <h1>{{ completionMode ? "欢迎" : "我的资料" }}</h1>
        <p>
          {{
            completionMode
              ? "先告诉大家怎么称呼你。"
              : "管理用于小猪作业协作中的本人资料，不作为公开社交主页。"
          }}
        </p>
      </div>
    </header>

    <PageState
      :loading="!auth.initialized"
      :error="auth.error"
      :empty="!auth.user"
      empty-title="当前没有登录账号"
    >
      <template v-if="auth.user">
        <section
          v-if="completionMode"
          class="surface completion-card"
          aria-labelledby="nickname-completion-title"
        >
          <p class="completion-brand" aria-hidden="true">🐷 小猪作业</p>
          <h2 id="nickname-completion-title">欢迎</h2>
          <p class="muted">先告诉大家怎么称呼你。</p>
          <form class="completion-form" @submit.prevent="save">
            <label for="completion-display-name">昵称</label>
            <input
              id="completion-display-name"
              v-model="displayName"
              autocomplete="nickname"
              maxlength="30"
              placeholder="小林"
              :aria-invalid="!!profileError"
              :aria-describedby="
                profileError ? 'completion-name-error' : undefined
              "
            />
            <p
              v-if="profileError"
              id="completion-name-error"
              class="profile-error"
              role="alert"
            >
              {{ profileError }}
            </p>
            <p class="privacy-note">你可以之后在账户设置中修改。</p>
            <div class="form-actions">
              <van-button type="primary" native-type="submit" :loading="saving">
                继续
              </van-button>
            </div>
          </form>
        </section>

        <template v-else>
          <section class="surface profile-card">
            <div class="avatar-large">
              {{
                (displayName || auth.user.email || "T")
                  .slice(0, 1)
                  .toUpperCase()
              }}
            </div>
            <div>
              <h2>{{ displayName || "设置显示名称" }}</h2>
              <p>{{ auth.user.email }}</p>
            </div>
          </section>

          <section class="surface form-section">
            <h2>协作资料</h2>
            <van-field
              v-model="displayName"
              label="显示名称"
              maxlength="30"
              placeholder="项目成员看到的名称"
            />
            <van-field
              v-model="realName"
              label="真实姓名"
              maxlength="80"
              placeholder="仅在项目规则要求时使用"
            />
            <van-field
              v-model="studentNumber"
              label="学号"
              maxlength="40"
              placeholder="仅在项目规则要求时使用"
            />
            <div class="privacy-note">
              真实姓名与学号的可见性仍由实际项目权限与后端规则决定，不会被当作贡献或信誉指标。
            </div>
            <p v-if="profileError" class="profile-error" role="alert">
              {{ profileError }}
            </p>
            <div class="form-actions">
              <van-button type="primary" :loading="saving" @click="save"
                >保存资料</van-button
              >
            </div>
          </section>

          <section class="surface form-section">
            <h2>登录邮箱</h2>
            <p class="muted">
              小猪作业 当前使用邮箱 OTP
              登录，不提供密码管理。邮箱修改入口只在本页出现。
            </p>
            <van-field
              v-model="nextEmail"
              type="email"
              label="邮箱"
              autocomplete="email"
            />
            <div class="form-actions">
              <van-button
                plain
                type="primary"
                :loading="changingEmail"
                @click="changeEmail"
                >申请修改邮箱</van-button
              >
            </div>
          </section>

          <section class="surface form-section account-facts">
            <h2>账号基础信息</h2>
            <dl>
              <div>
                <dt>创建时间</dt>
                <dd>
                  {{
                    auth.user.created_at
                      ? new Date(auth.user.created_at).toLocaleString()
                      : "—"
                  }}
                </dd>
              </div>
              <div>
                <dt>最近登录</dt>
                <dd>
                  {{
                    auth.user.last_sign_in_at
                      ? new Date(auth.user.last_sign_in_at).toLocaleString()
                      : "—"
                  }}
                </dd>
              </div>
            </dl>
          </section>
        </template>
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.completion-card {
  max-width: 560px;
  margin: 0 auto;
  padding: 30px;
}
.completion-brand {
  margin: 0 0 18px;
  color: var(--tu-blue-strong);
  font-weight: 800;
}
.completion-card h2 {
  margin: 0;
  font-size: 28px;
}
.completion-card > .muted {
  margin: 8px 0 24px;
}
.completion-form {
  display: grid;
  gap: 10px;
}
.completion-form label {
  font-weight: 700;
}
.completion-form input {
  min-height: 46px;
  padding: 0 12px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  font: inherit;
}
.completion-form input:focus-visible {
  outline: 2px solid var(--tu-blue);
  outline-offset: 2px;
}
.profile-error {
  margin: 8px 0 0;
  color: var(--van-danger-color);
  font-size: 13px;
}

.profile-page {
  max-width: 940px;
}
.profile-card {
  display: flex;
  align-items: center;
  gap: 18px;
  padding: 22px;
  margin-bottom: 16px;
}
.avatar-large {
  width: 68px;
  height: 68px;
  display: grid;
  place-items: center;
  border-radius: 22px;
  background: var(--tu-blue);
  color: white;
  font-size: 29px;
  font-weight: 850;
}
.profile-card h2,
.profile-card p {
  margin: 0;
}
.profile-card p {
  margin-top: 5px;
  color: var(--tu-muted);
}
.form-section {
  padding: 22px;
  margin-bottom: 16px;
}
.form-section h2 {
  margin: 0 0 14px;
  font-size: 18px;
}
.privacy-note {
  margin-top: 12px;
  padding: 12px;
  border-radius: 9px;
  background: var(--tu-subtle-surface);
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.5;
}
.form-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 16px;
}
.account-facts dl {
  margin: 0;
}
.account-facts dl div {
  display: grid;
  grid-template-columns: 150px 1fr;
  gap: 12px;
  padding: 11px 0;
  border-top: 1px solid var(--tu-border);
}
.account-facts dt {
  color: var(--tu-muted);
}
.account-facts dd {
  margin: 0;
  word-break: break-all;
}
@media (max-width: 600px) {
  .account-facts dl div {
    grid-template-columns: 1fr;
    gap: 3px;
  }
}
</style>
