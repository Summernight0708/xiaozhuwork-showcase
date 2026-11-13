<script setup lang="ts">
import { computed, ref, watch } from "vue";

import type { TaskFileVersion } from "@/types/ui";

const props = withDefaults(
  defineProps<{
    isPrimary: boolean;
    isAcceptedCollaborator?: boolean;
    availableVersions?: readonly TaskFileVersion[];
    requiredFileTypeLabel?: string | null;
    requirementSatisfied?: boolean;
    disabled?: boolean;
  }>(),
  {
    isAcceptedCollaborator: false,
    availableVersions: () => [],
    requiredFileTypeLabel: null,
    requirementSatisfied: false,
    disabled: false,
  },
);

const emit = defineEmits<{
  submit: [payload: { text: string; fileVersionIds: string[] }];
  upload: [];
}>();

const text = ref("");
const selectedIds = ref<string[]>([]);

watch(
  () =>
    props.availableVersions.map((version) => version.fileVersionId).join(","),
  () => {
    const allowed = new Set(
      props.availableVersions.map((version) => version.fileVersionId),
    );
    selectedIds.value = selectedIds.value.filter((id) => allowed.has(id));
  },
);

const canSubmit = computed(
  () =>
    props.isPrimary &&
    !props.disabled &&
    (text.value.trim().length > 0 || selectedIds.value.length > 0),
);

function submit() {
  if (!canSubmit.value) return;
  emit("submit", {
    text: text.value.trim(),
    fileVersionIds: [...selectedIds.value],
  });
}
</script>

<template>
  <div class="submission">
    <strong>Submission</strong>
    <template v-if="isPrimary">
      <label class="field">
        <span>说明</span>
        <textarea v-model="text" rows="3" placeholder="补充本轮提交说明" />
      </label>
      <fieldset class="attachments">
        <legend>附件</legend>
        <label
          v-for="version in availableVersions"
          :key="version.fileVersionId"
          class="attachment-choice"
        >
          <input
            v-model="selectedIds"
            type="checkbox"
            :value="version.fileVersionId"
          />
          <span>v{{ version.versionNumber }} · {{ version.originalName }}</span>
        </label>
        <p v-if="!availableVersions.length" class="muted">
          暂无可选择的任务文件。
        </p>
      </fieldset>
      <button type="button" class="plain-upload" @click="emit('upload')">
        上传并选择文件
      </button>
      <p v-if="requiredFileTypeLabel" class="requirement">
        {{ requirementSatisfied ? "✓" : "○" }} 至少包含 1 个
        {{ requiredFileTypeLabel }}
      </p>
      <button
        type="button"
        class="submit-button"
        :disabled="!canSubmit"
        @click="submit"
      >
        提交验收
      </button>
    </template>
    <template v-else>
      <p v-if="isAcceptedCollaborator" class="muted">
        最终提交由主负责人完成。你仍可以在下方上传任务文件。
      </p>
      <p v-else class="muted">最终提交由主负责人完成。</p>
    </template>
  </div>
</template>

<style scoped>
.submission {
  display: grid;
  gap: 10px;
}
.field {
  display: grid;
  gap: 5px;
}
.field textarea {
  width: 100%;
  resize: vertical;
}
.attachments {
  display: grid;
  gap: 7px;
  margin: 0;
  padding: 10px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
}
.attachment-choice {
  display: flex;
  gap: 8px;
  align-items: center;
}
.plain-upload {
  justify-self: start;
  min-height: 44px;
  border: 0;
  background: transparent;
  color: var(--tu-action);
  cursor: pointer;
  font-weight: 700;
}
.submit-button {
  justify-self: start;
  min-height: 44px;
  padding: 0 14px;
  border: 0;
  border-radius: 9px;
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  cursor: pointer;
  font-weight: 800;
}
@media (hover: hover) {
  .submit-button:not(:disabled):hover {
    background: var(--tu-action-hover);
  }
}
.submit-button:not(:disabled):active {
  background: var(--tu-action-active);
}
.submit-button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.muted {
  color: var(--tu-muted);
}
.requirement {
  margin: 0;
}
</style>
