<script setup lang="ts">
import { computed, ref, watchEffect } from "vue";
type TaskAction = "cancel" | "abandon" | "delete";
const props = defineProps<{
  canCancel: boolean;
  canAbandon: boolean;
  canDelete: boolean;
  onCancel: (reason: string) => Promise<void>;
  onAbandon: (reason: string) => Promise<void>;
  onDelete: () => Promise<void>;
}>();
const action = ref<TaskAction>(
  props.canCancel ? "cancel" : props.canAbandon ? "abandon" : "delete",
);
watchEffect(() => {
  if (
    (action.value === "cancel" && !props.canCancel) ||
    (action.value === "abandon" && !props.canAbandon) ||
    (action.value === "delete" && !props.canDelete)
  ) {
    action.value = props.canCancel
      ? "cancel"
      : props.canAbandon
        ? "abandon"
        : "delete";
  }
});
const reason = ref("");
const confirmed = ref(false);
const saving = ref(false);
const error = ref("");
const available = computed(
  () =>
    (props.canCancel ? 1 : 0) +
    (props.canAbandon ? 1 : 0) +
    (props.canDelete ? 1 : 0),
);
const canSubmit = computed(
  () =>
    !saving.value &&
    confirmed.value &&
    (action.value === "delete" || reason.value.trim().length > 0) &&
    ((action.value === "cancel" && props.canCancel) ||
      (action.value === "abandon" && props.canAbandon) ||
      (action.value === "delete" && props.canDelete)),
);
async function submit() {
  if (!canSubmit.value) return;
  saving.value = true;
  error.value = "";
  try {
    if (action.value === "cancel") await props.onCancel(reason.value.trim());
    if (action.value === "abandon") await props.onAbandon(reason.value.trim());
    if (action.value === "delete") await props.onDelete();
    confirmed.value = false;
    reason.value = "";
  } catch (e) {
    error.value = e instanceof Error ? e.message : "操作失败，请刷新并重试";
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <section v-if="available" class="disposition" aria-label="任务处置">
    <h3>任务处置</h3>
    <label for="task-disposition-kind">操作</label>
    <select
      id="task-disposition-kind"
      v-model="action"
      @change="confirmed = false"
    >
      <option v-if="canCancel" value="cancel">
        取消任务（不扣除成员贡献）
      </option>
      <option v-if="canAbandon" value="abandon">本人主动放弃责任</option>
      <option v-if="canDelete" value="delete">删除无业务事实的空任务</option>
    </select>
    <p v-if="action === 'cancel'">
      保留任务、提交、文件及审核历史，不代表成员违约。
    </p>
    <p v-else-if="action === 'abandon'">
      释放当前主负责人责任；免费窗口外的放弃可能进入后续贡献治理。
    </p>
    <p v-else>
      仅无责任接受、文件、依赖、提交或审核等历史的空任务可删除，服务端会再次检查。
    </p>
    <template v-if="action !== 'delete'">
      <label for="task-disposition-reason">原因（必填）</label>
      <textarea
        id="task-disposition-reason"
        v-model="reason"
        maxlength="2000"
        rows="3"
      />
    </template>
    <label class="confirmation"
      ><input v-model="confirmed" type="checkbox" />
      我理解此操作的影响并确认执行
    </label>
    <button type="button" :disabled="!canSubmit" @click="submit">
      {{ saving ? "提交中…" : "确认操作" }}
    </button>
    <p v-if="error" role="alert">{{ error }}</p>
  </section>
</template>

<style scoped>
.disposition {
  display: grid;
  gap: 0.7rem;
  padding: 1rem;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
}
.disposition h3 {
  margin: 0;
  font-size: 1rem;
}
.disposition p {
  margin: 0;
  line-height: 1.6;
  font-size: 0.875rem;
}
.disposition select,
.disposition textarea {
  max-width: 100%;
  width: 100%;
  border: 1px solid #aaa;
  border-radius: 6px;
  padding: 0.55rem;
  background: inherit;
  color: inherit;
}
.confirmation {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.disposition button {
  padding: 0.65rem;
  border-radius: 8px;
}
</style>
