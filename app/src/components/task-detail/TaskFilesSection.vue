<script setup lang="ts">
import { computed } from "vue";
import type { TaskFile, TaskFileVersion } from "@/types/ui";

const props = defineProps<{
  files: readonly TaskFile[];
  canUpload?: boolean;
  busy?: boolean;
}>();

const emit = defineEmits<{
  upload: [];
  preview: [version: TaskFileVersion];
  download: [version: TaskFileVersion];
}>();

const referenceFiles = computed(() =>
  props.files.filter((file) => file.purpose === "reference"),
);
const deliverableFiles = computed(() =>
  props.files.filter((file) => file.purpose !== "reference"),
);
const groups = computed(() =>
  [
    {
      label: "任务资料",
      hint: "创建任务时提供，仅供参考",
      files: referenceFiles.value,
    },
    { label: "成果文件", hint: "", files: deliverableFiles.value },
  ].filter((group) => group.files.length),
);

function latestVersion(file: TaskFile) {
  return (
    file.versions.find(
      (version) => version.fileVersionId === file.currentVersionId,
    ) ??
    [...file.versions].sort((a, b) => b.versionNumber - a.versionNumber)[0] ??
    null
  );
}
</script>

<template>
  <div class="task-files">
    <header class="subheading">
      <strong>任务文件</strong>
      <button
        v-if="canUpload"
        type="button"
        class="plain-action"
        :disabled="busy"
        @click="emit('upload')"
      >
        上传文件
      </button>
    </header>
    <div v-if="files.length" class="file-groups">
      <section v-for="group in groups" :key="group.label" class="file-group">
        <div class="group-label">
          <strong>{{ group.label }}</strong>
          <span v-if="group.hint">{{ group.hint }}</span>
        </div>
        <div class="file-list">
          <article
            v-for="file in group.files"
            :key="file.fileId"
            class="file-row"
          >
            <div>
              <strong>{{ file.logicalName }}</strong>
              <span v-if="latestVersion(file)">
                v{{ latestVersion(file)?.versionNumber }} ·
                {{ latestVersion(file)?.originalName }}
              </span>
            </div>
            <div v-if="latestVersion(file)" class="file-actions">
              <button
                type="button"
                :aria-label="'预览任务文件 ' + file.logicalName"
                @click="emit('preview', latestVersion(file)!)"
              >
                预览
              </button>
              <button
                type="button"
                :aria-label="'下载任务文件 ' + file.logicalName"
                @click="emit('download', latestVersion(file)!)"
              >
                下载
              </button>
            </div>
          </article>
        </div>
      </section>
    </div>
    <p v-else class="muted">尚无任务文件。</p>
  </div>
</template>

<style scoped>
.task-files {
  display: grid;
  gap: 10px;
}
.subheading,
.file-row,
.file-actions {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  align-items: center;
}
.file-list {
  display: grid;
  gap: 0;
  border-top: 1px solid var(--tu-border);
}
.file-groups,
.file-group {
  display: grid;
  gap: 10px;
}
.file-group + .file-group {
  margin-top: 8px;
}
.group-label {
  display: flex;
  align-items: baseline;
  gap: 8px;
}
.group-label span {
  color: var(--tu-muted);
  font-size: 12px;
}
.file-row {
  padding: var(--space-md) 0;
  border-bottom: 1px solid var(--tu-border);
  background: transparent;
}
.file-row > div:first-child {
  display: grid;
  gap: 4px;
}
.file-row span,
.muted {
  color: var(--tu-muted);
  font-size: 13px;
}
.file-actions button,
.plain-action {
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
  font-weight: 700;
}
@media (max-width: 560px) {
  .file-row {
    align-items: flex-start;
    flex-direction: column;
  }
}
</style>
