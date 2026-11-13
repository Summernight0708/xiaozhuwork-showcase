<script setup lang="ts">
import { ref } from "vue";
import { sendTaskNudge } from "@/features/deadline-reminders/api";

const props = defineProps<{
  projectId: string;
  taskId: string;
  taskVersion: number;
  canNudge: boolean;
  disabled?: boolean;
}>();
const emit = defineEmits<{ sent: [] }>();
const busy = ref(false);
const feedback = ref("");
async function nudge() {
  busy.value = true;
  feedback.value = "";
  try {
    const result = await sendTaskNudge(
      props.projectId,
      props.taskId,
      props.taskVersion,
    );
    feedback.value = `已提醒 ${result.data?.recipientCount ?? 0} 位相关成员`;
    emit("sent");
  } catch (caught) {
    feedback.value = caught instanceof Error ? caught.message : "催促失败";
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div v-if="canNudge" class="nudge">
    <button type="button" :disabled="busy || disabled" @click="nudge">
      {{ busy ? "发送中…" : "催促处理" }}
    </button>
    <span v-if="feedback" role="status">{{ feedback }}</span>
  </div>
</template>

<style scoped>
.nudge {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  align-items: center;
  font-size: 13px;
}
button {
  min-height: 36px;
  padding: 6px 12px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  cursor: pointer;
}
button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
