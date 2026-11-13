<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showToast } from "vant";
import { getBackend } from "@/services/backend";

const props = defineProps<{
  projectId: string;
  taskId: string;
  taskVersion: number;
  acceptedAt: string | null;
  taskWeight: number | null;
  deadlineAt: string;
  canConsent: boolean;
  autoPenaltyEnabled: boolean;
  userId: string | null;
}>();
const emit = defineEmits<{ consented: [] }>();
const share = ref<string | number>("");
const agreed = ref(false);
const busy = ref(false);
const recordedBps = ref<number | null>(null);
const error = ref("");
const retry = ref<{ payload: string; requestId: string } | null>(null);
const bps = computed(() => {
  const fraction = Number(share.value);
  if (String(share.value).trim() === "" || !Number.isFinite(fraction))
    return null;
  const result = fraction * 100;
  if (result !== Math.round(result) || result < 1 || result > 10000)
    return null;
  return Math.round(result);
});
const expectedScore = computed(() =>
  bps.value === null || !props.taskWeight
    ? null
    : ((props.taskWeight * bps.value) / 10000).toFixed(4),
);
const eligible = computed(
  () =>
    props.canConsent &&
    !props.acceptedAt &&
    props.taskWeight !== null &&
    props.taskWeight >= 1 &&
    bps.value !== null &&
    agreed.value &&
    recordedBps.value === null,
);

async function refresh() {
  recordedBps.value = null;
  error.value = "";
  if (!props.userId) return;
  const backend = getBackend();
  if (!backend) return;
  try {
    const { data, error: readError } = await backend.client
      .from("task_expected_share_consents")
      .select("expected_share_bps")
      .eq("task_id", props.taskId)
      .eq("member_user_id", props.userId)
      .eq("task_version", props.taskVersion)
      .maybeSingle();
    if (readError) throw readError;
    recordedBps.value = data?.expected_share_bps ?? null;
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "读取本人约定失败";
  }
}
watch(
  () => [props.taskId, props.taskVersion, props.userId],
  () => void refresh(),
  { immediate: true },
);
async function consent() {
  if (!eligible.value || busy.value || bps.value === null) return;
  const backend = getBackend();
  if (!backend) {
    error.value = "无法连接服务端";
    return;
  }
  busy.value = true;
  error.value = "";
  try {
    const payload = JSON.stringify({
      taskId: props.taskId,
      taskVersion: props.taskVersion,
      bps: bps.value,
    });
    if (retry.value?.payload !== payload)
      retry.value = { payload, requestId: crypto.randomUUID() };
    const client = backend.client as unknown as {
      rpc: (
        name: string,
        args: Record<string, unknown>,
      ) => Promise<{
        data: { ok?: boolean; code?: string } | null;
        error: { message: string } | null;
      }>;
    };
    const { data, error: commandError } = await client.rpc(
      "cmd_consent_task_expected_share",
      {
        p_project_id: props.projectId,
        p_task_id: props.taskId,
        p_share_bps: bps.value,
        p_request_id: retry.value.requestId,
        p_expected_version: props.taskVersion,
      },
    );
    if (commandError) throw new Error(commandError.message);
    if (!data?.ok) throw new Error(data?.code ?? "服务器拒绝了事前约定");
    recordedBps.value = bps.value;
    retry.value = null;
    agreed.value = false;
    showToast("事前份额已记录");
    emit("consented");
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "提交失败";
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section
    v-if="canConsent && !acceptedAt"
    class="expected-share"
    aria-label="事前预期贡献约定"
  >
    <strong>接受任务前：确认预期贡献份额</strong>
    <p>
      只有接受任务前明确签署、且本任务所有相关成员事前约定合计为
      100%，自动扣减才可能生效。该约定不同于任务完成后的实际贡献分配，不能事后补签。
    </p>
    <p>
      任务星级：{{ taskWeight ?? "待定" }}；截止时间：{{
        new Date(deadlineAt).toLocaleString()
      }}。
    </p>
    <p v-if="!autoPenaltyEnabled">
      本项目目前关闭自动扣减，即使记录约定，也不会对关闭期间接受的责任追溯扣减。
    </p>
    <p v-if="error" role="alert" class="expected-share__error">{{ error }}</p>
    <p v-if="recordedBps !== null">
      你已签署 {{ (recordedBps / 100).toFixed(2) }}%
      的预期份额；本任务版本的约定不可静默修改。
    </p>
    <template v-else>
      <label class="expected-share__field">
        本人预期承担比例（%）
        <input
          v-model="share"
          type="number"
          min="0.01"
          max="100"
          step="0.01"
          :disabled="busy"
          placeholder="手动输入，例如 65"
        />
      </label>
      <p v-if="expectedScore">
        预期贡献基数：{{ expectedScore }}（任务星级 × 本人份额）。
      </p>
      <label class="expected-share__check">
        <input v-model="agreed" type="checkbox" :disabled="busy" />
        我了解约定生效后的逾期与主动放弃可能扣减贡献，确认本次份额出于自愿。
      </label>
      <button type="button" :disabled="busy || !eligible" @click="consent">
        记录本人事前份额
      </button>
    </template>
    <button type="button" :disabled="busy" @click="refresh">
      刷新约定记录
    </button>
  </section>
</template>

<style scoped>
.expected-share {
  display: grid;
  gap: 0.7rem;
}
.expected-share p {
  margin: 0;
  line-height: 1.6;
  font-size: 0.875rem;
}
.expected-share__field {
  display: grid;
  gap: 0.35rem;
  font-size: 0.875rem;
}
.expected-share__field input {
  min-height: 36px;
  max-width: 12rem;
  padding: 0.5rem;
  border: 1px solid var(--tu-border);
  border-radius: 6px;
  color: inherit;
  background: transparent;
}
.expected-share__check {
  display: flex;
  gap: 0.6rem;
  align-items: flex-start;
  font-size: 0.875rem;
}
.expected-share__check input {
  margin-top: 0.3rem;
}
.expected-share button {
  justify-self: start;
  min-height: 36px;
  padding: 0.4rem 0.75rem;
  background: var(--tu-surface);
  color: var(--tu-ink);
  border: 1px solid var(--tu-border);
  border-radius: 8px;
}
.expected-share__error {
  color: var(--tu-danger);
}
</style>
