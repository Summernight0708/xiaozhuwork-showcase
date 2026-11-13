<script setup lang="ts">
import type { MemberFlowMember } from "@/domain/member-team-work";

defineProps<{
  members: MemberFlowMember[];
  selectedMemberId: string | null;
}>();

const emit = defineEmits<{
  select: [memberId: string | null];
}>();
</script>

<template>
  <nav class="member-list" aria-label="成员列表">
    <button
      type="button"
      class="member-item all-members"
      :class="{ selected: selectedMemberId === null }"
      :aria-current="selectedMemberId === null ? 'true' : undefined"
      @click="emit('select', null)"
    >
      <strong>全部成员</strong>
      <small>团队工作总览</small>
    </button>
    <button
      v-for="member in members"
      :key="member.id"
      type="button"
      class="member-item"
      :class="{ selected: selectedMemberId === member.id }"
      :aria-current="selectedMemberId === member.id ? 'true' : undefined"
      @click="emit('select', member.id)"
    >
      <span class="avatar" aria-hidden="true">{{
        member.displayName.slice(0, 1)
      }}</span>
      <span>
        <strong>{{ member.displayName }} · {{ member.roleLabel }}</strong>
        <small
          >主负责 {{ member.primaryCount }} · 协作
          {{ member.collaboratorCount }}</small
        >
      </span>
    </button>
  </nav>
</template>

<style scoped>
.member-list {
  display: grid;
  align-content: start;
  gap: 4px;
}
.member-item {
  width: 100%;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  align-items: center;
  gap: 10px;
  min-height: 58px;
  padding: 8px 10px;
  border: 0;
  border-radius: 10px;
  background: transparent;
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.member-item:hover,
.member-item:focus-visible,
.member-item.selected {
  background: var(--tu-blue-soft);
  outline: none;
}
.all-members {
  grid-template-columns: 1fr;
}
.member-item strong,
.member-item small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.member-item small {
  margin-top: 4px;
  color: var(--tu-muted);
  font-size: 11px;
}
.avatar {
  width: 34px;
  height: 34px;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: var(--tu-surface);
  border: 1px solid var(--tu-border);
  color: var(--tu-blue-strong);
  font-weight: 800;
}
</style>
