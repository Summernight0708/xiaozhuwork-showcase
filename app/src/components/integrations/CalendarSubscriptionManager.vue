<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from "vue";
import CalendarSubscriptionCreate from "./CalendarSubscriptionCreate.vue";
import CalendarSubscriptionList from "./CalendarSubscriptionList.vue";
import CalendarSubscriptionSecurityNotice from "./CalendarSubscriptionSecurityNotice.vue";
import {
  calendarSubscriptionUrl,
  createCalendarSubscription,
  listCalendarSubscriptions,
  revokeCalendarSubscription,
  type CalendarSubscription,
} from "@/services/calendar-subscriptions";

const props = defineProps<{
  projectId: string;
  leader: boolean;
  entitlementState: string;
}>();
const subscriptions = ref<CalendarSubscription[]>([]);
const projectVersion = ref<number | null>(null);
const pending = ref(false);
const pendingId = ref<string | null>(null);
const error = ref("");
const newUrl = ref("");
const copied = ref(false);
const entitled = () =>
  props.entitlementState === "active" || props.entitlementState === "grace";
let loadSequence = 0;

async function refresh() {
  const seq = ++loadSequence;
  newUrl.value = "";
  if (!props.projectId || !props.leader) {
    subscriptions.value = [];
    projectVersion.value = null;
    return;
  }
  const result = await listCalendarSubscriptions(props.projectId);
  if (seq !== loadSequence) return;
  if (!result.ok) {
    error.value = `无法读取订阅（${result.code}）`;
    return;
  }
  subscriptions.value = result.data.subscriptions;
  projectVersion.value = result.data.projectVersion;
}
watch(
  () => [props.projectId, props.leader],
  () => {
    error.value = "";
    void refresh();
  },
  { immediate: true },
);
onBeforeUnmount(() => {
  loadSequence++;
  newUrl.value = "";
});

async function create(showTitles: boolean) {
  if (pending.value || projectVersion.value === null || !props.leader) return;
  pending.value = true;
  newUrl.value = "";
  copied.value = false;
  error.value = "";
  const issuedProject = props.projectId;
  const issuedSequence = loadSequence;
  const result = await createCalendarSubscription(
    issuedProject,
    projectVersion.value,
    showTitles,
  );
  pending.value = false;
  if (issuedProject !== props.projectId || issuedSequence !== loadSequence)
    return;
  if (!result.ok) {
    await refresh();
    error.value = `创建失败（${result.code}）`;
    return;
  }
  const token = result.data.token;
  let url = "";
  try {
    url = token ? calendarSubscriptionUrl(token) : "";
  } catch {
    error.value = "无法构建安全订阅地址，请检查 HTTPS 入口配置。";
  }
  await refresh();
  if (issuedProject !== props.projectId) return;
  newUrl.value = url;
  if (!token)
    error.value = "请求已成功处理，但秘密链接无法重放。请重新签发新订阅。";
}
async function revoke(item: CalendarSubscription) {
  if (pendingId.value !== null) return;
  pendingId.value = item.id;
  newUrl.value = "";
  error.value = "";
  const result = await revokeCalendarSubscription(
    props.projectId,
    item.id,
    item.version,
  );
  pendingId.value = null;
  await refresh();
  if (!result.ok) error.value = `撤销失败（${result.code}）`;
}
async function copyUrl() {
  if (!newUrl.value) return;
  try {
    await navigator.clipboard.writeText(newUrl.value);
    copied.value = true;
  } catch {
    error.value = "复制失败，请手动复制上面的链接。";
  }
}
</script>

<template>
  <div class="calendar-manager">
    <CalendarSubscriptionSecurityNotice />
    <p v-if="!leader" role="status">仅项目活动组长可以管理日历订阅。</p>
    <template v-else>
      <p role="status">
        项目权益：{{
          entitlementState === "active"
            ? "Pro"
            : entitlementState === "grace"
              ? "Grace"
              : "Free"
        }}
      </p>
      <p v-if="!entitled()">
        当前项目不具备有效的日历订阅权益；现有订阅不会被删除，但无法读取新的任务事件。
      </p>
      <p v-if="error" class="calendar-error" role="alert">{{ error }}</p>
      <CalendarSubscriptionCreate
        :disabled="!entitled() || projectVersion === null"
        :pending="pending"
        @create="create"
      />
      <div v-if="newUrl" class="calendar-secret">
        <strong>一次性订阅链接（离开页面后无法找回）</strong>
        <input
          :value="newUrl"
          readonly
          aria-label="一次性日历订阅链接"
          @focus="($event.target as HTMLInputElement).select()"
        />
        <button type="button" @click="copyUrl">
          {{ copied ? "已复制" : "复制链接" }}
        </button>
      </div>
      <CalendarSubscriptionList
        :items="subscriptions"
        :pending-id="pendingId"
        :can-revoke="leader"
        @revoke="revoke"
      />
    </template>
  </div>
</template>

<style scoped>
.calendar-manager {
  display: grid;
  gap: 1rem;
}
.calendar-error {
  color: var(--tu-danger);
}
.calendar-secret {
  display: grid;
  gap: 0.5rem;
  border: 1px solid #b0c4e8;
  border-radius: 10px;
  padding: 1rem;
  min-width: 0;
}
.calendar-secret input {
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
  padding: 0.6rem;
}
.calendar-secret button {
  justify-self: start;
  border: 0;
  background: var(--tu-action);
  border-radius: 8px;
  color: white;
  padding: 0.6rem 1rem;
}
</style>
