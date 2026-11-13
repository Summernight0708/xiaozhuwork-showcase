<script setup lang="ts">
import { onMounted, ref, watch } from "vue";
import {
  loadTaskReminderPreferences,
  saveTaskReminderPreferences,
} from "@/features/deadline-reminders/api";
import {
  DEFAULT_REMINDER_OFFSETS,
  MAX_REMINDER_OFFSETS,
  displayReminderOffset,
  normalizeReminderOffsets,
} from "@/features/deadline-reminders/model";

const props = defineProps<{ projectId: string; taskId: string }>();
const enabled = ref(true);
const offsets = ref<number[]>([...DEFAULT_REMINDER_OFFSETS]);
const version = ref(0);
const customMinutes = ref("");
const saving = ref(false);
const loading = ref(false);
const error = ref("");
const success = ref("");

async function reload() {
  loading.value = true;
  error.value = "";
  try {
    const data = await loadTaskReminderPreferences(
      props.projectId,
      props.taskId,
    );
    enabled.value = data.enabled;
    offsets.value = data.offsets;
    version.value = data.version;
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "提醒设置读取失败";
  } finally {
    loading.value = false;
  }
}
onMounted(reload);
watch(() => [props.projectId, props.taskId], reload);
function remove(offset: number) {
  if (offsets.value.length > 1)
    offsets.value = offsets.value.filter((n) => n !== offset);
}
function add() {
  error.value = "";
  try {
    offsets.value = normalizeReminderOffsets([
      ...offsets.value,
      Number(customMinutes.value) * 60,
    ]);
    customMinutes.value = "";
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "提醒节点无效";
  }
}
async function save() {
  saving.value = true;
  error.value = "";
  success.value = "";
  try {
    const result = await saveTaskReminderPreferences(
      props.projectId,
      props.taskId,
      offsets.value,
      enabled.value,
      version.value,
    );
    version.value = result.data?.preferenceVersion ?? version.value + 1;
    success.value = "提醒设置已保存";
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "保存失败";
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <section class="reminder-settings" aria-label="个人任务提醒设置">
    <div class="heading">
      <strong>截止提醒</strong>
      <label
        ><input
          v-model="enabled"
          type="checkbox"
          :disabled="loading || saving"
        />
        启用站内提醒</label
      >
    </div>
    <p>仅影响你自己的提醒；默认在截止前 24 小时和 2 小时通知。</p>
    <div class="offsets" aria-label="提醒节点">
      <span v-for="offset in offsets" :key="offset" class="offset">
        {{ displayReminderOffset(offset) }}
        <button
          type="button"
          :disabled="loading || saving || offsets.length <= 1"
          :aria-label="`移除${displayReminderOffset(offset)}`"
          @click="remove(offset)"
        >
          ×
        </button>
      </span>
    </div>
    <div class="actions">
      <label
        >提前
        <input
          v-model="customMinutes"
          type="number"
          min="5"
          max="20160"
          step="1"
          inputmode="numeric"
          :disabled="
            loading || saving || offsets.length >= MAX_REMINDER_OFFSETS
          "
        />
        分钟</label
      >
      <button
        type="button"
        :disabled="loading || saving || offsets.length >= MAX_REMINDER_OFFSETS"
        @click="add"
      >
        增加节点
      </button>
      <button type="button" :disabled="loading || saving" @click="save">
        {{ saving ? "保存中…" : "保存设置" }}
      </button>
    </div>
    <p v-if="error" role="alert" class="error">{{ error }}</p>
    <p v-if="success" role="status">{{ success }}</p>
  </section>
</template>

<style scoped>
.reminder-settings {
  display: grid;
  gap: 12px;
  padding: 16px;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
  color: var(--tu-ink);
  background: var(--tu-surface);
}
.heading,
.actions,
.offsets {
  display: flex;
  gap: 12px;
  align-items: center;
  flex-wrap: wrap;
}
.heading {
  justify-content: space-between;
}
.reminder-settings p {
  margin: 0;
  font-size: 13px;
  color: var(--tu-muted);
}
.offset {
  display: inline-flex;
  gap: 6px;
  align-items: center;
  border-radius: 999px;
  padding: 6px 9px;
  background: var(--tu-blue-soft);
}
.offset button {
  border: 0;
  background: transparent;
  cursor: pointer;
  font-size: 18px;
}
.actions input {
  width: 88px;
  min-height: 36px;
  border: 1px solid var(--tu-border);
  border-radius: 6px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  padding: 4px;
}
.actions button {
  min-height: 36px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 6px 12px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  cursor: pointer;
}
.actions button:last-child {
  background: var(--tu-blue);
  color: white;
}
button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.reminder-settings .error {
  color: var(--tu-danger);
}
</style>
