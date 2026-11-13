<script setup lang="ts">
import {
  REQUIRED_FILE_TYPE_LABELS,
  type RequiredSubmissionFileType,
} from "@/domain/task-form";
import { normalizeRequiredSubmissionFileTypes } from "@/domain/submission-file-types";
import type { TaskRow } from "@/types/ui";
import { vDismissibleDetails } from "@/directives/dismissible-details";

const props = defineProps<{
  tasks: readonly TaskRow[];
  currentTaskId?: string;
  upstreamTaskIds: readonly string[];
  supportsRequiredFileType: boolean;
  requiredFileTypes: readonly RequiredSubmissionFileType[];
}>();

const emit = defineEmits<{
  updateUpstreamTaskIds: [value: string[]];
  updateRequiredFileTypes: [value: RequiredSubmissionFileType[]];
}>();

function toggleUpstream(taskId: string) {
  const next = props.upstreamTaskIds.includes(taskId)
    ? props.upstreamTaskIds.filter((id) => id !== taskId)
    : [...props.upstreamTaskIds, taskId];
  emit("updateUpstreamTaskIds", next);
}

function toggleRequiredFileType(type: RequiredSubmissionFileType) {
  const next = props.requiredFileTypes.includes(type)
    ? props.requiredFileTypes.filter((item) => item !== type)
    : [...props.requiredFileTypes, type];
  emit("updateRequiredFileTypes", normalizeRequiredSubmissionFileTypes(next));
}

const fileTypeOptions = Object.entries(REQUIRED_FILE_TYPE_LABELS) as [
  RequiredSubmissionFileType,
  string,
][];
</script>

<template>
  <div class="workflow-fields">
    <div class="workflow-group">
      <span class="field-label">上游任务</span>
      <details v-dismissible-details class="selector">
        <summary>
          {{
            upstreamTaskIds.length
              ? `已选择 ${upstreamTaskIds.length} 个直接上游`
              : "选择直接上游任务"
          }}
        </summary>
        <label
          v-for="task in tasks.filter((item) => item.id !== currentTaskId)"
          :key="task.id"
          class="option"
        >
          <input
            type="checkbox"
            :checked="upstreamTaskIds.includes(task.id)"
            @change="toggleUpstream(task.id)"
          />
          <span>{{ task.title }}</span>
        </label>
        <p
          v-if="!tasks.filter((item) => item.id !== currentTaskId).length"
          class="field-note"
        >
          当前项目暂无可选上游任务。
        </p>
      </details>
      <p class="field-note">
        这里只选择直接上游；系统会阻止自依赖、跨项目和循环依赖。
      </p>
    </div>

    <fieldset v-if="supportsRequiredFileType" class="submission-requirement">
      <legend>提交要求</legend>
      <label
        v-for="[value, label] in fileTypeOptions"
        :key="value"
        class="choice"
      >
        <input
          :data-testid="`required-file-type-${value}`"
          type="checkbox"
          :checked="requiredFileTypes.includes(value)"
          @change="toggleRequiredFileType(value)"
        />
        <span>{{ label }}</span>
      </label>
      <p v-if="requiredFileTypes.length === 0" class="field-note">
        不限制文件类型。
      </p>
      <p v-else class="field-note">
        提交附件至少包含其中一种即可，也可以同时提交其他附件和文字说明。
      </p>
    </fieldset>
  </div>
</template>

<style scoped>
.workflow-fields,
.workflow-group,
.submission-requirement {
  display: grid;
  gap: 9px;
}
.field-label,
.submission-requirement legend {
  color: var(--tu-ink);
  font-weight: 700;
}
.selector {
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
}
.selector summary {
  padding: 10px;
  cursor: pointer;
}
.option {
  display: flex;
  gap: 8px;
  padding: 8px 10px;
}
.submission-requirement {
  margin: 8px 0 0;
  padding: 0;
  border: 0;
}
.choice {
  display: flex;
  gap: 8px;
  align-items: center;
}
.field-note {
  margin: 0;
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.5;
}
</style>
