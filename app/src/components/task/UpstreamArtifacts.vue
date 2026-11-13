<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";

import FilePreviewPanel from "@/components/file/FilePreviewPanel.vue";

import {
  artifactHasUpdate,
  latestArtifactVersion,
  type UpstreamArtifact,
  type UpstreamArtifactsSnapshot,
} from "@/domain/artifact-binding";
import { getBackend } from "@/services/backend";
import { createArtifactBindingRepository } from "@/services/artifact-binding-repository";
import type { PreviewFileVersion } from "@/services/file-preview";

const props = defineProps<{
  projectId: string;
  taskId: string;
}>();

const loading = ref(true);
const error = ref("");
const pendingKey = ref("");
const snapshot = ref<UpstreamArtifactsSnapshot | null>(null);
const previewTarget = ref<{
  upstreamTaskId: string;
  fileId: string;
  fileVersionId: string;
} | null>(null);

const artifacts = computed(() => snapshot.value?.artifacts ?? []);
const canBind = computed(() => snapshot.value?.canBind ?? false);
const previewedArtifact = computed(() => {
  const target = previewTarget.value;
  if (!target) return null;
  return (
    artifacts.value.find(
      (artifact) =>
        artifact.upstreamTaskId === target.upstreamTaskId &&
        artifact.fileId === target.fileId,
    ) ?? null
  );
});
const previewedVersion = computed(() => {
  const target = previewTarget.value;
  return (
    previewedArtifact.value?.versions.find(
      (version) => version.fileVersionId === target?.fileVersionId,
    ) ?? null
  );
});

function requestId() {
  return globalThis.crypto.randomUUID();
}

async function load() {
  const backend = getBackend();
  if (!backend) {
    snapshot.value = {
      downstreamTaskId: props.taskId,
      canBind: false,
      artifacts: [],
    };
    loading.value = false;
    return;
  }

  loading.value = true;
  error.value = "";
  try {
    snapshot.value = await createArtifactBindingRepository(
      backend.client,
    ).listUpstreamArtifacts(props.taskId);
  } catch {
    error.value = "无法加载上游成果";
  } finally {
    loading.value = false;
  }
}

function openVersion(artifact: UpstreamArtifact, fileVersionId: string) {
  if (!artifact.versions.some((item) => item.fileVersionId === fileVersionId))
    return;
  error.value = "";
  previewTarget.value = {
    upstreamTaskId: artifact.upstreamTaskId,
    fileId: artifact.fileId,
    fileVersionId,
  };
}

function previewFileVersion(): PreviewFileVersion | null {
  const version = previewedVersion.value;
  if (!version) return null;
  return {
    id: version.fileVersionId,
    originalName: version.originalName,
    mimeType: version.mimeType,
    sizeBytes: version.sizeBytes,
    versionNumber: version.versionNumber,
    createdAt: version.createdAt,
  };
}

async function recordPreviewUse(fileVersionId: string) {
  const target = previewTarget.value;
  const artifact = previewedArtifact.value;
  if (
    !target ||
    !artifact ||
    target.fileVersionId !== fileVersionId ||
    !artifact.versions.some(
      (version) => version.fileVersionId === fileVersionId,
    ) ||
    !canBind.value
  ) {
    return;
  }

  const backend = getBackend();
  if (!backend) return;
  pendingKey.value = `bind:${fileVersionId}`;
  error.value = "";
  try {
    const result = await createArtifactBindingRepository(
      backend.client,
    ).recordArtifactUse({
      projectId: props.projectId,
      downstreamTaskId: props.taskId,
      fileVersionId,
      requestId: requestId(),
    });
    if (!result.ok) error.value = "预览成功，但未能记录当前使用版本";
    await load();
  } catch {
    error.value = "预览成功，但未能记录当前使用版本";
  } finally {
    pendingKey.value = "";
  }
}

async function switchVersion(artifact: UpstreamArtifact) {
  const backend = getBackend();
  const latest = latestArtifactVersion(artifact);
  const binding = artifact.binding;
  if (!backend || !latest || !binding || !canBind.value) return;

  pendingKey.value = `switch:${artifact.fileId}`;
  error.value = "";
  try {
    const result = await createArtifactBindingRepository(
      backend.client,
    ).switchBindingVersion({
      projectId: props.projectId,
      downstreamTaskId: props.taskId,
      fileVersionId: latest.fileVersionId,
      requestId: requestId(),
      expectedVersion: binding.version,
    });
    if (!result.ok) {
      error.value =
        result.code === "STALE_VERSION"
          ? "绑定已被其他操作更新，请重试"
          : "无法切换成果版本";
    }
    await load();
  } catch {
    error.value = "无法切换成果版本";
  } finally {
    pendingKey.value = "";
  }
}

async function toggleStrong(artifact: UpstreamArtifact) {
  const backend = getBackend();
  const latest = latestArtifactVersion(artifact);
  const binding = artifact.binding;
  if (!backend || !latest || !canBind.value) return;

  const targetStrength = binding?.strength === "strong" ? "light" : "strong";
  const fileVersionId = binding?.fileVersionId ?? latest.fileVersionId;
  const expectedVersion = binding?.version ?? 0;

  pendingKey.value = `strength:${artifact.fileId}`;
  error.value = "";
  try {
    const result = await createArtifactBindingRepository(
      backend.client,
    ).setBindingStrength({
      projectId: props.projectId,
      downstreamTaskId: props.taskId,
      fileVersionId,
      strength: targetStrength,
      requestId: requestId(),
      expectedVersion,
    });
    if (!result.ok) {
      error.value =
        result.code === "STALE_VERSION"
          ? "绑定已被其他操作更新，请重试"
          : "无法更新绑定强度";
    }
    await load();
  } catch {
    error.value = "无法更新绑定强度";
  } finally {
    pendingKey.value = "";
  }
}

watch(
  () => props.taskId,
  () => void load(),
);
onMounted(() => void load());
</script>

<template>
  <section class="surface surface-padded upstream-artifacts">
    <div class="artifact-section-heading">
      <div>
        <h2 class="section-title">上游成果</h2>
        <p class="artifact-help">
          成功预览直接上游的正式成果会记录轻绑定；强绑定会在上游出现正式新版时额外通知你。
        </p>
      </div>
    </div>

    <p v-if="loading" class="artifact-muted">正在加载上游成果…</p>
    <p v-else-if="error && !artifacts.length" class="artifact-error">
      {{ error }}
    </p>
    <p v-else-if="!artifacts.length" class="artifact-muted">
      暂无可使用的上游正式成果。
    </p>

    <div v-else class="artifact-list">
      <article
        v-for="artifact in artifacts"
        :key="`${artifact.upstreamTaskId}:${artifact.fileId}`"
        class="artifact-card"
      >
        <div class="artifact-card-heading">
          <div>
            <strong>{{ artifact.logicalName }}</strong>
            <span class="artifact-upstream">{{
              artifact.upstreamTaskTitle
            }}</span>
          </div>
          <button
            v-if="canBind"
            type="button"
            class="binding-button"
            :class="{ strong: artifact.binding?.strength === 'strong' }"
            :aria-pressed="artifact.binding?.strength === 'strong'"
            :aria-label="
              artifact.binding?.strength === 'strong'
                ? '取消强绑定'
                : '强绑定此成果'
            "
            :title="
              artifact.binding?.strength === 'strong'
                ? '取消强绑定'
                : '强绑定此成果'
            "
            :disabled="pendingKey === `strength:${artifact.fileId}`"
            @click="toggleStrong(artifact)"
          >
            🔗
          </button>
        </div>

        <div class="artifact-version-summary">
          <span v-if="artifact.binding">
            当前使用：v{{ artifact.binding.boundVersionNumber }}
            <em v-if="artifact.binding.strength === 'strong'">强绑定</em>
            <em v-else>轻绑定</em>
          </span>
          <span v-else>当前使用：尚未绑定</span>
          <span v-if="latestArtifactVersion(artifact)">
            最新版本：v{{ latestArtifactVersion(artifact)?.versionNumber }}
          </span>
        </div>

        <p
          v-if="artifactHasUpdate(artifact)"
          class="artifact-update"
          role="status"
        >
          ⚠ 上游成果已有更新
        </p>

        <div class="artifact-actions">
          <button
            v-if="latestArtifactVersion(artifact)"
            type="button"
            class="artifact-action"
            @click="
              openVersion(
                artifact,
                latestArtifactVersion(artifact)!.fileVersionId,
              )
            "
          >
            查看 v{{ latestArtifactVersion(artifact)?.versionNumber }}
          </button>
          <button
            v-if="artifactHasUpdate(artifact) && canBind"
            type="button"
            class="artifact-action primary"
            :disabled="pendingKey === `switch:${artifact.fileId}`"
            @click="switchVersion(artifact)"
          >
            切换到 v{{ latestArtifactVersion(artifact)?.versionNumber }}
          </button>
        </div>
      </article>
    </div>

    <FilePreviewPanel
      v-if="previewedVersion && previewFileVersion()"
      :project-id="projectId"
      :file-version="previewFileVersion()!"
      @close="previewTarget = null"
      @preview-success="recordPreviewUse"
    />

    <p v-if="error && artifacts.length" class="artifact-error" role="alert">
      {{ error }}
    </p>
  </section>
</template>

<style scoped>
.upstream-artifacts {
  display: grid;
  gap: 14px;
}

.artifact-section-heading,
.artifact-card-heading,
.artifact-version-summary,
.artifact-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.artifact-help,
.artifact-muted,
.artifact-upstream {
  color: var(--tu-muted);
}

.artifact-help {
  margin: 4px 0 0;
  font-size: 13px;
}

.artifact-list {
  display: grid;
  gap: 12px;
}

.artifact-card {
  display: grid;
  gap: 10px;
  padding: 14px;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
}

.artifact-card-heading > div {
  display: grid;
  gap: 3px;
}

.artifact-upstream {
  font-size: 12px;
}

.artifact-version-summary {
  justify-content: flex-start;
  flex-wrap: wrap;
  font-size: 13px;
}

.artifact-version-summary em {
  margin-left: 6px;
  font-style: normal;
  color: var(--tu-muted);
}

.binding-button,
.artifact-action {
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
  color: inherit;
  cursor: pointer;
  min-height: 36px;
}

.binding-button {
  width: 38px;
  font-size: 18px;
}

.binding-button.strong {
  font-weight: 700;
  box-shadow: inset 0 0 0 2px currentColor;
}

.artifact-actions {
  justify-content: flex-start;
  flex-wrap: wrap;
}

.artifact-action {
  padding: 0 12px;
}

.artifact-action.primary {
  font-weight: 600;
}

.binding-button:disabled,
.artifact-action:disabled {
  cursor: wait;
  opacity: 0.55;
}

.artifact-update,
.artifact-error {
  margin: 0;
}

.artifact-update {
  font-size: 13px;
  font-weight: 600;
}

.artifact-error {
  color: var(--tu-danger);
  font-size: 13px;
}

@media (max-width: 767px) {
  .artifact-card-heading {
    align-items: flex-start;
  }

  .artifact-version-summary {
    display: grid;
    justify-content: stretch;
  }

  .artifact-actions {
    display: grid;
    grid-template-columns: 1fr;
  }

  .artifact-action {
    width: 100%;
  }
}
</style>
