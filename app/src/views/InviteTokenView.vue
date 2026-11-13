<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showToast } from "vant";

import pigLogo from "@/assets/brand/pig.svg";

import { newRequestId } from "@/lib/command-adapter";
import { inviteJoinCommandSnapshot } from "@/domain/invitations";
import PageState from "@/components/common/PageState.vue";
import { missingProjectIdentity } from "@/domain/profile-completion";
import { getBackend } from "@/services/backend";
import { runIdempotentCommand } from "@/services/command-runner";
import { domainErrorMessage } from "@/services/errors";
import { useAuthStore } from "@/stores/auth";
import type { PreviewProjectInviteData } from "@/types/commands";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const token = computed(() => String(route.params.token || ""));
const preview = ref<PreviewProjectInviteData | null>(null);
const loading = ref(true);
const error = ref<string | null>(null);
const outcome = ref<"idle" | "pending">("idle");
const joining = ref(false);
const savingIdentity = ref(false);
const realName = ref("");
const studentNumber = ref("");
const missingIdentity = computed(() =>
  missingProjectIdentity(auth.profile, {
    requireRealName: preview.value?.requireRealName ?? false,
    requireStudentNumber: preview.value?.requireStudentNumber ?? false,
  }),
);
const identityRequired = computed(
  () => missingIdentity.value.realName || missingIdentity.value.studentNumber,
);

async function loadPreview() {
  const backend = getBackend();
  loading.value = true;
  error.value = null;
  try {
    if (!backend) {
      error.value = "当前未配置 Supabase 环境，无法读取邀请。";
      return;
    }
    preview.value = await backend.commands.previewProjectInvite({
      token: token.value,
    });
  } catch {
    error.value = "邀请信息加载失败，请检查链接或稍后重试。";
  } finally {
    loading.value = false;
  }
}

async function saveIdentityAndContinue() {
  if (!auth.profile) return;
  if (missingIdentity.value.realName && !realName.value.trim()) {
    showToast("请填写真实姓名");
    return;
  }
  if (missingIdentity.value.studentNumber && !studentNumber.value.trim()) {
    showToast("请填写学号");
    return;
  }
  savingIdentity.value = true;
  try {
    await auth.saveProfile({
      displayName: auth.profile.display_name?.trim() ?? "",
      realName: missingIdentity.value.realName
        ? realName.value
        : (auth.profile.real_name ?? ""),
      studentNumber: missingIdentity.value.studentNumber
        ? studentNumber.value
        : (auth.profile.student_number ?? ""),
    });
    await continueJoin();
  } catch {
    showToast("身份信息保存失败，请重试");
  } finally {
    savingIdentity.value = false;
  }
}

async function continueJoin() {
  await auth.initialize();
  if (!auth.isAuthenticated) {
    await router.push({ name: "login", query: { return: route.fullPath } });
    return;
  }
  if (identityRequired.value) return;
  if (!preview.value?.available) return;

  const backend = getBackend();
  if (!backend) return;
  const command = inviteJoinCommandSnapshot(token.value, preview.value);
  joining.value = true;
  try {
    const requestId = newRequestId();
    const result = await runIdempotentCommand({
      requestId,
      maxTransportRetries: 1,
      onStaleVersion: async () => {
        if (token.value === command.token) await loadPreview();
      },
      execute: (stableRequestId) =>
        backend.commands.joinProjectViaInvite({
          token: command.token,
          requestId: stableRequestId,
          expectedVersion: command.expectedVersion,
        }),
    });
    if (!result.ok) {
      showToast(domainErrorMessage(result.code));
      return;
    }
    if (result.data.outcome === "joined") {
      showToast("已加入项目");
      await router.replace({
        name: "project-overview",
        params: { projectId: result.data.projectId },
      });
    } else {
      outcome.value = "pending";
    }
  } finally {
    joining.value = false;
  }
}

watch(token, () => {
  preview.value = null;
  outcome.value = "idle";
  void loadPreview();
});

watch(
  () => auth.profile,
  (profile) => {
    realName.value = profile?.real_name ?? "";
    studentNumber.value = profile?.student_number ?? "";
  },
  { immediate: true },
);

onMounted(async () => {
  await auth.initialize();
  await loadPreview();
});
</script>

<template>
  <main class="invite-page">
    <div class="invite-brand">
      <span class="invite-brand-mark" aria-hidden="true">
        <img :src="pigLogo" alt="" width="20" height="20" />
      </span>
      <strong>小猪作业</strong>
    </div>
    <PageState
      :loading="loading"
      :error="error"
      :empty="!preview"
      empty-title="邀请不可用"
      @retry="loadPreview"
    >
      <section v-if="preview" class="invite-card">
        <template v-if="outcome === 'pending'">
          <span class="result-mark">✓</span>
          <h1>加入申请已提交</h1>
          <p>项目需要组长审批。审批完成后即可从“我的项目”进入。</p>
          <RouterLink to="/projects"
            ><van-button type="primary">返回我的项目</van-button></RouterLink
          >
        </template>
        <template v-else>
          <span class="invite-label">项目邀请</span>
          <h1>{{ preview.projectName }}</h1>
          <p class="deadline">
            项目 DDL：{{ new Date(preview.projectDeadlineAt).toLocaleString() }}
          </p>
          <div class="requirements">
            <span
              >加入方式：{{
                preview.mode === "direct" ? "直接加入" : "需要审批"
              }}</span
            >
            <span
              >真实姓名：{{
                preview.requireRealName ? "项目要求" : "不强制"
              }}</span
            >
            <span
              >学号：{{
                preview.requireStudentNumber ? "项目要求" : "不强制"
              }}</span
            >
          </div>
          <div v-if="!preview.available" class="unavailable">
            此邀请已过期、撤销或达到使用上限。
          </div>
          <template v-else>
            <form
              v-if="auth.isAuthenticated && identityRequired"
              class="identity-form"
              @submit.prevent="saveIdentityAndContinue"
            >
              <strong>加入「{{ preview.projectName }}」</strong>
              <p>该项目要求成员补充以下身份信息，保存后会继续当前邀请流程。</p>
              <label v-if="missingIdentity.realName" for="invite-real-name">
                真实姓名
              </label>
              <input
                v-if="missingIdentity.realName"
                id="invite-real-name"
                v-model="realName"
                autocomplete="name"
                name="realName"
                maxlength="120"
              />
              <label
                v-if="missingIdentity.studentNumber"
                for="invite-student-number"
              >
                学号
              </label>
              <input
                v-if="missingIdentity.studentNumber"
                id="invite-student-number"
                v-model="studentNumber"
                name="studentNumber"
                autocomplete="off"
                maxlength="40"
              />
              <van-button
                block
                type="primary"
                native-type="submit"
                :loading="savingIdentity"
              >
                保存并继续
              </van-button>
            </form>
            <van-button
              v-else
              block
              type="primary"
              :loading="joining"
              @click="continueJoin"
            >
              {{
                auth.isAuthenticated
                  ? preview.mode === "direct"
                    ? "加入项目"
                    : "提交加入申请"
                  : "登录后继续"
              }}
            </van-button>
          </template>
        </template>
      </section>
    </PageState>
  </main>
</template>

<style scoped>
.invite-page {
  --invite-bg: var(--tu-bg);
  --invite-surface: var(--tu-surface);
  --invite-ink: var(--tu-ink);
  --invite-muted: var(--tu-muted);
  --invite-border: var(--tu-border);
  --invite-subtle: var(--tu-subtle-surface);

  min-height: 100vh;
  min-height: 100dvh;
  width: 100%;
  display: grid;
  grid-template-columns: minmax(0, 680px);
  align-content: start;
  justify-content: center;
  gap: 36px;
  padding: max(34px, env(safe-area-inset-top))
    max(18px, env(safe-area-inset-right))
    calc(40px + env(safe-area-inset-bottom))
    max(18px, env(safe-area-inset-left));
  background: var(--invite-bg);
  color: var(--invite-ink);
}
.invite-brand {
  justify-self: start;
  display: inline-flex;
  align-items: center;
  gap: 9px;
  color: var(--invite-ink);
  font-size: 17px;
  letter-spacing: -0.02em;
}
.invite-brand-mark {
  width: 34px;
  height: 34px;
  display: grid;
  place-items: center;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  background: var(--tu-subtle-surface);
  color: var(--invite-ink);
}
.invite-brand-mark img {
  width: 20px;
  height: 20px;
}
.invite-card {
  min-width: 0;
  display: grid;
  gap: 18px;
  padding: 30px;
  border: 1px solid var(--invite-border);
  border-radius: var(--radius-panel);
  background: var(--invite-surface);
  box-shadow: var(--tu-shadow);
}
.invite-label {
  color: var(--invite-muted);
  font-size: 13px;
  font-weight: 700;
}
.invite-card h1 {
  margin: 0;
  color: var(--invite-ink);
  font-size: 34px;
  letter-spacing: -0.035em;
  overflow-wrap: anywhere;
  text-wrap: balance;
}
.deadline {
  margin: 0;
  color: var(--invite-muted);
}
.requirements {
  min-width: 0;
  display: grid;
  gap: 8px;
  padding: 14px;
  border: 1px solid var(--invite-border);
  border-radius: var(--radius-control);
  background: var(--invite-subtle);
  color: var(--invite-muted);
  font-size: 14px;
}
.identity-form {
  min-width: 0;
  display: grid;
  gap: 9px;
  padding: 14px;
  border: 1px solid var(--invite-border);
  border-radius: var(--radius-control);
  background: var(--invite-subtle);
}
.identity-form p {
  margin: 0 0 4px;
  color: var(--invite-muted);
  font-size: 13px;
  line-height: 1.5;
}
.identity-form label {
  color: var(--invite-ink);
  font-size: 13px;
  font-weight: 700;
}
.identity-form input {
  width: 100%;
  min-width: 0;
  min-height: 44px;
  padding: 0 11px;
  border: 1px solid var(--invite-border);
  border-radius: var(--radius-control);
  background: var(--invite-surface);
  color: var(--invite-ink);
  font: inherit;
}
.identity-form input:focus-visible {
  border-color: var(--tu-action);
}

.invite-card :deep(.van-button) {
  min-height: 44px;
}

.unavailable {
  padding: 12px;
  border: 1px solid var(--tu-danger);
  border-radius: 9px;
  background: var(--tu-danger-surface);
  color: var(--tu-danger-ink);
}
.result-mark {
  width: 48px;
  height: 48px;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: var(--tu-success-surface);
  color: var(--tu-success-ink);
  font-size: 24px;
  font-weight: 800;
}

:global(:root[data-theme="dark"] .invite-brand-mark) {
  border-color: var(--tu-border);
  background: var(--tu-subtle-surface);
}

:global(:root[data-theme="dark"] .invite-brand-mark img) {
  filter: invert(1);
}

:global(:root[data-theme="dark"] .unavailable) {
  border-color: var(--tu-danger);
  background: var(--tu-danger-surface);
  color: var(--tu-danger-ink);
}

:global(:root[data-theme="dark"] .result-mark) {
  background: var(--tu-success-surface);
  color: var(--tu-success-ink);
}

@media (max-width: 600px) {
  .invite-page {
    gap: 24px;
    padding: max(24px, env(safe-area-inset-top))
      max(14px, env(safe-area-inset-right))
      calc(28px + env(safe-area-inset-bottom))
      max(14px, env(safe-area-inset-left));
  }

  .invite-card {
    gap: 16px;
    padding: 22px 18px;
    border-radius: var(--radius-panel);
  }

  .invite-card h1 {
    font-size: clamp(28px, 9vw, 34px);
  }

  .requirements,
  .identity-form {
    padding: 12px;
  }
}
</style>
