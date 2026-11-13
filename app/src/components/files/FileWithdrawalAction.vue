<script setup lang="ts">
import { computed, ref } from "vue";
const props = defineProps<{
  canWithdraw: boolean;
  withdrawnState: null | "pending_quarantine" | "withdrawn";
  onWithdraw: (reason: string) => Promise<void>;
}>();
const reason = ref("");
const confirmed = ref(false);
const saving = ref(false);
const error = ref("");
const enabled = computed(
  () =>
    props.canWithdraw &&
    props.withdrawnState === null &&
    reason.value.trim().length > 0 &&
    confirmed.value &&
    !saving.value,
);
async function withdraw() {
  if (!enabled.value) return;
  saving.value = true;
  error.value = "";
  try {
    await props.onWithdraw(reason.value.trim());
    reason.value = "";
    confirmed.value = false;
  } catch (e) {
    error.value = e instanceof Error ? e.message : "撤回失败，请刷新并重试";
  } finally {
    saving.value = false;
  }
}
</script>
<template>
  <section class="withdrawal" aria-label="文件版本撤回">
    <p v-if="withdrawnState === 'withdrawn'">
      此版本已撤回，内容不可再预览或下载；审计元数据仍保留。
    </p>
    <p v-else-if="withdrawnState === 'pending_quarantine'">
      正在执行安全撤回。此版本应禁止签发新下载链接，服务端仍需隔离原文件。
    </p>
    <template v-else-if="canWithdraw">
      <p>
        撤回此版本将保留文件元数据、内容哈希及历史证据，但停止提供文件正文。
      </p>
      <label for="withdraw-file-reason">撤回原因</label>
      <textarea
        id="withdraw-file-reason"
        v-model="reason"
        rows="3"
        maxlength="2000"
      />
      <label class="confirmation"
        ><input v-model="confirmed" type="checkbox" /> 确认撤回此版本</label
      >
      <button type="button" :disabled="!enabled" @click="withdraw">
        {{ saving ? "处理中…" : "撤回此版本" }}
      </button>
    </template>
    <p v-if="error" role="alert">{{ error }}</p>
  </section>
</template>
<style scoped>
.withdrawal {
  display: grid;
  gap: 0.65rem;
  padding: 1rem;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
}
.withdrawal p {
  margin: 0;
  line-height: 1.6;
}
.withdrawal textarea {
  width: 100%;
  max-width: 100%;
  padding: 0.5rem;
  border-radius: 6px;
}
.confirmation {
  display: flex;
  gap: 0.5rem;
  align-items: center;
}
.withdrawal button {
  padding: 0.65rem;
  border-radius: 8px;
}
</style>
