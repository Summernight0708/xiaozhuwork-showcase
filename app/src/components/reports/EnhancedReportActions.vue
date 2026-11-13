<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";
import { showToast } from "vant";

import { downloadBlob } from "@/platform/downloads";
import {
  downloadEnhancedReport,
  enhancedReportErrorMessage,
  isEnhancedReportAbort,
  type EnhancedReportAvailability,
  type EnhancedReportFormat,
} from "@/services/enhanced-report";

const props = withDefaults(
  defineProps<{
    reportId: string;
    reportState: "draft" | "formal";
    canRead: boolean;
    availability?: EnhancedReportAvailability;
    exportAction?: (
      reportId: string,
      format: EnhancedReportFormat,
      signal: AbortSignal,
    ) => Promise<Blob>;
  }>(),
  { availability: "planned", exportAction: undefined },
);

const busy = ref<EnhancedReportFormat | null>(null);
const errorText = ref("");
let controller: AbortController | null = null;

function cancel(): void {
  const current = controller;
  if (!current) return;
  current.abort();
  controller = null;
  // Some transports ignore AbortSignal. Never leave the UI indefinitely busy.
  busy.value = null;
}

onBeforeUnmount(() => {
  cancel();
});

async function exportFile(format: EnhancedReportFormat): Promise<void> {
  if (
    busy.value !== null ||
    !props.canRead ||
    props.reportState !== "formal" ||
    props.availability !== "available"
  )
    return;
  const current = new AbortController();
  controller = current;
  busy.value = format;
  errorText.value = "";
  try {
    const blob = await (props.exportAction ?? downloadEnhancedReport)(
      props.reportId,
      format,
      current.signal,
    );
    if (current.signal.aborted) return;
    const result = await downloadBlob({
      blob,
      fileName: `xiaozhu-enhanced-report-${props.reportId}.${format}`,
      mimeType: format === "pdf" ? "application/pdf" : "text/csv;charset=utf-8",
    });
    if (result.native) showToast("报告已保存到系统下载");
  } catch (err) {
    if (!current.signal.aborted && !isEnhancedReportAbort(err))
      errorText.value = enhancedReportErrorMessage(err);
  } finally {
    // An old cancelled request must not clear a newer download's loading state.
    if (controller === current) {
      controller = null;
      busy.value = null;
    }
  }
}
</script>

<template>
  <section
    v-if="canRead"
    class="enhanced-report-actions"
    aria-label="Pro 增强报告"
  >
    <h3>增强贡献报告</h3>
    <p v-if="reportState !== 'formal'" class="enhanced-report-hint">
      报告正式化后才可使用增强导出。
    </p>
    <p v-else-if="availability === 'planned'" class="enhanced-report-hint">
      Pro 增强报告正在准备中，尚未开放。
    </p>
    <p v-else-if="availability === 'requires_pro'" class="enhanced-report-hint">
      当前项目尚无有效 Pro 权益，基础导出仍可使用。
    </p>
    <div v-else class="enhanced-report-buttons">
      <button
        type="button"
        :disabled="busy !== null"
        :aria-busy="busy === 'pdf'"
        @click="exportFile('pdf')"
      >
        {{ busy === "pdf" ? "正在生成 PDF…" : "增强 PDF" }}
      </button>
      <button
        type="button"
        :disabled="busy !== null"
        :aria-busy="busy === 'csv'"
        @click="exportFile('csv')"
      >
        {{ busy === "csv" ? "正在生成 CSV…" : "增强 CSV" }}
      </button>
      <button v-if="busy !== null" type="button" @click="cancel">
        取消下载
      </button>
    </div>
    <p v-if="errorText" role="alert">{{ errorText }}</p>
    <p class="enhanced-report-hint">仅供参考，不代表教师评分或成员能力评价。</p>
  </section>
</template>

<style scoped>
.enhanced-report-actions {
  display: grid;
  gap: 0.65rem;
}
.enhanced-report-actions h3 {
  margin: 0;
  font-size: 1rem;
}
.enhanced-report-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.65rem;
}
.enhanced-report-buttons button {
  min-height: 2.5rem;
  border-radius: 0.5rem;
  border: 1px solid var(--tu-action);
  color: var(--tu-action);
  background: transparent;
  padding: 0.4rem 0.8rem;
}
.enhanced-report-buttons button:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}
.enhanced-report-hint {
  color: var(--tu-muted);
  margin: 0;
  font-size: 0.85rem;
}
</style>
