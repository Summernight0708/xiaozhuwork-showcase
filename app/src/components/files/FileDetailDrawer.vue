<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";

import FileVersionHistory from "@/components/files/FileVersionHistory.vue";
import { sortImmutableVersions } from "@/domain/project-files-ui";
import type {
  ApprovedFileVersion,
  ApprovedProjectFile,
} from "@/types/frontend-integration";

const props = defineProps<{
  show: boolean;
  file: ApprovedProjectFile | null;
  canUpload?: boolean;
  canMarkFinal?: boolean;
  busy?: boolean;
}>();

const emit = defineEmits<{
  close: [];
  preview: [version: ApprovedFileVersion];
  download: [version: ApprovedFileVersion];
  uploadNewVersion: [];
  toggleFinal: [version: ApprovedFileVersion, isFinal: boolean];
}>();

const closeButton = ref<HTMLButtonElement | null>(null);

const currentVersion = computed(() => {
  const file = props.file;
  if (!file) return null;
  return (
    file.versions.find((version) => version.id === file.currentVersionId) ??
    sortImmutableVersions(file.versions)[0] ??
    null
  );
});

function toggleFinal(version: ApprovedFileVersion, isFinal: boolean) {
  emit("toggleFinal", version, isFinal);
}

watch(
  () => props.show,
  async (show) => {
    if (!show) return;
    await nextTick();
    closeButton.value?.focus();
  },
);
</script>

<template>
  <van-popup
    :show="show && !!file"
    class="file-detail-popup"
    position="right"
    :style="{ height: '100%' }"
    teleport="body"
    @click-overlay="emit('close')"
  >
    <section
      v-if="file"
      class="file-drawer"
      role="dialog"
      aria-modal="true"
      :aria-label="'文件详情 ' + file.logicalName"
      @keydown.esc.stop.prevent="emit('close')"
    >
      <header class="drawer-header">
        <div>
          <span class="eyebrow">文件</span>
          <h2>{{ file.logicalName }}</h2>
        </div>
        <button
          ref="closeButton"
          type="button"
          class="close-button"
          aria-label="关闭文件详情"
          @click="emit('close')"
        >
          关闭
        </button>
      </header>

      <div class="file-facts">
        <span><b>所属任务</b>{{ file.taskTitle }}</span>
        <span><b>当前版本</b>v{{ currentVersion?.versionNumber ?? "—" }}</span>
        <span><b>上传者</b>{{ file.uploaderName }}</span>
        <span>
          <b>状态</b>
          {{ file.finalVersionIds.length ? "最终成果" : "普通文件" }}
        </span>
      </div>

      <div v-if="currentVersion" class="current-actions">
        <button
          type="button"
          class="primary-action"
          @click="emit('preview', currentVersion)"
        >
          预览当前版本
        </button>
        <button
          type="button"
          class="secondary-action"
          @click="emit('download', currentVersion)"
        >
          下载
        </button>
        <button
          v-if="canUpload"
          type="button"
          class="secondary-action"
          :disabled="busy"
          @click="emit('uploadNewVersion')"
        >
          上传新版本
        </button>
      </div>

      <section class="history-section">
        <h3>版本历史</h3>
        <FileVersionHistory
          :versions="file.versions"
          :final-version-ids="file.finalVersionIds"
          :can-mark-final="canMarkFinal"
          :busy="busy"
          @preview="emit('preview', $event)"
          @download="emit('download', $event)"
          @toggle-final="toggleFinal"
        />
      </section>
    </section>
  </van-popup>
</template>

<style scoped>
.file-detail-popup {
  width: min(620px, 96vw);
  max-width: 100vw;
}
.file-drawer {
  width: 100%;
  max-width: 100%;
  min-width: 0;
  height: 100%;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 22px;
  background: var(--tu-bg);
}
.drawer-header {
  display: flex;
  justify-content: space-between;
  gap: 18px;
  align-items: flex-start;
  min-width: 0;
}
.drawer-header > div {
  min-width: 0;
}
.drawer-header h2 {
  margin: 4px 0 0;
  overflow-wrap: anywhere;
}
.eyebrow {
  color: var(--tu-muted);
  font-size: 12px;
}
.close-button,
.secondary-action {
  min-height: 44px;
  padding: 0 12px;
  border: 1px solid var(--tu-action-border);
  border-radius: 9px;
  background: var(--tu-action-surface);
  color: var(--tu-action);
  cursor: pointer;
}
@media (hover: hover) {
  .close-button:not(:disabled):hover,
  .secondary-action:not(:disabled):hover {
    background: var(--tu-action-surface-hover);
  }
}
.close-button:not(:disabled):active,
.secondary-action:not(:disabled):active {
  background: var(--tu-action-surface-active);
}
.close-button {
  flex: 0 0 auto;
}
.file-facts {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin: 18px 0;
}
.file-facts span {
  display: grid;
  gap: 3px;
  min-width: 0;
  padding: 12px;
  border-radius: 10px;
  background: var(--tu-surface);
  color: var(--tu-muted);
  overflow-wrap: anywhere;
}
.file-facts b {
  color: var(--tu-ink);
}
.current-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  min-width: 0;
  margin-bottom: 22px;
}
.primary-action {
  min-height: 44px;
  padding: 0 14px;
  border: 0;
  border-radius: 9px;
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  cursor: pointer;
  font-weight: 700;
}
@media (hover: hover) {
  .primary-action:not(:disabled):hover {
    background: var(--tu-action-hover);
  }
}
.primary-action:not(:disabled):active {
  background: var(--tu-action-active);
}
.primary-action,
.secondary-action {
  max-width: 100%;
}
.history-section {
  min-width: 0;
}
.history-section h3 {
  margin: 0 0 10px;
}
@media (max-width: 560px) {
  .file-detail-popup {
    width: 100vw;
    max-width: 100vw;
  }
  .file-drawer {
    padding: max(16px, env(safe-area-inset-top))
      max(14px, env(safe-area-inset-right))
      max(16px, env(safe-area-inset-bottom))
      max(14px, env(safe-area-inset-left));
  }
  .drawer-header {
    gap: 10px;
  }
  .file-facts {
    grid-template-columns: minmax(0, 1fr);
  }
  .current-actions {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
  }
  .current-actions button {
    width: 100%;
  }
}
</style>
