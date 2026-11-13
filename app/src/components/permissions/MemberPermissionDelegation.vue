<script setup lang="ts">
import {
  delegationAssigned,
  delegationEffective,
  PROJECT_PERMISSION_TEMPLATES,
  TEMPLATE_DETAILS,
  type PermissionMember,
  type PermissionSnapshot,
  type ProjectPermissionTemplate,
} from "@/services/project-permissions";

defineProps<{
  members: PermissionMember[];
  snapshot: PermissionSnapshot;
  pendingMemberId: string | null;
  canEdit: boolean;
}>();

const emit = defineEmits<{
  change: [
    membershipId: string,
    templateCode: ProjectPermissionTemplate,
    enabled: boolean,
    expectedVersion: number,
  ];
}>();
</script>

<template>
  <section class="surface delegation-manager">
    <h2>成员权限分配</h2>
    <p v-if="members.length === 0">暂无可授权的活动普通成员。</p>
    <div v-for="member in members" :key="member.id" class="member-row">
      <div class="member-label">
        <strong>{{ member.displayName }}</strong>
        <span>普通成员 · v{{ member.version }}</span>
      </div>
      <div class="template-actions">
        <div
          v-for="code in PROJECT_PERMISSION_TEMPLATES"
          :key="code"
          class="template-action"
        >
          <div>
            <span>{{ TEMPLATE_DETAILS[code].name }}</span>
            <small v-if="delegationEffective(snapshot, member.id, code)"
              >生效中</small
            >
            <small v-else-if="delegationAssigned(snapshot, member.id, code)"
              >已分配 · 暂不生效</small
            >
            <small v-else>未分配</small>
          </div>
          <button
            type="button"
            :disabled="!canEdit || pendingMemberId !== null"
            :aria-label="
              (delegationAssigned(snapshot, member.id, code)
                ? '撤销'
                : '授予') + TEMPLATE_DETAILS[code].name
            "
            @click="
              emit(
                'change',
                member.id,
                code,
                !delegationAssigned(snapshot, member.id, code),
                member.version,
              )
            "
          >
            {{
              delegationAssigned(snapshot, member.id, code) ? "撤销" : "授予"
            }}
          </button>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.delegation-manager {
  padding: 1rem;
}
.member-row {
  border-top: 1px solid var(--tu-border);
  padding: 1rem 0;
  display: grid;
  gap: 0.75rem;
}
.member-label {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem;
}
.member-label span,
small {
  color: var(--tu-muted);
  font-size: 0.8rem;
}
.template-actions {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 0.75rem;
}
.template-action {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 0.75rem;
}
.template-action > div {
  display: grid;
  gap: 0.25rem;
}
button {
  border: 1px solid var(--tu-blue-strong);
  border-radius: 0.5rem;
  padding: 0.4rem 0.8rem;
  background: var(--tu-surface);
  color: var(--tu-blue-strong);
  cursor: pointer;
  min-height: 44px;
}
button:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
</style>
