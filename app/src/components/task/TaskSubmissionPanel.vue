<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showToast } from "vant";

import {
  submissionFileTypeFromMime,
  submissionFileTypeLabel,
  type SubmissionFileType,
} from "@/domain/submission-file-types";
import type { TaskFileVersion } from "@/types/ui";

const props = withDefaults(
  defineProps<{
    versions: TaskFileVersion[];
    requiredFileTypes: readonly SubmissionFileType[];
    dependencyBlocked: boolean;
    requiresReview?: boolean;
    submitLoading: boolean;
    uploadLoading: boolean;
    resetKey: number;
    autoSelectFileVersionId: string | null;
  }>(),
  { requiresReview: true },
);

const emit = defineEmits<{
  submit: [
    payload: {
      submissionText?: string;
      fileVersionIds: string[];
    },
  ];
  upload: [file: File];
}>();

const submissionText = ref("");
const selectedFileVersionIds = ref<string[]>([]);
const uploadInput = ref<HTMLInputElement | null>(null);

const deliverableVersions = computed(() =>
  props.versions.filter((version) => version.purpose !== "reference"),
);

const selectedVersions = computed(() => {
  const ids = new Set(selectedFileVersionIds.value);
  return deliverableVersions.value.filter((version) =>
    ids.has(version.fileVersionId),
  );
});

const hasRequiredFile = computed(() => {
  if (props.requiredFileTypes.length === 0) return true;
  return selectedVersions.value.some((version) => {
    const type = submissionFileTypeFromMime(version.mimeType);
    return type !== null && props.requiredFileTypes.includes(type);
  });
});

const hasDeliverable = computed(
  () =>
    submissionText.value.trim().length > 0 ||
    selectedFileVersionIds.value.length > 0,
);

const canSubmit = computed(
  () => hasDeliverable.value && hasRequiredFile.value && !props.submitLoading,
);

function chooseUpload() {
  uploadInput.value?.click();
}

function upload(event: Event) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  emit("upload", file);
  input.value = "";
}

function submit() {
  const text = submissionText.value.trim();
  if (!text && selectedFileVersionIds.value.length === 0) {
    showToast("请填写完成说明或至少选择一个附件");
    return;
  }
  if (!hasRequiredFile.value && props.requiredFileTypes.length > 0) {
    showToast(
      `此任务要求提交内容中至少包含以下任一类型：${props.requiredFileTypes.map(submissionFileTypeLabel).join("、")}`,
    );
    return;
  }
  emit("submit", {
    ...(text ? { submissionText: text } : {}),
    fileVersionIds: [...selectedFileVersionIds.value],
  });
}

watch(
  () => props.autoSelectFileVersionId,
  (fileVersionId) => {
    if (
      !fileVersionId ||
      selectedFileVersionIds.value.includes(fileVersionId) ||
      !deliverableVersions.value.some(
        (version) => version.fileVersionId === fileVersionId,
      )
    ) {
      return;
    }
    selectedFileVersionIds.value = [
      ...selectedFileVersionIds.value,
      fileVersionId,
    ];
  },
);

watch(
  () =>
    deliverableVersions.value.map((version) => version.fileVersionId).join(","),
  () => {
    const allowed = new Set(
      deliverableVersions.value.map((version) => version.fileVersionId),
    );
    selectedFileVersionIds.value = selectedFileVersionIds.value.filter((id) =>
      allowed.has(id),
    );
  },
);

watch(
  () => props.resetKey,
  () => {
    submissionText.value = "";
    selectedFileVersionIds.value = [];
  },
);
</script>

<template>
  <section class="submission-panel">
    <div class="section-heading">
      <div>
        <h2 class="section-title">提交成果</h2>
        <p class="muted">完成说明与附件可任选其一，也可以同时提交。</p>
      </div>
      <van-button
        size="small"
        plain
        type="primary"
        :loading="uploadLoading"
        @click="chooseUpload"
      >
        上传附件
      </van-button>
      <input
        ref="uploadInput"
        class="sr-only"
        type="file"
        aria-label="上传提交附件"
        @change="upload"
      />
    </div>

    <label class="submission-field">
      <span>完成说明</span>
      <textarea
        v-model="submissionText"
        rows="4"
        maxlength="4000"
        placeholder="可填写本次完成内容……"
      />
    </label>

    <p v-if="requiredFileTypes.length" class="requirement-note">
      本任务要求成果中至少包含以下任一类型：
      <strong>{{
        requiredFileTypes.map(submissionFileTypeLabel).join("、")
      }}</strong
      >。
    </p>

    <fieldset class="submission-files">
      <legend>附件</legend>
      <label
        v-for="version in [...deliverableVersions].reverse()"
        :key="version.fileVersionId"
        class="submission-file-option"
      >
        <input
          v-model="selectedFileVersionIds"
          type="checkbox"
          :value="version.fileVersionId"
        />
        <span> {{ version.originalName }} · v{{ version.versionNumber }} </span>
      </label>
      <p v-if="deliverableVersions.length === 0" class="muted">
        暂无已最终化附件。你仍可以仅提交完成说明。
      </p>
    </fieldset>

    <p v-if="dependencyBlocked" class="capability-note">
      上游任务尚未完成，你仍可以先提交成果。
    </p>
    <p
      v-else-if="
        requiredFileTypes.length &&
        selectedFileVersionIds.length &&
        !hasRequiredFile
      "
      class="capability-note"
    >
      当前所选附件不包含任何指定类型（{{
        requiredFileTypes.map(submissionFileTypeLabel).join("、")
      }}）。
    </p>

    <van-button
      type="primary"
      :loading="submitLoading"
      :disabled="!canSubmit"
      @click="submit"
    >
      {{ requiresReview === false ? "提交并完成" : "提交验收" }}
    </van-button>
  </section>
</template>

<style scoped>
.submission-panel {
  display: grid;
  gap: 16px;
}

.section-heading {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  justify-content: space-between;
}

.section-title {
  margin: 0;
}

.muted,
.capability-note,
.requirement-note {
  margin: 4px 0 0;
}

.submission-field {
  display: grid;
  gap: 8px;
}

.submission-field textarea {
  width: 100%;
  min-height: 112px;
  box-sizing: border-box;
  resize: vertical;
  border: 1px solid var(--van-border-color);
  border-radius: 10px;
  padding: 12px;
  font: inherit;
}

.requirement-note {
  padding: 10px 12px;
  border-radius: 10px;
  background: var(--van-warning-color-light);
}

.submission-files {
  display: grid;
  gap: 8px;
  min-width: 0;
  margin: 0;
  padding: 12px;
  border: 1px solid var(--van-border-color);
  border-radius: 10px;
}

.submission-file-option {
  display: flex;
  gap: 8px;
  align-items: center;
}
</style>
