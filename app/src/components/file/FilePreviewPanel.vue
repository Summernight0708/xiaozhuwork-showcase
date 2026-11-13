<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { showToast } from "vant";

import {
  createDownloadUrl,
  createPreviewAccess,
  getFilePreviewKind,
  loadDocxPreview,
  loadPdfPreview,
  loadTextPreview,
  loadWorkbookPreview,
  openDownload,
  parseCsvPreview,
  type FilePreviewKind,
  type PreviewFileVersion,
  type TablePreview,
  type WorkbookPreview,
} from "@/services/file-preview";
import { registerNativeBackHandler } from "@/platform/native-back";
import {
  createPdfCanvasSession,
  type PdfCanvasSession,
} from "@/services/pdf-canvas-preview";

const props = defineProps<{
  projectId: string;
  fileVersion: PreviewFileVersion;
  uploaderName?: string;
}>();

const emit = defineEmits<{
  close: [];
  "preview-success": [fileVersionId: string];
}>();

type PreviewState = "loading" | "success" | "unsupported" | "error";

const state = ref<PreviewState>("loading");
const kind = ref<FilePreviewKind>("unsupported");
const signedUrl = ref("");
const pdfCanvas = ref<HTMLCanvasElement | null>(null);
const pdfPages = ref(0);
const pdfCurrentPage = ref(1);
const pdfBusy = ref(false);
let pdfSession: PdfCanvasSession | null = null;
const trustedVersion = ref<PreviewFileVersion | null>(null);
const textContent = ref("");
const partialText = ref(false);
const docxHtml = ref("");
const docxContainer = ref<HTMLElement | null>(null);
const dialogRef = ref<HTMLElement | null>(null);
const closeButton = ref<HTMLButtonElement | null>(null);
const table = ref<TablePreview | null>(null);
const workbook = ref<WorkbookPreview | null>(null);
const activeSheetIndex = ref(0);
const downloadBusy = ref(false);
const downloadError = ref("");
let requestGeneration = 0;
let successEmittedFor = "";
let previouslyFocused: HTMLElement | null = null;
let previousBodyOverflow = "";
let unregisterNativeBack: (() => void) | null = null;

const activeSheet = computed(
  () => workbook.value?.sheets[activeSheetIndex.value] ?? null,
);
const displayVersion = computed(
  () => trustedVersion.value ?? props.fileVersion,
);
const dialogTitleId = computed(
  () => `file-preview-title-${props.fileVersion.id}`,
);
const tableWasLimited = computed(() => {
  const current = table.value ?? activeSheet.value;
  return (
    !!current?.partialSource ||
    !!current?.truncatedRows ||
    !!current?.truncatedColumns
  );
});

function resetContent() {
  pdfSession?.close();
  pdfSession = null;
  pdfPages.value = 0;
  pdfCurrentPage.value = 1;
  pdfBusy.value = false;
  signedUrl.value = "";
  trustedVersion.value = null;
  textContent.value = "";
  partialText.value = false;
  docxHtml.value = "";
  table.value = null;
  workbook.value = null;
  activeSheetIndex.value = 0;
  downloadError.value = "";
}

async function ensureSanitizedDocxRendered() {
  await nextTick();
  const container = docxContainer.value;
  if (!container?.firstChild)
    throw new Error("DOCX preview container unavailable");
}

function markSuccess() {
  if (state.value === "error" || state.value === "unsupported") return;
  state.value = "success";
  const id = displayVersion.value.id;
  if (successEmittedFor === id) return;
  successEmittedFor = id;
  emit("preview-success", id);
}

function markNativeError() {
  state.value = "error";
}

async function renderPdfPage(page: number, generation = requestGeneration) {
  const session = pdfSession;
  if (!session || pdfBusy.value || page < 1 || page > session.pageCount) return;
  pdfBusy.value = true;
  try {
    await nextTick();
    const canvas = pdfCanvas.value;
    if (!canvas) throw new Error("PDF canvas is unavailable");
    await session.renderPage(page, canvas);
    if (generation !== requestGeneration || session !== pdfSession) return;
    pdfCurrentPage.value = page;
    markSuccess();
  } catch {
    if (generation === requestGeneration && session === pdfSession)
      state.value = "error";
  } finally {
    if (generation === requestGeneration && session === pdfSession)
      pdfBusy.value = false;
  }
}

async function preparePreview() {
  const generation = ++requestGeneration;
  state.value = "loading";
  kind.value = "unsupported";
  successEmittedFor = "";
  resetContent();

  try {
    const access = await createPreviewAccess(
      props.projectId,
      props.fileVersion.id,
    );
    if (generation !== requestGeneration) return;

    trustedVersion.value = access.version;
    signedUrl.value = access.signedUrl;
    kind.value = getFilePreviewKind(access.version);

    if (kind.value === "unsupported") {
      state.value = "unsupported";
      return;
    }
    if (["image", "video"].includes(kind.value)) {
      return;
    }
    if (kind.value === "pdf") {
      const pdf = await loadPdfPreview(
        access.signedUrl,
        access.version.sizeBytes,
      );
      if (generation !== requestGeneration) return;
      const session = await createPdfCanvasSession(pdf);
      if (generation !== requestGeneration) {
        session.close();
        return;
      }
      pdfSession = session;
      pdfPages.value = session.pageCount;
      await renderPdfPage(1, generation);
      return;
    }
    if (kind.value === "docx") {
      docxHtml.value = await loadDocxPreview(
        access.signedUrl,
        access.version.sizeBytes,
      );
      if (generation !== requestGeneration) return;
      await ensureSanitizedDocxRendered();
      markSuccess();
      return;
    }
    if (kind.value === "xlsx") {
      workbook.value = await loadWorkbookPreview(
        access.signedUrl,
        access.version.sizeBytes,
      );
      if (generation !== requestGeneration) return;
      markSuccess();
      return;
    }

    const loaded = await loadTextPreview(
      access.signedUrl,
      access.version.sizeBytes,
    );
    if (generation !== requestGeneration) return;
    if (kind.value === "csv") {
      table.value = parseCsvPreview(loaded.text, loaded.partial);
      if (!table.value.rows.length)
        throw new Error("CSV has no previewable rows");
    } else {
      textContent.value = loaded.text;
      partialText.value = loaded.partial;
    }
    markSuccess();
  } catch {
    if (generation === requestGeneration) state.value = "error";
  }
}

async function downloadOriginal() {
  downloadBusy.value = true;
  downloadError.value = "";
  try {
    const result = await openDownload(
      await createDownloadUrl(props.projectId, props.fileVersion.id),
      displayVersion.value.originalName,
      displayVersion.value.mimeType,
    );
    if (result?.native) showToast("已加入系统下载");
  } catch {
    downloadError.value = "当前无法生成下载链接，请稍后重试。";
  } finally {
    downloadBusy.value = false;
  }
}

function sizeLabel(bytes: number) {
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`;
  return `${Math.max(0.1, bytes / 1024).toFixed(1)} KB`;
}

const focusableSelector = [
  "button:not([disabled])",
  "[href]",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "iframe",
  "video[controls]",
  '[tabindex]:not([tabindex="-1"])',
].join(",");

function focusableElements() {
  const dialog = dialogRef.value;
  if (!dialog) return [];
  return Array.from(
    dialog.querySelectorAll<HTMLElement>(focusableSelector),
  ).filter((element) => element.getAttribute("aria-hidden") !== "true");
}

function handleDocumentKeydown(event: KeyboardEvent) {
  if (event.key === "Escape") {
    event.preventDefault();
    event.stopPropagation();
    emit("close");
    return;
  }
  if (event.key !== "Tab") return;

  const dialog = dialogRef.value;
  if (!dialog) return;
  const focusable = focusableElements();
  if (!focusable.length) {
    event.preventDefault();
    dialog.focus();
    return;
  }

  const first = focusable[0]!;
  const last = focusable[focusable.length - 1]!;
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  } else if (
    !(document.activeElement instanceof Node) ||
    !dialog.contains(document.activeElement)
  ) {
    event.preventDefault();
    (event.shiftKey ? last : first).focus();
  }
}

onMounted(async () => {
  previouslyFocused =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
  previousBodyOverflow = document.body.style.overflow;
  document.body.style.overflow = "hidden";
  document.addEventListener("keydown", handleDocumentKeydown);
  unregisterNativeBack = registerNativeBackHandler(() => {
    emit("close");
    return true;
  }, 100);
  await nextTick();
  closeButton.value?.focus();
});

watch(
  () => [props.projectId, props.fileVersion.id] as const,
  () => void preparePreview(),
  { immediate: true },
);

onUnmounted(() => {
  requestGeneration += 1;
  resetContent();
  document.removeEventListener("keydown", handleDocumentKeydown);
  unregisterNativeBack?.();
  unregisterNativeBack = null;
  document.body.style.overflow = previousBodyOverflow;
  if (previouslyFocused?.isConnected) previouslyFocused.focus();
});
</script>

<template>
  <Teleport to="body">
    <div class="preview-overlay">
      <section
        ref="dialogRef"
        class="file-preview-panel"
        role="dialog"
        aria-modal="true"
        :aria-labelledby="dialogTitleId"
        tabindex="-1"
      >
        <header class="preview-heading">
          <div>
            <strong :id="dialogTitleId">{{
              displayVersion.originalName
            }}</strong>
            <p>
              v{{ displayVersion.versionNumber }} ·
              {{ sizeLabel(displayVersion.sizeBytes) }} ·
              {{ displayVersion.mimeType }}
            </p>
            <small>
              上传者 {{ uploaderName || "未知成员" }} ·
              {{ new Date(displayVersion.createdAt).toLocaleString() }}
            </small>
          </div>
          <button
            ref="closeButton"
            type="button"
            class="preview-close"
            aria-label="关闭文件预览"
            @click="emit('close')"
          >
            关闭
          </button>
        </header>

        <div class="preview-stage" :aria-busy="state === 'loading'">
          <p v-if="state === 'loading'" class="preview-message">
            正在准备预览…
          </p>

          <img
            v-if="kind === 'image' && signedUrl"
            v-show="state !== 'error'"
            class="image-preview"
            :src="signedUrl"
            :alt="displayVersion.originalName"
            @load="markSuccess"
            @error="markNativeError"
          />

          <div v-if="kind === 'pdf' && pdfPages > 0" class="pdf-viewer">
            <nav class="pdf-controls" aria-label="PDF 翻页">
              <button
                type="button"
                :disabled="pdfBusy || pdfCurrentPage <= 1"
                @click="renderPdfPage(pdfCurrentPage - 1)"
              >
                上一页
              </button>
              <span>第 {{ pdfCurrentPage }} / {{ pdfPages }} 页</span>
              <button
                type="button"
                :disabled="pdfBusy || pdfCurrentPage >= pdfPages"
                @click="renderPdfPage(pdfCurrentPage + 1)"
              >
                下一页
              </button>
            </nav>
            <p v-if="pdfBusy && state === 'success'" class="preview-note">
              正在渲染页面…
            </p>
            <canvas
              v-show="state !== 'error'"
              ref="pdfCanvas"
              class="pdf-preview"
              role="img"
              :aria-label="displayVersion.originalName + ' PDF 页面'"
            />
          </div>

          <video
            v-if="kind === 'video' && signedUrl"
            v-show="state !== 'error'"
            class="video-preview"
            :src="signedUrl"
            controls
            preload="metadata"
            @loadedmetadata="markSuccess"
            @error="markNativeError"
          >
            当前浏览器无法播放此视频，请下载原文件。
          </video>

          <div
            v-if="kind === 'docx' && docxHtml"
            ref="docxContainer"
            class="docx-preview"
            :innerHTML="docxHtml"
          />

          <div v-if="kind === 'xlsx' && workbook" class="sheet-preview">
            <div class="sheet-tabs" aria-label="工作表">
              <button
                v-for="(sheet, index) in workbook.sheets"
                :key="sheet.name"
                type="button"
                :aria-pressed="activeSheetIndex === index"
                @click="activeSheetIndex = index"
              >
                {{ sheet.name }}
              </button>
            </div>
            <div v-if="activeSheet?.rows.length" class="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th
                      v-for="(cell, index) in activeSheet.rows[0]"
                      :key="`h-${index}`"
                      scope="col"
                    >
                      {{ cell || "—" }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(row, rowIndex) in activeSheet.rows.slice(1)"
                    :key="rowIndex"
                  >
                    <td v-for="(cell, cellIndex) in row" :key="cellIndex">
                      {{ cell }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p v-else class="preview-message">当前工作表没有可显示的数据。</p>
          </div>

          <div v-if="kind === 'csv' && table?.rows.length" class="table-scroll">
            <table>
              <thead>
                <tr>
                  <th
                    v-for="(cell, index) in table.rows[0]"
                    :key="`h-${index}`"
                    scope="col"
                  >
                    {{ cell || "—" }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(row, rowIndex) in table.rows.slice(1)"
                  :key="rowIndex"
                >
                  <td v-for="(cell, cellIndex) in row" :key="cellIndex">
                    {{ cell }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <pre
            v-if="kind === 'text' && state === 'success'"
            class="text-preview"
            >{{ textContent }}</pre>

          <p
            v-if="(partialText || tableWasLimited) && state === 'success'"
            class="preview-note"
          >
            当前仅显示文件部分内容，完整内容请下载。
          </p>

          <div v-if="state === 'unsupported'" class="preview-message">
            <strong>当前文件类型暂不支持在线预览。</strong>
            <span>你仍然可以下载原文件查看完整内容。</span>
          </div>

          <div v-if="state === 'error'" class="preview-message" role="alert">
            <strong>当前无法预览此文件。</strong>
            <span>预览失败不会影响原文件下载。</span>
          </div>
        </div>

        <footer class="preview-footer">
          <button
            type="button"
            class="download-button"
            :disabled="downloadBusy"
            @click="downloadOriginal"
          >
            {{ downloadBusy ? "正在准备下载…" : "下载原文件" }}
          </button>
          <span v-if="downloadError" role="alert">{{ downloadError }}</span>
        </footer>
      </section>
    </div>
  </Teleport>
</template>

<style scoped>
.preview-overlay {
  position: fixed;
  inset: 0;
  z-index: 4000;
  display: grid;
  place-items: center;
  padding: 24px;
  background: rgb(15 23 42 / 0.54);
  overscroll-behavior: contain;
}

.file-preview-panel {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  gap: 14px;
  width: min(1080px, 100%);
  height: min(820px, calc(100dvh - 48px));
  max-width: 100%;
  max-height: calc(100dvh - 48px);
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  padding: 16px;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
  background: white;
  box-shadow: 0 24px 72px rgb(15 23 42 / 0.24);
}
.preview-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  min-width: 0;
}
.preview-heading div {
  min-width: 0;
}
.preview-close {
  flex: 0 0 auto;
}
.preview-heading strong,
.preview-heading p,
.preview-heading small {
  display: block;
  overflow-wrap: anywhere;
}
.preview-heading p {
  margin: 5px 0;
  color: var(--tu-muted);
}
.preview-heading small {
  color: var(--tu-muted);
}
.preview-close,
.download-button,
.sheet-tabs button,
.pdf-controls button {
  min-height: 36px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: white;
  padding: 0 12px;
  cursor: pointer;
}
.preview-stage {
  min-width: 0;
  min-height: 0;
  overflow: auto;
  overscroll-behavior: contain;
  border-radius: 10px;
  background: var(--tu-subtle-surface);
}
.preview-message {
  display: grid;
  gap: 6px;
  margin: 0;
  padding: 28px 20px;
  color: var(--tu-muted);
  text-align: center;
}
.image-preview,
.video-preview,
.pdf-preview {
  display: block;
  width: 100%;
  max-width: 100%;
  border: 0;
}
.image-preview {
  max-height: 70vh;
  object-fit: contain;
}
.video-preview {
  max-height: 70vh;
  background: black;
}
.pdf-viewer {
  display: grid;
  justify-items: center;
  gap: 12px;
  padding: 12px;
}
.pdf-controls {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  width: 100%;
  flex-wrap: wrap;
}
.pdf-controls button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.pdf-preview {
  height: auto;
  max-width: 100%;
  background: white;
  box-shadow: 0 2px 12px rgb(15 23 42 / 0.08);
}
.docx-preview {
  max-width: 100%;
  padding: 24px;
  overflow-wrap: anywhere;
  background: white;
}
.docx-preview :deep(img) {
  max-width: 100%;
  height: auto;
}
.docx-preview :deep(table) {
  width: 100%;
  border-collapse: collapse;
}
.docx-preview :deep(th),
.docx-preview :deep(td) {
  border: 1px solid var(--tu-border);
  padding: 6px 8px;
  vertical-align: top;
}
.sheet-preview {
  display: grid;
  gap: 10px;
  padding: 12px;
}
.sheet-tabs {
  display: flex;
  gap: 8px;
  max-width: 100%;
  overflow-x: auto;
  padding-bottom: 2px;
}
.sheet-tabs button[aria-pressed="true"] {
  font-weight: 700;
  border-color: currentColor;
}
.table-scroll {
  max-width: 100%;
  overflow: auto;
  background: white;
}
.table-scroll table {
  width: max-content;
  min-width: 100%;
  border-collapse: collapse;
}
.table-scroll th,
.table-scroll td {
  max-width: 320px;
  padding: 7px 9px;
  border: 1px solid var(--tu-border);
  overflow-wrap: anywhere;
  text-align: left;
  vertical-align: top;
}
.table-scroll th {
  position: sticky;
  top: 0;
  background: var(--tu-subtle-surface);
}
.text-preview {
  max-height: 65vh;
  margin: 0;
  padding: 18px;
  overflow: auto;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  font: inherit;
}
.preview-note {
  margin: 0;
  padding: 10px 14px;
  border-top: 1px solid var(--tu-border);
  color: var(--tu-muted);
  font-size: 13px;
}
.preview-footer {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.preview-footer span {
  color: var(--tu-danger);
  font-size: 13px;
}
.download-button {
  font-weight: 600;
}
.download-button:disabled {
  cursor: wait;
  opacity: 0.65;
}
.preview-close:focus-visible,
.download-button:focus-visible,
.sheet-tabs button:focus-visible {
  outline: 3px solid color-mix(in srgb, currentColor 32%, transparent);
  outline-offset: 2px;
}
@media (max-width: 767px) {
  .preview-overlay {
    place-items: stretch;
    padding: 0;
  }
  .file-preview-panel {
    width: 100%;
    height: 100dvh;
    max-height: 100dvh;
    padding: max(12px, env(safe-area-inset-top))
      max(12px, env(safe-area-inset-right))
      max(12px, env(safe-area-inset-bottom))
      max(12px, env(safe-area-inset-left));
    border: 0;
    border-radius: 0;
  }
  .preview-heading {
    gap: 10px;
  }
  .preview-close {
    min-height: 40px;
  }
  .docx-preview {
    padding: 16px 12px;
  }
  .pdf-preview {
    min-height: 100%;
  }
}
</style>
