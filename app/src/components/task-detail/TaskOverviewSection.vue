<script setup lang="ts">
export interface CollaboratorPresentation {
  id: string;
  name: string;
  state: "accepted" | "pending";
}

withDefaults(
  defineProps<{
    description?: string | null;
    status: string;
    startAt?: string | null;
    deadlineAt: string;
    weight?: number | null;
    primaryName: string;
    collaborators?: readonly CollaboratorPresentation[];
    canManageCollaborators?: boolean;
  }>(),
  {
    description: null,
    startAt: null,
    weight: 1,
    collaborators: () => [],
    canManageCollaborators: false,
  },
);
</script>

<template>
  <div class="overview-grid">
    <div class="description-block">
      <strong>任务描述</strong>
      <p>{{ description || "暂无任务说明。" }}</p>
    </div>
    <dl class="facts">
      <div>
        <dt>状态</dt>
        <dd>{{ status }}</dd>
      </div>
      <div>
        <dt>开始时间</dt>
        <dd>{{ startAt ? new Date(startAt).toLocaleString() : "—" }}</dd>
      </div>
      <div>
        <dt>截止时间</dt>
        <dd>{{ new Date(deadlineAt).toLocaleString() }}</dd>
      </div>
      <div>
        <dt>难度</dt>
        <dd>{{ "★".repeat(Math.max(1, Math.round(weight || 1))) }}</dd>
      </div>
    </dl>
    <slot />
  </div>
</template>

<style scoped>
.overview-grid {
  display: grid;
  gap: 16px;
  padding-top: 16px;
}
.description-block p {
  margin: 7px 0 0;
  line-height: 1.65;
  color: var(--tu-muted);
}
.facts {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0 var(--space-xl);
  margin: 0;
}
.facts div {
  min-width: 0;
  padding: var(--space-sm) 0;
  border-bottom: 1px solid var(--tu-border);
}
.facts dt {
  color: var(--tu-muted);
  font-size: 12px;
}
.facts dd {
  margin: 4px 0 0;
}
.responsibility {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto;
  gap: 12px;
  align-items: start;
}
.responsibility p {
  margin: 5px 0 0;
}
.responsibility ul {
  margin: 5px 0 0;
  padding-left: 18px;
}
.muted {
  color: var(--tu-muted);
}
.plain-action {
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
  font-weight: 700;
}
@media (max-width: 640px) {
  .facts,
  .responsibility {
    grid-template-columns: 1fr;
  }
}
</style>
