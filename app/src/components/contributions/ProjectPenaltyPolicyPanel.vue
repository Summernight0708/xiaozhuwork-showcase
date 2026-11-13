<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showConfirmDialog, showToast } from "vant";
import { getBackend } from "@/services/backend";

const props = defineProps<{
  projectId: string;
  projectVersion: number;
  enabled: boolean;
  activeMemberIds: string[];
  userId: string | null;
  canManage: boolean;
  canConsent: boolean;
}>();
const emit = defineEmits<{ updated: [] }>();
const consentedBy = ref<string[]>([]);
const agreed = ref(false);
const busy = ref(false);
const error = ref("");
const retry = ref<{ fingerprint: string; requestId: string } | null>(null);

const hasConsented = computed(
  () => !!props.userId && consentedBy.value.includes(props.userId),
);
const requiredIds = computed(() => [...new Set(props.activeMemberIds)]);
const allConsented = computed(
  () =>
    requiredIds.value.length > 0 &&
    requiredIds.value.every((id) => consentedBy.value.includes(id)),
);

function getClient() {
  const backend = getBackend();
  if (!backend) throw new Error("后端当前不可用");
  return backend.client;
}
function requestIdFor(payload: unknown) {
  const fingerprint = JSON.stringify(payload);
  if (retry.value?.fingerprint !== fingerprint) {
    retry.value = { fingerprint, requestId: crypto.randomUUID() };
  }
  return retry.value.requestId;
}
async function refresh() {
  error.value = "";
  try {
    const { data, error: dbError } = await getClient()
      .from("project_penalty_policy_consents")
      .select("member_user_id")
      .eq("project_id", props.projectId)
      .eq("policy_version", 1);
    if (dbError) throw dbError;
    consentedBy.value = (data ?? [])
      .map((record) => record.member_user_id)
      .filter((id): id is string => !!id);
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "读取同意记录失败";
  }
}
watch(
  () => props.projectId,
  () => void refresh(),
  { immediate: true },
);

async function submit(command: string, params: Record<string, unknown>) {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    const backend = getBackend();
    if (!backend) throw new Error("服务器不可用");
    const requestId = requestIdFor({ command, params });
    const client = backend.client as unknown as {
      rpc: (
        name: string,
        args: Record<string, unknown>,
      ) => Promise<{
        data: { ok?: boolean; code?: string } | null;
        error: { message: string } | null;
      }>;
    };
    const { data, error: dbError } = await client.rpc(command, {
      ...params,
      p_request_id: requestId,
    });
    if (dbError) throw dbError;
    if (!(data as { ok?: boolean } | null)?.ok) {
      throw new Error((data as { code?: string } | null)?.code ?? "操作未成功");
    }
    retry.value = null;
    agreed.value = false;
    showToast("操作已记录");
    await refresh();
    emit("updated");
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "提交失败";
  } finally {
    busy.value = false;
  }
}
async function consent() {
  if (!props.canConsent || !agreed.value || hasConsented.value) return;
  await submit("cmd_consent_auto_penalty_policy", {
    p_project_id: props.projectId,
    p_expected_version: props.projectVersion,
  });
}
async function setEnabled(value: boolean) {
  if (!props.canManage || (value && !allConsented.value)) return;
  try {
    await showConfirmDialog({
      title: value ? "启用自动贡献扣减" : "关闭自动贡献扣减",
      message: value
        ? "所有活跃成员均已同意规则。只对启用后、且有真实事前任务份额签署的新责任生效；历史任务不会追溯扣分。"
        : "关闭后新接受的任务不会产生自动扣减，不影响已经形成的不可变审计记录。",
    });
  } catch {
    return;
  }
  await submit("cmd_set_project_auto_penalty_policy", {
    p_project_id: props.projectId,
    p_enabled: value,
    p_expected_version: props.projectVersion,
  });
}
</script>

<template>
  <section
    class="surface setting-section penalty-policy"
    aria-label="自动贡献扣减规则"
  >
    <h2>自动贡献扣减</h2>
    <p>
      当前：{{ enabled ? "已启用" : "关闭" }}。规则版本
      v1，只在真实任务责任开始前，所有相关成员明确同意预期份额时才可能生效。
    </p>
    <p>
      扣减以当时的任务星级、约定份额、有效起点和截止时间计算。逾期或放弃的扣减有分级标准与申诉机制；没有事前明确签署、依赖阻塞或不合格时间窗口时不会扣减。
    </p>
    <p>
      项目同意情况：{{
        requiredIds.filter((id) => consentedBy.includes(id)).length
      }}/{{ requiredIds.length }} 位活跃非观察者成员。
    </p>
    <p v-if="error" role="alert" class="penalty-policy__error">{{ error }}</p>
    <label v-if="canConsent && !hasConsented" class="penalty-policy__consent">
      <input v-model="agreed" type="checkbox" :disabled="busy" />
      我已阅读并自愿同意 v1
      自动扣减规则；每项任务的实际预期份额仍须另行在接受任务前确认。
    </label>
    <p v-if="hasConsented">
      你已同意当前规则版本。此记录不可静默撤销；组长可关闭功能。
    </p>
    <button
      v-if="canConsent && !hasConsented"
      type="button"
      :disabled="busy || !agreed"
      @click="consent"
    >
      记录本人同意
    </button>
    <button
      v-if="canManage && !enabled"
      type="button"
      :disabled="busy || !allConsented"
      @click="setEnabled(true)"
    >
      全员同意后启用
    </button>
    <button
      v-if="canManage && enabled"
      type="button"
      :disabled="busy"
      @click="setEnabled(false)"
    >
      关闭自动扣减
    </button>
    <button type="button" :disabled="busy" @click="refresh">
      刷新同意状态
    </button>
  </section>
</template>

<style scoped>
.penalty-policy {
  display: grid;
  gap: 0.75rem;
}
.penalty-policy p {
  margin: 0;
  line-height: 1.6;
}
.penalty-policy__error {
  color: var(--tu-danger);
}
.penalty-policy__consent {
  display: flex;
  align-items: flex-start;
  gap: 0.65rem;
  font-size: 0.875rem;
}
.penalty-policy__consent input {
  margin-top: 0.3rem;
}
.penalty-policy button {
  min-height: 36px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 0.45rem 0.8rem;
  background: var(--tu-surface);
  color: var(--tu-ink);
  justify-self: start;
}
</style>
