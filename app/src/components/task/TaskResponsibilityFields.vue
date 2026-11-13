<script setup lang="ts">
import type { MembershipRow } from "@/types/ui";
import { vDismissibleDetails } from "@/directives/dismissible-details";

const props = defineProps<{
  assignmentMode: "direct" | "claimable";
  assigneeId: string;
  collaboratorIds: readonly string[];
  members: readonly MembershipRow[];
  supportsCollaborators: boolean;
}>();

const emit = defineEmits<{
  updateAssignmentMode: [value: "direct" | "claimable"];
  updateAssigneeId: [value: string];
  updateCollaboratorIds: [value: string[]];
}>();

function eligibleMembers() {
  return props.members.filter(
    (member) =>
      !member.is_observer && member.role !== "observer" && member.user_id,
  );
}

function setMode(value: "direct" | "claimable") {
  emit("updateAssignmentMode", value);
  if (value === "claimable") {
    emit("updateAssigneeId", "");
    emit("updateCollaboratorIds", []);
  }
}

function setAssignee(value: string) {
  emit("updateAssigneeId", value);
  emit(
    "updateCollaboratorIds",
    props.collaboratorIds.filter((id) => id !== value),
  );
}

function toggleCollaborator(userId: string) {
  if (userId === props.assigneeId) return;
  const next = props.collaboratorIds.includes(userId)
    ? props.collaboratorIds.filter((id) => id !== userId)
    : [...props.collaboratorIds, userId];
  emit("updateCollaboratorIds", next);
}
</script>

<template>
  <fieldset class="responsibility-fields">
    <legend>主负责人</legend>
    <label class="choice">
      <input
        type="radio"
        :checked="assignmentMode === 'direct'"
        @change="setMode('direct')"
      />
      <span>指定成员</span>
    </label>
    <label class="choice">
      <input
        type="radio"
        :checked="assignmentMode === 'claimable'"
        @change="setMode('claimable')"
      />
      <span>暂不指定，开放认领</span>
    </label>

    <p v-if="assignmentMode === 'claimable'" class="field-note">
      该任务将进入「待认领任务」区域，符合规则的成员可以主动认领。
    </p>

    <label v-else class="select-field">
      <span>主负责人</span>
      <select
        :value="assigneeId"
        required
        @change="setAssignee(($event.target as HTMLSelectElement).value)"
      >
        <option value="" disabled>请选择成员</option>
        <option
          v-for="member in eligibleMembers()"
          :key="member.id"
          :value="member.user_id || ''"
        >
          {{ member.display_name_snapshot || "未命名成员" }}
        </option>
      </select>
    </label>

    <div
      v-if="supportsCollaborators && assignmentMode === 'direct' && assigneeId"
      class="collaborators"
    >
      <span class="field-label">协作者</span>
      <details v-dismissible-details>
        <summary>+ 添加协作者</summary>
        <label
          v-for="member in eligibleMembers().filter(
            (item) => item.user_id !== assigneeId,
          )"
          :key="member.id"
          class="collaborator-option"
        >
          <input
            type="checkbox"
            :checked="collaboratorIds.includes(member.user_id || '')"
            @change="toggleCollaborator(member.user_id || '')"
          />
          {{ member.display_name_snapshot || "未命名成员" }}
        </label>
      </details>
      <p class="field-note">选中的成员将收到协作邀请，接受后才成为协作者。</p>
    </div>
  </fieldset>
</template>

<style scoped>
.responsibility-fields {
  display: grid;
  gap: 10px;
  margin: 0;
  padding: 0;
  border: 0;
}
.responsibility-fields legend,
.field-label {
  margin-bottom: 2px;
  color: var(--tu-ink);
  font-weight: 700;
}
.choice {
  display: flex;
  align-items: center;
  gap: 8px;
}
.select-field {
  display: grid;
  gap: 6px;
  margin-top: 4px;
}
.select-field select,
.collaborators details {
  min-height: 42px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.select-field select {
  padding: 0 10px;
}
.collaborators {
  display: grid;
  gap: 7px;
  margin-top: 4px;
}
.collaborators summary {
  padding: 10px;
  cursor: pointer;
}
.collaborator-option {
  display: flex;
  gap: 8px;
  padding: 8px 10px;
}
.field-note {
  margin: 0;
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.5;
}
</style>
