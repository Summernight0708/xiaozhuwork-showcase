<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import {
  cancelAccountDeletion,
  getAccountLifecycleStatus,
  mayCancelDeletion,
  requestAccountDeletion,
  type AccountLifecycleStatus,
} from "@/features/account-lifecycle/repository";

const router = useRouter();
const authStore = useAuthStore();
const status = ref<AccountLifecycleStatus | null>(null);
const loading = ref(false);
const submitting = ref(false);
const error = ref("");
const confirmed = ref(false);
const phrase = ref("");
const pendingRequest = ref<{ id: string; version: number } | null>(null);
const pendingCancel = ref<{ id: string; version: number } | null>(null);
const now = ref(Date.now());
let clock: ReturnType<typeof setInterval> | undefined;

const canRequest = computed(
  () => status.value?.state === "active" || status.value?.state === "canceled",
);
const canCancel = computed(
  () => status.value !== null && mayCancelDeletion(status.value, now.value),
);
const canConfirm = computed(
  () =>
    canRequest.value && confirmed.value && phrase.value.trim() === "注销账号",
);

async function refresh() {
  loading.value = true;
  error.value = "";
  try {
    status.value = await getAccountLifecycleStatus();
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "读取账号状态失败";
  } finally {
    loading.value = false;
  }
}

async function submitDeletion() {
  if (!status.value || !canConfirm.value || submitting.value) return;
  submitting.value = true;
  error.value = "";
  if (pendingRequest.value?.version !== status.value.version) {
    pendingRequest.value = {
      id: crypto.randomUUID(),
      version: status.value.version,
    };
  }
  const { id, version } = pendingRequest.value;
  try {
    await requestAccountDeletion(id, version);
    pendingRequest.value = null;
    confirmed.value = false;
    phrase.value = "";
    await refresh();
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "提交注销申请失败";
  } finally {
    submitting.value = false;
  }
}

async function undoDeletion() {
  if (!status.value || !canCancel.value || submitting.value) return;
  submitting.value = true;
  error.value = "";
  if (pendingCancel.value?.version !== status.value.version) {
    pendingCancel.value = {
      id: crypto.randomUUID(),
      version: status.value.version,
    };
  }
  const { id, version } = pendingCancel.value;
  try {
    await cancelAccountDeletion(id, version);
    pendingCancel.value = null;
    await refresh();
    await authStore.refreshProfile();
    await router.replace({ name: "account-settings" });
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "撤销注销申请失败";
  } finally {
    submitting.value = false;
  }
}

onMounted(() => {
  void refresh();
  clock = setInterval(() => (now.value = Date.now()), 1_000);
});
onUnmounted(() => clearInterval(clock));
</script>

<template>
  <section class="account-deletion" aria-labelledby="account-deletion-title">
    <header>
      <h2 id="account-deletion-title">注销账号</h2>
      <p>
        注销申请会限制账号业务访问。请先移交组长、任务与待确认责任。
        小组历史任务、文件、正式成果及其他成员贡献不会因你的注销而删除。
      </p>
    </header>

    <p v-if="loading" role="status">正在读取账号状态…</p>
    <p v-if="error" class="account-deletion__error" role="alert">{{ error }}</p>

    <template v-if="status && !loading">
      <div v-if="canRequest" class="account-deletion__form">
        <p>
          申请后提供
          <strong>30 天撤销窗口</strong>。届时将依据隐私与必要留存规则
          处理个人资料；已保留的审计事实不会被伪造或改写。
        </p>
        <label class="account-deletion__confirm">
          <input v-model="confirmed" type="checkbox" />
          我理解注销影响，且已安排完成必要的项目责任交接
        </label>
        <label for="account-deletion-phrase">
          在下方输入「注销账号」以确认
        </label>
        <input
          id="account-deletion-phrase"
          v-model="phrase"
          type="text"
          autocomplete="off"
          class="account-deletion__input"
        />
        <button
          type="button"
          class="account-deletion__danger"
          :disabled="!canConfirm || submitting"
          @click="submitDeletion"
        >
          {{ submitting ? "提交中…" : "申请注销账号" }}
        </button>
      </div>

      <div v-else class="account-deletion__status" role="status">
        <p v-if="status.state === 'pending'">
          注销申请已提交。撤销截止：
          <strong>{{
            status.cancelUntil
              ? new Date(status.cancelUntil).toLocaleString()
              : "待确认"
          }}</strong>
        </p>
        <p v-else-if="status.state === 'blocked'">
          注销进入需要人工安全核验的阶段，目前不能认定为已完成。
        </p>
        <p v-else>当前账号已进入不可由本页面恢复的身份处理阶段。</p>
        <button
          v-if="canCancel"
          type="button"
          :disabled="submitting"
          @click="undoDeletion"
        >
          {{ submitting ? "撤销中…" : "撤销注销申请" }}
        </button>
        <p v-else-if="status.state === 'pending'">
          撤销窗口已结束或登录权限已撤销，无法在本页面恢复。身份处理仍需人工安全核验。
        </p>
      </div>
    </template>

    <button v-if="error" type="button" @click="refresh">重新读取状态</button>
  </section>
</template>

<style scoped>
.account-deletion {
  display: grid;
  gap: 1rem;
  width: 100%;
  max-width: 48rem;
  padding: 1.25rem;
  border: 1px solid var(--tu-border);
  border-radius: 0.875rem;
}
.account-deletion header h2 {
  margin: 0 0 0.5rem;
  font-size: 1.125rem;
}
.account-deletion p {
  line-height: 1.65;
  margin: 0.375rem 0;
}
.account-deletion__form {
  display: grid;
  gap: 0.75rem;
}
.account-deletion__confirm {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
}
.account-deletion__confirm input {
  margin-top: 0.3rem;
}
.account-deletion__input {
  width: 100%;
  min-height: 2.75rem;
  padding: 0.625rem;
  border: 1px solid var(--tu-border);
  border-radius: 0.5rem;
  background: var(--van-background-2, transparent);
  color: inherit;
}
.account-deletion button {
  min-height: 2.75rem;
  padding: 0.5rem 1rem;
  border: 1px solid currentColor;
  border-radius: 0.5rem;
  background: transparent;
  color: inherit;
  cursor: pointer;
}
.account-deletion .account-deletion__danger {
  border-color: var(--tu-danger);
  color: var(--tu-danger);
}
.account-deletion button:disabled {
  cursor: not-allowed;
  opacity: 0.48;
}
.account-deletion__error {
  color: var(--tu-danger);
}
</style>
