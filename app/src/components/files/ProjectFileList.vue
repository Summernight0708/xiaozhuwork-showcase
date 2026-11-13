<script setup lang="ts">
import { computed } from "vue";

import { sortImmutableVersions } from "@/domain/project-files-ui";
import type { ApprovedProjectFile } from "@/types/frontend-integration";

const props = defineProps<{
  files: readonly ApprovedProjectFile[];
}>();

const emit = defineEmits<{
  open: [file: ApprovedProjectFile];
}>();

function currentVersion(file: ApprovedProjectFile) {
  return (
    file.versions.find((version) => version.id === file.currentVersionId) ??
    sortImmutableVersions(file.versions)[0] ??
    null
  );
}

const empty = computed(() => props.files.length === 0);
</script>

<template>
  <div class="project-file-list" :class="{ empty }">
    <table v-if="!empty" class="file-table">
      <colgroup>
        <col class="col-name" />
        <col class="col-task" />
        <col class="col-version" />
        <col class="col-updated" />
        <col class="col-state" />
      </colgroup>
      <thead>
        <tr>
          <th>名称</th>
          <th>所属任务</th>
          <th>版本</th>
          <th>更新</th>
          <th>状态</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="file in files" :key="file.id">
          <td data-label="名称">
            <button
              type="button"
              class="file-anchor"
              :aria-label="'打开文件 ' + file.logicalName"
              @click="emit('open', file)"
            >
              <strong>{{ file.logicalName }}</strong>
              <small>{{ currentVersion(file)?.originalName }}</small>
            </button>
          </td>
          <td data-label="所属任务">{{ file.taskTitle }}</td>
          <td data-label="版本">
            v{{ currentVersion(file)?.versionNumber ?? "—" }}
          </td>
          <td data-label="更新">
            {{
              new Date(file.updatedAt).toLocaleString("zh-CN", {
                month: "numeric",
                day: "numeric",
                hour: "2-digit",
                minute: "2-digit",
              })
            }}
          </td>
          <td data-label="状态">
            <span
              v-if="file.finalVersionIds.length"
              class="final-badge"
              title="该版本已作为任务正式成果确认"
              >最终成果</span
            >
            <span v-else class="muted">—</span>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else class="empty-copy">没有符合筛选条件的文件。</p>
  </div>
</template>

<style scoped>
.project-file-list {
  min-width: 0;
  max-width: 100%;
  overflow: hidden;
  border-top: 1px solid var(--tu-border);
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
}
.file-table {
  width: 100%;
  table-layout: fixed;
  border-collapse: collapse;
}
.col-name {
  width: 32%;
}
.col-task {
  width: 28%;
}
.col-version {
  width: 8%;
}
.col-updated {
  width: 20%;
}
.col-state {
  width: 12%;
}
.file-table th,
.file-table td {
  min-width: 0;
  padding: 14px var(--space-md);
  border-bottom: 1px solid var(--tu-border);
  overflow-wrap: anywhere;
  text-align: left;
  vertical-align: middle;
}
.file-table th {
  color: var(--tu-muted);
  font-size: var(--text-xs);
  font-weight: 600;
  background: var(--tu-subtle-surface);
}
.file-table td:nth-child(3),
.file-table td:nth-child(4) {
  font-variant-numeric: tabular-nums;
}
.file-table tbody tr {
  transition: background-color var(--dur-ui) var(--ease-ui);
}
@media (hover: hover) {
  .file-table tbody tr:hover {
    background: var(--tu-subtle-surface);
  }
}
.file-table tr:last-child td {
  border-bottom: 0;
}
.file-anchor {
  display: grid;
  gap: var(--space-2xs);
  width: 100%;
  min-width: 0;
  max-width: 100%;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.file-anchor strong {
  font-size: var(--text-sm);
}
.file-anchor small {
  color: var(--tu-muted);
  font-size: var(--text-xs);
}
.file-anchor strong,
.file-anchor small {
  min-width: 0;
  overflow-wrap: anywhere;
}
.final-badge {
  display: inline-flex;
  color: var(--tu-success);
  font-size: var(--text-xs);
  font-weight: 650;
}
.empty-copy {
  margin: 0;
  padding: var(--space-2xl) var(--space-md);
  color: var(--tu-muted);
  text-align: center;
}
@media (max-width: 44rem) {
  .file-table colgroup,
  .file-table thead {
    display: none;
  }
  .file-table,
  .file-table tbody,
  .file-table tr,
  .file-table td {
    display: block;
    width: 100%;
  }
  .file-table tr {
    padding: var(--space-sm) 0;
    border-bottom: 1px solid var(--tu-border);
  }
  .file-table tr:last-child {
    border-bottom: 0;
  }
  .file-table td {
    display: grid;
    grid-template-columns: 86px minmax(0, 1fr);
    gap: var(--space-xs);
    padding: 5px var(--space-sm);
    border: 0;
  }
  .file-table td::before {
    content: attr(data-label);
    color: var(--tu-muted);
    font-size: var(--text-xs);
  }
  .file-table td:first-child {
    grid-template-columns: 1fr;
    padding-bottom: var(--space-xs);
  }
  .file-table td:first-child::before {
    display: none;
  }
}
</style>
