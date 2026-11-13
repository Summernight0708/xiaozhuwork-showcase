<script setup lang="ts">
import { computed, watch } from "vue";

import TaskResponsibilityFields from "@/components/task/TaskResponsibilityFields.vue";
import TaskWorkflowFields from "@/components/task/TaskWorkflowFields.vue";
import {
  validateTaskForm,
  type TaskFormCapabilities,
  type TaskFormModel,
} from "@/domain/task-form";
import type { MembershipRow, TaskRow } from "@/types/ui";

const props = defineProps<{
  modelValue: TaskFormModel;
  members: readonly MembershipRow[];
  tasks: readonly TaskRow[];
  capabilities: TaskFormCapabilities;
  currentTaskId?: string;
  submitting?: boolean;
  submitLabel?: string;
  contributionMode?: string;
  projectDeadlineAt?: string;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: TaskFormModel];
  submit: [];
  cancel: [];
}>();

const validationError = computed(() =>
  validateTaskForm(props.modelValue, props.capabilities, {
    projectDeadlineAt: props.projectDeadlineAt,
  }),
);

function datetimeLocalMax(value?: string) {
  if (!value) return undefined;
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) return value;
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return undefined;
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function projectDeadlineLabel(value?: string) {
  if (!value || !Number.isFinite(Date.parse(value))) return "";
  return new Date(value).toLocaleString();
}

let latestModel: TaskFormModel = props.modelValue;

watch(
  () => props.modelValue,
  (value) => {
    latestModel = value;
  },
);

function patch(patchValue: Partial<TaskFormModel>) {
  const next = { ...latestModel, ...patchValue };
  latestModel = next;
  emit("update:modelValue", next);
}

function submit() {
  if (!validationError.value) emit("submit");
}
</script>

<template>
  <form class="task-form" @submit.prevent="submit">
    <section class="form-section">
      <div class="section-heading">
        <h2>基本信息</h2>
        <span>定义任务本身</span>
      </div>
      <label class="field">
        <span>任务名称 *</span>
        <input
          :value="modelValue.title"
          maxlength="120"
          required
          @input="patch({ title: ($event.target as HTMLInputElement).value })"
        />
      </label>
      <label class="field">
        <span>任务描述</span>
        <textarea
          :value="modelValue.description"
          rows="4"
          maxlength="1200"
          @input="
            patch({ description: ($event.target as HTMLTextAreaElement).value })
          "
        />
      </label>
      <div v-if="contributionMode !== 'facts_only'" class="field">
        <span>工作量星级</span>
        <div class="difficulty" role="radiogroup" aria-label="任务难度">
          <label v-for="star in 5" :key="star">
            <input
              type="radio"
              name="task-difficulty"
              :value="star"
              :checked="modelValue.difficulty === star"
              @change="patch({ difficulty: star })"
            />
            <span aria-hidden="true">{{
              modelValue.difficulty >= star ? "★" : "☆"
            }}</span>
            <span class="sr-only">{{ star }} 星</span>
          </label>
        </div>
        <small>星级表示预计工作量，不是成员评分。</small>
      </div>
    </section>

    <section class="form-section">
      <div class="section-heading">
        <h2>责任与时间</h2>
        <span>明确 Primary 和时间边界</span>
      </div>
      <TaskResponsibilityFields
        :assignment-mode="modelValue.assignmentMode"
        :assignee-id="modelValue.assigneeId"
        :collaborator-ids="modelValue.collaboratorIds"
        :members="members"
        :supports-collaborators="capabilities.collaborators"
        @update-assignment-mode="patch({ assignmentMode: $event })"
        @update-assignee-id="patch({ assigneeId: $event })"
        @update-collaborator-ids="patch({ collaboratorIds: $event })"
      />

      <label v-if="capabilities.startAt" class="field">
        <span>开始时间</span>
        <input
          type="datetime-local"
          :value="modelValue.startAt"
          @input="patch({ startAt: ($event.target as HTMLInputElement).value })"
        />
      </label>
      <label class="field">
        <span>截止时间 *</span>
        <input
          type="datetime-local"
          required
          :value="modelValue.deadlineAt"
          :max="datetimeLocalMax(projectDeadlineAt)"
          @input="
            patch({ deadlineAt: ($event.target as HTMLInputElement).value })
          "
        />
        <small v-if="projectDeadlineAt">
          项目 DDL：{{ projectDeadlineLabel(projectDeadlineAt) }}
        </small>
      </label>
    </section>

    <section class="form-section">
      <div class="section-heading">
        <h2>工作流与提交</h2>
        <span>只配置创建时需要的规则</span>
      </div>
      <TaskWorkflowFields
        :tasks="tasks"
        :current-task-id="currentTaskId"
        :upstream-task-ids="modelValue.upstreamTaskIds"
        :supports-required-file-type="capabilities.requiredFileType"
        :required-file-types="modelValue.requiredFileTypes"
        @update-upstream-task-ids="patch({ upstreamTaskIds: $event })"
        @update-required-file-types="patch({ requiredFileTypes: $event })"
      />
      <label v-if="!currentTaskId" class="review-option">
        <input
          data-testid="requires-review-toggle"
          type="checkbox"
          :checked="modelValue.requiresReview"
          @change="
            patch({
              requiresReview: ($event.target as HTMLInputElement).checked,
            })
          "
        />
        <span>
          <strong>需要验收</strong>
          <small>关闭后，负责人提交成果即完成任务</small>
        </span>
      </label>
      <slot name="creation-extras" />
    </section>

    <p v-if="validationError" class="form-error" role="status">
      {{ validationError }}
    </p>

    <div class="form-actions">
      <button type="button" class="secondary" @click="emit('cancel')">
        取消
      </button>
      <button
        type="submit"
        class="primary"
        :disabled="!!validationError || submitting"
      >
        {{ submitting ? "提交中…" : submitLabel || "保存任务" }}
      </button>
    </div>
  </form>
</template>

<style scoped>
.task-form {
  display: grid;
  gap: 16px;
}
.form-section {
  display: grid;
  gap: var(--space-md);
  padding: var(--space-lg) 0;
  border-top: 1px solid var(--tu-border);
}
.section-heading {
  padding-bottom: 12px;
  border-bottom: 1px solid var(--tu-border);
}
.section-heading h2 {
  margin: 0;
  font-size: 18px;
}
.section-heading span {
  display: block;
  margin-top: 4px;
  color: var(--tu-muted);
  font-size: 13px;
}
.field {
  display: grid;
  gap: 6px;
}
.field > span {
  font-weight: 600;
}
.field input,
.field textarea {
  width: 100%;
  min-height: 42px;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  padding: 9px 11px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.field textarea {
  resize: vertical;
}
.field small {
  color: var(--tu-muted);
  line-height: 1.5;
}
.review-option {
  display: flex;
  align-items: center;
  gap: 12px;
  cursor: pointer;
}
.review-option input {
  width: 20px;
  height: 20px;
  flex: none;
  accent-color: var(--tu-action);
}
.review-option span {
  display: grid;
  gap: 3px;
}
.review-option small {
  color: var(--tu-muted);
}
.difficulty {
  display: flex;
  gap: 5px;
}
.difficulty label {
  position: relative;
  display: inline-flex;
  cursor: pointer;
}
.difficulty input {
  position: absolute;
  width: 1px;
  height: 1px;
  margin: 0;
  overflow: hidden;
  clip-path: inset(50%);
  opacity: 0;
}
.difficulty span[aria-hidden="true"] {
  color: var(--tu-star);
  font-size: 24px;
}
.difficulty input:focus-visible + span {
  outline: 3px solid var(--tu-focus-ring);
  outline-offset: 2px;
}
.form-error {
  margin: 0;
  color: var(--tu-danger);
}
.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}
.form-actions button {
  min-height: 44px;
  border-radius: var(--radius-control);
  padding: 0 16px;
  cursor: pointer;
}
.secondary {
  border: 1px solid var(--tu-action-border);
  background: var(--tu-action-surface);
  color: var(--tu-action);
}
.primary {
  border: 1px solid var(--tu-action);
  background: var(--tu-action);
  color: var(--tu-action-contrast);
}
@media (hover: hover) {
  .secondary:not(:disabled):hover {
    background: var(--tu-action-surface-hover);
  }
  .primary:not(:disabled):hover {
    border-color: var(--tu-action-hover);
    background: var(--tu-action-hover);
  }
}
.secondary:not(:disabled):active {
  background: var(--tu-action-surface-active);
}
.primary:not(:disabled):active {
  border-color: var(--tu-action-active);
  background: var(--tu-action-active);
}
.primary:disabled {
  cursor: not-allowed;
  opacity: 0.5;
}
@media (max-width: 600px) {
  .form-section {
    padding: var(--space-md) 0;
  }
  .form-actions {
    /* At the end of the form, instead of floating over fields or mobile navigation. */
    position: static;
    padding: var(--space-sm) 0;
    border-top: 1px solid var(--tu-border);
  }
  .form-actions button {
    flex: 1;
  }
}
</style>
