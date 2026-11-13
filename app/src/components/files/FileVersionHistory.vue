<script setup lang="ts">
import {
  isPreviewSupported,
  sortImmutableVersions,
} from "@/domain/project-files-ui";
import type { ApprovedFileVersion } from "@/types/frontend-integration";

const props = defineProps<{
  versions: readonly ApprovedFileVersion[];
  finalVersionIds?: readonly string[];
  canMarkFinal?: boolean;
  busy?: boolean;
}>();

const emit = defineEmits<{
  preview: [version: ApprovedFileVersion];
  download: [version: ApprovedFileVersion];
  toggleFinal: [version: ApprovedFileVersion, isFinal: boolean];
}>();

function isFinal(versionId: string) {
  return props.finalVersionIds?.includes(versionId) ?? false;
}
</script>

<template>
  <div class="version-history">
    <article
      v-for="version in sortImmutableVersions(versions)"
      :key="version.id"
      class="version-row"
    >
      <div class="version-copy">
        <div class="version-title">
          <strong>v{{ version.versionNumber }}</strong>
          <span v-if="isFinal(version.id)" class="final-badge">最终成果</span>
        </div>
        <span>{{ version.originalName }}</span>
        <small>{{ new Date(version.createdAt).toLocaleString() }}</small>
      </div>
      <div class="version-actions">
        <button
          v-if="isPreviewSupported(version.originalName, version.mimeType)"
          type="button"
          class="plain-action"
          :aria-label="
            '预览 v' + version.versionNumber + ' ' + version.originalName
          "
          @click="emit('preview', version)"
        >
          预览
        </button>
        <span v-else class="unsupported">该格式暂不支持在线预览</span>
        <button
          type="button"
          class="plain-action"
          :aria-label="
            '下载 v' + version.versionNumber + ' ' + version.originalName
          "
          @click="emit('download', version)"
        >
          下载
        </button>
        <button
          v-if="canMarkFinal"
          type="button"
          class="plain-action"
          :disabled="busy"
          :aria-label="
            (isFinal(version.id) ? '取消最终 ' : '标记最终 ') +
            'v' +
            version.versionNumber +
            ' ' +
            version.originalName
          "
          @click="emit('toggleFinal', version, !isFinal(version.id))"
        >
          {{ isFinal(version.id) ? "取消最终" : "标记最终" }}
        </button>
      </div>
    </article>
  </div>
</template>

<style scoped>
.version-history {
  display: grid;
  gap: 10px;
}
.version-row {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  padding: 12px;
  border: 1px solid var(--tu-border);
  border-radius: 10px;
  background: var(--tu-surface);
}
.version-copy,
.version-actions {
  display: grid;
  gap: 5px;
}
.version-copy {
  min-width: 0;
}
.version-actions {
  min-width: 0;
}
.version-copy > span,
.version-copy small {
  overflow-wrap: anywhere;
}
.version-copy small,
.unsupported {
  color: var(--tu-muted);
  font-size: 12px;
}
.version-title {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  min-width: 0;
}
.final-badge {
  padding: 2px 7px;
  border-radius: 999px;
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
  font-size: 11px;
  font-weight: 700;
}
.version-actions {
  justify-items: end;
  align-content: center;
}
.plain-action {
  min-height: 36px;
  border: 0;
  background: transparent;
  color: var(--tu-blue-strong);
  cursor: pointer;
  padding: 0 6px;
  font-weight: 700;
}
@media (max-width: 640px) {
  .version-row {
    display: grid;
  }
  .version-actions {
    display: flex;
    flex-wrap: wrap;
    justify-items: initial;
    justify-content: flex-start;
  }
  .unsupported {
    flex: 1 1 100%;
    overflow-wrap: anywhere;
  }
  .plain-action {
    min-height: 40px;
  }
}
</style>
