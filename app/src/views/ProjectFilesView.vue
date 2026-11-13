<script setup lang="ts">
import ContextHelpLink from "@/components/help/ContextHelpLink.vue";
defineOptions({ name: "ProjectFilesView" });

import { computed, nextTick, onActivated, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showToast } from "vant";

import FilePreviewPanel from "@/components/file/FilePreviewPanel.vue";
import FileDetailDrawer from "@/components/files/FileDetailDrawer.vue";
import { isFinalDesignationEligibleFile } from "@/domain/final-file-access";
import ProjectFileList from "@/components/files/ProjectFileList.vue";
import PageState from "@/components/common/PageState.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  buildApprovedProjectFiles,
  matchesApprovedProjectFile,
  type ApprovedFileRangeFilter,
  type ApprovedFileTypeFilter,
} from "@/domain/project-files-ui";
import {
  createDownloadUrl,
  openDownload,
  type PreviewFileVersion,
} from "@/services/file-preview";
import type {
  ApprovedFileVersion,
  ApprovedProjectFile,
} from "@/types/frontend-integration";

const route = useRoute();
function formatStorageBytes(bytes: number) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 ** 2) return (bytes / 1024).toFixed(1) + " KiB";
  if (bytes < 0.01 * 1024 ** 3) return (bytes / 1024 ** 2).toFixed(1) + " MiB";
  return (bytes / 1024 ** 3).toFixed(2) + " GiB";
}
const router = useRouter();
const { workspace, reload } = useWorkspaceRoute();

const search = ref("");
const typeFilter = ref<ApprovedFileTypeFilter>("all");
const rangeFilter = ref<ApprovedFileRangeFilter>("all");
const showMobileFilters = ref(false);
const selectedFileId = ref<string | null>(
  typeof route.params.fileId === "string" ? route.params.fileId : null,
);
const filesLoaded = ref(false);
const uploadInput = ref<HTMLInputElement | null>(null);
const uploadTaskId = ref("");
const uploadMode = ref<"new_file" | "new_version">("new_file");
const uploadTargetFileId = ref<string | undefined>();
const failedUpload = ref<{
  file: File;
  taskId: string;
  mode: "new_file" | "new_version";
  targetFileId?: string;
} | null>(null);
const previewTarget = ref<ApprovedFileVersion | null>(null);

let fileTriggerElement: HTMLElement | null = null;

const approvedFiles = computed(() =>
  buildApprovedProjectFiles({
    files: workspace.files,
    versions: workspace.fileVersions,
    designations: workspace.fileFinalDesignations,
    tasks: workspace.tasks,
    memberName: workspace.memberName,
  }),
);

const rows = computed(() =>
  approvedFiles.value
    .filter((file) =>
      matchesApprovedProjectFile(file, {
        search: search.value,
        type: typeFilter.value,
        range: rangeFilter.value,
      }),
    )
    .sort((a, b) => a.logicalName.localeCompare(b.logicalName)),
);

const selectedFile = computed(
  () =>
    approvedFiles.value.find((file) => file.id === selectedFileId.value) ??
    null,
);

const canMarkSelectedFileFinal = computed(
  () =>
    workspace.capabilities.canMarkFinalFiles &&
    isFinalDesignationEligibleFile(selectedFile.value?.purpose),
);

const invalidFileDeepLink = computed(
  () =>
    filesLoaded.value && !!selectedFileId.value && selectedFile.value === null,
);

async function openFile(file: ApprovedProjectFile) {
  fileTriggerElement =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
  selectedFileId.value = file.id;
  await router.push({
    name: "file-detail",
    params: {
      projectId: String(route.params.projectId),
      fileId: file.id,
    },
  });
}

async function closeFile() {
  selectedFileId.value = null;
  if (route.name === "file-detail") {
    await router.replace({
      name: "project-files",
      params: { projectId: String(route.params.projectId) },
    });
  }
  await nextTick();
  fileTriggerElement?.focus();
  fileTriggerElement = null;
}

function previewVersion(version: ApprovedFileVersion): PreviewFileVersion {
  return {
    id: version.id,
    originalName: version.originalName,
    mimeType: version.mimeType,
    sizeBytes: version.sizeBytes,
    versionNumber: version.versionNumber,
    uploadedBy: version.uploadedBy,
    createdAt: version.createdAt,
  };
}

function openPreview(version: ApprovedFileVersion) {
  previewTarget.value = version;
}

async function downloadVersion(version: ApprovedFileVersion) {
  try {
    const result = await openDownload(
      await createDownloadUrl(String(route.params.projectId), version.id),
      version.originalName,
      version.mimeType,
    );
    if (result?.native) showToast("已加入系统下载");
  } catch {
    showToast("无法生成下载链接");
  }
}

function startNewVersionUpload() {
  if (!selectedFile.value) return;
  uploadTaskId.value = selectedFile.value.taskId;
  uploadMode.value = "new_version";
  uploadTargetFileId.value = selectedFile.value.id;
  failedUpload.value = null;
  uploadInput.value?.click();
}

async function toggleFinal(version: ApprovedFileVersion, isFinal: boolean) {
  const result = await workspace.setTaskFileVersionFinal(version.id, isFinal);
  if (!result.ok) {
    showToast(workspace.actionError || "最终成果状态更新失败");
    return;
  }
  showToast(isFinal ? "已标记为最终成果" : "已取消最终成果");
  await workspace.loadFiles();
}

function startNewFileUpload() {
  if (!uploadTaskId.value) {
    showToast("请先选择文件所属任务");
    return;
  }
  uploadMode.value = "new_file";
  uploadTargetFileId.value = undefined;
  failedUpload.value = null;
  uploadInput.value?.click();
}

async function performUpload(
  file: File,
  taskId: string,
  mode: "new_file" | "new_version",
  targetFileId?: string,
) {
  const task = workspace.findTask(taskId);
  if (!task) return;

  const result = await workspace.uploadFile(task, file, mode, targetFileId);
  if (result.ok) {
    failedUpload.value = null;
    if (uploadInput.value) uploadInput.value.value = "";
    showToast("文件已通过服务端校验并创建正式版本");
    await workspace.loadFiles();
    return;
  }

  failedUpload.value = { file, taskId, mode, targetFileId };
  showToast(workspace.actionError || "文件上传失败，已保留文件，可直接重试");
}

async function upload(event: Event) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  await performUpload(
    file,
    uploadTaskId.value,
    uploadMode.value,
    uploadTargetFileId.value,
  );
}

async function retryFailedUpload() {
  const failed = failedUpload.value;
  if (!failed) return;
  await performUpload(
    failed.file,
    failed.taskId,
    failed.mode,
    failed.targetFileId,
  );
}

async function load() {
  filesLoaded.value = false;
  await workspace.loadFiles();
  filesLoaded.value = true;
}

watch(
  () => route.params.fileId,
  (fileId) => {
    selectedFileId.value = typeof fileId === "string" ? fileId : null;
  },
);

onActivated(() => void load());
void load();
</script>

<template>
  <div class="xiaozhuwork-page">
    <header class="page-heading file-page-heading">
      <div class="page-title-line">
        <h1>文件</h1>
        <ContextHelpLink example-id="file-rollback" />
      </div>
      <div class="storage-summary" aria-label="项目存储配额">
        <template
          v-if="workspace.storageUsage?.projectId === workspace.projectId"
        >
          <span>
            {{ formatStorageBytes(workspace.storageUsage.usedBytes) }}
            / {{ formatStorageBytes(workspace.storageUsage.limitBytes) }}
          </span>
          <span v-if="workspace.storageUsage.reservedBytes > 0">
            · 上传预留
            {{ formatStorageBytes(workspace.storageUsage.reservedBytes) }}
          </span>
          <strong v-if="workspace.storageUsage.overLimit">· 已超出额度</strong>
        </template>
        <span v-else>存储用量暂不可用</span>
      </div>
    </header>

    <section v-if="workspace.capabilities.canUploadFile" class="upload-strip">
      <div>
        <strong>上传文件</strong>
        <small>文件必须关联任务，并通过服务端校验后进入正式文件列表。</small>
      </div>
      <select v-model="uploadTaskId" aria-label="选择文件所属任务">
        <option value="" disabled>选择任务</option>
        <option v-for="task in workspace.tasks" :key="task.id" :value="task.id">
          {{ task.title }}
        </option>
      </select>
      <van-button
        type="primary"
        :loading="workspace.pendingAction === 'file-upload'"
        @click="startNewFileUpload"
      >
        上传新文件
      </van-button>
      <input ref="uploadInput" class="sr-only" type="file" @change="upload" />
      <div v-if="failedUpload" class="upload-retry" role="status">
        <span>{{ failedUpload.file.name }} 上传失败，文件仍保留。</span>
        <van-button
          size="small"
          plain
          :loading="workspace.pendingAction === 'file-upload'"
          @click="retryFailedUpload"
        >
          重试上传
        </van-button>
      </div>
    </section>

    <div
      class="file-toolbar"
      :class="{ 'filters-open': showMobileFilters }"
      aria-label="文件筛选"
    >
      <van-search v-model="search" class="grow" placeholder="搜索文件" />
      <button
        type="button"
        class="file-filter-toggle"
        :aria-expanded="showMobileFilters"
        aria-controls="file-extra-filters"
        @click="showMobileFilters = !showMobileFilters"
      >
        筛选{{
          typeFilter !== "all" || rangeFilter !== "all" ? " · 已启用" : ""
        }}
        <span aria-hidden="true">{{ showMobileFilters ? "−" : "+" }}</span>
      </button>
      <div id="file-extra-filters" class="file-extra-filters">
        <select v-model="typeFilter" aria-label="文件类型">
          <option value="all">类型：全部</option>
          <option value="pdf">PDF</option>
          <option value="docx">DOCX</option>
          <option value="xlsx">XLSX</option>
          <option value="pptx">PPTX</option>
          <option value="image">图片</option>
          <option value="text">文本</option>
          <option value="other">其他</option>
        </select>
        <select v-model="rangeFilter" aria-label="文件范围">
          <option value="all">范围：全部文件</option>
          <option value="final">最终成果</option>
        </select>
      </div>
    </div>

    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="
        !workspace.project || !workspace.membership || invalidFileDeepLink
      "
      :empty="!rows.length"
      empty-title="没有符合筛选条件的文件"
      @retry="
        async () => {
          await reload();
          await load();
        }
      "
    >
      <ProjectFileList :files="rows" @open="openFile" />
    </PageState>

    <FileDetailDrawer
      :show="!!selectedFile"
      :file="selectedFile"
      :can-upload="workspace.capabilities.canUploadFile"
      :can-mark-final="canMarkSelectedFileFinal"
      :busy="
        workspace.pendingAction === 'file-upload' ||
        workspace.pendingAction === 'final-file'
      "
      @close="closeFile"
      @preview="openPreview"
      @download="downloadVersion"
      @upload-new-version="startNewVersionUpload"
      @toggle-final="toggleFinal"
    />

    <FilePreviewPanel
      v-if="previewTarget"
      :project-id="String(route.params.projectId)"
      :file-version="previewVersion(previewTarget)"
      :uploader-name="workspace.memberName(previewTarget.uploadedBy)"
      @close="previewTarget = null"
    />
  </div>
</template>

<style scoped>
.file-page-heading {
  align-items: center;
  padding-bottom: var(--space-md);
  border-bottom: 1px solid var(--tu-border);
}
.storage-summary {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  color: var(--tu-muted);
  font-size: var(--text-sm);
  font-variant-numeric: tabular-nums;
}
.storage-summary strong {
  color: var(--tu-danger);
  font-weight: 600;
}
.upload-strip {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(220px, 340px) auto;
  gap: var(--space-sm);
  align-items: center;
  min-width: 0;
  padding: var(--space-md) 0;
  border-bottom: 1px solid var(--tu-border);
}
.upload-strip > div:first-child {
  display: grid;
  gap: var(--space-2xs);
  min-width: 0;
}
.upload-strip strong {
  font-size: var(--text-md);
}
.upload-strip small {
  color: var(--tu-muted);
  overflow-wrap: anywhere;
}
.upload-retry {
  grid-column: 1 / -1;
  display: flex;
  justify-content: space-between;
  gap: var(--space-sm);
  align-items: center;
  min-width: 0;
  color: var(--tu-danger);
}
.upload-retry span {
  min-width: 0;
  overflow-wrap: anywhere;
}
.file-toolbar {
  min-height: 64px;
  display: grid;
  grid-template-columns: minmax(280px, 1fr) auto;
  gap: var(--space-sm);
  align-items: center;
  min-width: 0;
  padding: var(--space-sm) 0;
}
.file-toolbar :deep(.van-search) {
  padding: 0;
  background: transparent;
}
.file-toolbar :deep(.van-search__content) {
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  background: var(--tu-surface);
}
.file-extra-filters {
  display: grid;
  grid-template-columns: 150px 170px;
  gap: var(--space-sm);
}
.file-filter-toggle {
  display: none;
}
.file-toolbar select,
.upload-strip select {
  width: 100%;
  min-width: 0;
  max-width: 100%;
  min-height: 40px;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  background: var(--tu-surface);
  color: var(--tu-ink);
  padding-inline: var(--space-sm);
}
.grow {
  min-width: 0;
}
@media (max-width: 52rem) {
  .file-page-heading {
    align-items: flex-start;
  }
  .storage-summary {
    justify-content: flex-start;
  }
  .upload-strip {
    grid-template-columns: minmax(0, 1fr);
  }
  .file-toolbar {
    grid-template-columns: minmax(0, 1fr) auto;
  }
  .file-filter-toggle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-xs);
    min-height: 42px;
    border: 1px solid var(--tu-border);
    border-radius: var(--radius-control);
    background: var(--tu-surface);
    color: var(--tu-ink);
    padding: 0 var(--space-sm);
    cursor: pointer;
  }
  .file-extra-filters {
    display: none;
    grid-column: 1 / -1;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  }
  .file-toolbar.filters-open .file-extra-filters {
    display: grid;
  }
  .upload-retry {
    flex-direction: column;
    align-items: stretch;
  }
}
@media (max-width: 480px) {
  .file-extra-filters {
    grid-template-columns: minmax(0, 1fr);
  }
  .upload-strip > div:first-child small {
    display: none;
  }
}
</style>
