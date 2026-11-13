<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showConfirmDialog, showToast } from "vant";
import { invokeDisposition } from "@/features/task-disposition/repository";
import { getBackend } from "@/services/backend";
import type { TaskFile } from "@/types/ui";

const props = defineProps<{
  projectId: string;
  taskId: string;
  files: readonly TaskFile[];
  userId: string | null;
  isLeader: boolean;
  canManage: boolean;
}>();
const emit = defineEmits<{ changed: [] }>();
const state = ref<Record<string, "pending_quarantine" | "withdrawn">>({});
const reason = ref<Record<string, string>>({});
const busy = ref<string | null>(null);
const error = ref("");
const pending = ref<{ fingerprint: string; requestId: string } | null>(null);
const items = computed(() =>
  props.files.map((file) => ({
    file,
    version:
      file.versions.find((v) => v.fileVersionId === file.currentVersionId) ??
      [...file.versions].sort((a, b) => b.versionNumber - a.versionNumber)[0] ??
      null,
  })),
);
async function refresh() {
  if (!props.projectId || !props.taskId) return;
  error.value = "";
  try {
    const backend = getBackend();
    if (!backend) throw new Error("服务器不可用");
    const { data, error: queryError } = await backend.client
      .from("file_version_withdrawals")
      .select("file_version_id,state")
      .eq("project_id", props.projectId)
      .eq("task_id", props.taskId);
    if (queryError) throw queryError;
    state.value = Object.fromEntries(
      (data ?? [])
        .filter(
          (
            row,
          ): row is {
            file_version_id: string;
            state: "pending_quarantine" | "withdrawn";
          } =>
            !!row.file_version_id &&
            (row.state === "pending_quarantine" || row.state === "withdrawn"),
        )
        .map((row) => [row.file_version_id, row.state]),
    );
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "无法获取撤回记录";
  }
}
watch(
  () => [props.projectId, props.taskId, props.files.length],
  () => void refresh(),
  { immediate: true },
);
function canWithdraw(file: TaskFile, versionId: string, uploadedBy?: string) {
  return (
    props.canManage &&
    !state.value[versionId] &&
    (props.isLeader || (!!props.userId && uploadedBy === props.userId)) &&
    file.version > 0
  );
}
async function withdraw(
  file: TaskFile,
  versionId: string,
  uploadedBy?: string,
) {
  if (!canWithdraw(file, versionId, uploadedBy) || busy.value) return;
  const text = reason.value[versionId]?.trim();
  if (!text) {
    error.value = "请填写撤回原因";
    return;
  }
  try {
    await showConfirmDialog({
      title: "撤回文件版本",
      message:
        "撤回申请立即阻断新访问授权，隔离完成前不会显示为已撤回。原签名链接的撤权需等待 Storage 隔离验证。",
    });
  } catch {
    return;
  }
  busy.value = versionId;
  error.value = "";
  try {
    const fingerprint = JSON.stringify({
      versionId,
      reason: text,
      expectedVersion: file.version,
    });
    if (pending.value?.fingerprint !== fingerprint)
      pending.value = { fingerprint, requestId: crypto.randomUUID() };
    const response = await invokeDisposition("cmd_withdraw_file_version", {
      p_project_id: props.projectId,
      p_file_version_id: versionId,
      p_reason: text,
      p_expected_version: file.version,
      p_request_id: pending.value.requestId,
    });
    pending.value = null;
    reason.value[versionId] = "";
    showToast(
      response.data?.state === "pending_quarantine"
        ? "已申请撤回，待 Storage 隔离"
        : "撤回请求已记录",
    );
    await refresh();
    emit("changed");
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "撤回失败";
  } finally {
    busy.value = null;
  }
}
</script>
<template>
  <div v-if="items.some((entry) => entry.version)" class="withdrawals">
    <strong>文件撤回（保留历史）</strong>
    <p>仅文件上传者或组长可申请，隔离确认前不会宣称永久撤回。</p>
    <p v-if="error" role="alert" class="withdrawals__error">{{ error }}</p>
    <div
      v-for="{ file, version } in items"
      :key="file.fileId"
      class="withdrawals__item"
    >
      <template v-if="version">
        <span>{{ version.originalName }} · v{{ version.versionNumber }}</span>
        <small v-if="state[version.fileVersionId] === 'pending_quarantine'">
          待隔离（已停止新访问授权）
        </small>
        <small v-else-if="state[version.fileVersionId] === 'withdrawn'"
          >已撤回</small
        >
        <template
          v-else-if="
            canWithdraw(file, version.fileVersionId, version.uploadedBy)
          "
        >
          <label :for="'file-withdraw-' + file.fileId">撤回原因</label>
          <input
            :id="'file-withdraw-' + file.fileId"
            v-model="reason[version.fileVersionId]"
            maxlength="2000"
            :disabled="busy !== null"
            placeholder="请说明撤回原因"
          />
          <button
            type="button"
            :disabled="busy !== null"
            @click="withdraw(file, version.fileVersionId, version.uploadedBy)"
          >
            {{ busy === version.fileVersionId ? "提交中…" : "申请撤回" }}
          </button>
        </template>
      </template>
    </div>
    <button type="button" class="withdrawals__refresh" @click="refresh">
      刷新隔离状态
    </button>
  </div>
</template>
<style scoped>
.withdrawals {
  display: grid;
  gap: 0.75rem;
}
.withdrawals p {
  margin: 0;
  font-size: 0.875rem;
  line-height: 1.6;
}
.withdrawals__item {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.6rem;
  border-top: 1px solid var(--tu-border);
  padding-top: 0.55rem;
}
.withdrawals__item input {
  flex: 1;
  min-width: 9rem;
  min-height: 36px;
  padding: 0.45rem;
  border: 1px solid var(--tu-border);
  border-radius: 6px;
  color: inherit;
  background: transparent;
}
.withdrawals__item button,
.withdrawals__refresh {
  min-height: 36px;
  padding: 0.45rem 0.65rem;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.withdrawals__error {
  color: var(--tu-danger);
}
</style>
