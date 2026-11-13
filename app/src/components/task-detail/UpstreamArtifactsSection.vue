<script setup lang="ts">
import { ref, watch } from "vue";

import type {
  UpstreamArtifactGroup,
  UpstreamArtifactPresentation,
} from "@/types/frontend-integration";

const props = defineProps<{
  groups: readonly UpstreamArtifactGroup[];
  canBind?: boolean;
  trustedPreviewSuccessVersionId?: string | null;
}>();

const emit = defineEmits<{
  preview: [artifact: UpstreamArtifactPresentation];
  lightBind: [artifact: UpstreamArtifactPresentation];
  strongBind: [artifact: UpstreamArtifactPresentation];
  switchVersion: [artifact: UpstreamArtifactPresentation];
}>();

const pendingPreviewVersionId = ref<string | null>(null);
const pendingPreviewArtifact = ref<UpstreamArtifactPresentation | null>(null);

function preview(artifact: UpstreamArtifactPresentation) {
  pendingPreviewVersionId.value = artifact.latestVersionId;
  pendingPreviewArtifact.value = artifact;
  emit("preview", artifact);
}

watch(
  () => props.trustedPreviewSuccessVersionId,
  (versionId) => {
    if (
      !props.canBind ||
      !versionId ||
      versionId !== pendingPreviewVersionId.value ||
      !pendingPreviewArtifact.value
    ) {
      return;
    }
    emit("lightBind", pendingPreviewArtifact.value);
    pendingPreviewVersionId.value = null;
    pendingPreviewArtifact.value = null;
  },
);
</script>

<template>
  <div class="upstream-artifacts">
    <article v-for="group in groups" :key="group.taskId" class="upstream-group">
      <header>
        <div>
          <strong>{{ group.taskTitle }}</strong>
          <small>{{ group.taskStatus }}</small>
        </div>
      </header>
      <div v-if="group.artifacts.length" class="artifact-list">
        <div
          v-for="artifact in group.artifacts"
          :key="artifact.fileId + ':' + artifact.versionId"
          class="artifact-row"
        >
          <div class="artifact-copy">
            <strong>{{ artifact.name }}</strong>
            <span>v{{ artifact.latestVersionNumber }} · 最新</span>
            <small v-if="artifact.binding.kind === 'light'">
              已参考 v{{ artifact.binding.versionNumber }} · 轻绑定
            </small>
            <small v-else-if="artifact.binding.kind === 'strong'">
              当前强绑定 v{{ artifact.binding.versionNumber }}
            </small>
          </div>
          <div class="artifact-actions">
            <button
              type="button"
              :aria-label="'预览上游成果 ' + artifact.name"
              @click="preview(artifact)"
            >
              预览 v{{ artifact.latestVersionNumber }}
            </button>
            <template v-if="canBind">
              <button
                v-if="artifact.binding.kind !== 'strong'"
                type="button"
                aria-label="设为强绑定"
                @click="emit('strongBind', artifact)"
              >
                设为强绑定
              </button>
              <button
                v-if="
                  artifact.binding.kind === 'strong' &&
                  artifact.binding.versionId !== artifact.latestVersionId
                "
                type="button"
                @click="emit('switchVersion', artifact)"
              >
                切换到 v{{ artifact.latestVersionNumber }}
              </button>
            </template>
          </div>
        </div>
      </div>
      <p v-else class="muted">该直接上游当前没有正式成果。</p>
    </article>
  </div>
</template>

<style scoped>
.upstream-artifacts {
  display: grid;
  gap: 12px;
}
.upstream-group {
  padding: var(--space-md) 0;
  border-top: 1px solid var(--tu-border);
}
.upstream-group header > div,
.artifact-copy {
  display: grid;
  gap: 3px;
}
.upstream-group small,
.artifact-copy span,
.artifact-copy small,
.muted {
  color: var(--tu-muted);
}
.artifact-list {
  display: grid;
  gap: 0;
  margin-top: var(--space-sm);
}
.artifact-row {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  padding: var(--space-sm) 0;
  border-bottom: 1px solid var(--tu-border);
  background: transparent;
}
.artifact-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 7px;
  align-items: center;
}
.artifact-actions button {
  min-height: 36px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  color: var(--tu-blue-strong);
  cursor: pointer;
  font-weight: 700;
}
@media (max-width: 640px) {
  .artifact-row {
    display: grid;
  }
}
</style>
