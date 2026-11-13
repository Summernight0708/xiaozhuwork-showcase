<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showConfirmDialog, showToast } from "vant";

import {
  archiveProject,
  archiveRetentionPhase,
  extendProjectRetention,
  loadArchiveCycle,
  restoreProject,
  type ArchiveCycle,
  type ArchiveCommandResult,
} from "@/features/project-archive/repository";

const props = defineProps<{
  projectId: string;
  version: number;
  archivedAt: string | null;
  canManage: boolean;
}>();
const emit = defineEmits<{ updated: [result: ArchiveCommandResult] }>();

const reason = ref("");
const extensionDays = ref(30);
const cycle = ref<ArchiveCycle | null>(null);
const loading = ref(false);
const loadingCycle = ref(false);
const cycleError = ref("");
const phase = computed(() =>
  cycle.value ? archiveRetentionPhase(cycle.value) : "expired",
);

async function refreshCycle() {
  if (!props.archivedAt) {
    cycle.value = null;
    return;
  }
  loadingCycle.value = true;
  cycleError.value = "";
  try {
    cycle.value = await loadArchiveCycle(props.projectId);
  } catch (error) {
    cycleError.value =
      error instanceof Error ? error.message : "无法读取归档期限";
  } finally {
    loadingCycle.value = false;
  }
}

watch(() => [props.projectId, props.archivedAt], refreshCycle, {
  immediate: true,
});

function messageFor(code?: string): string {
  switch (code) {
    case "STALE_VERSION":
      return "项目版本已更新，请刷新后重试";
    case "ACTIVE_FREE_PROJECT_LIMIT_REACHED":
      return "成员的 Free 活跃项目额度不足，无法恢复";
    case "RETENTION_WINDOW_EXPIRED":
      return "当前保留或恢复窗口已结束";
    case "NOT_FOUND_OR_NOT_AUTHORIZED":
      return "没有该项目的操作权限";
    case "PROJECT_NOT_ACTIVE":
    case "INVALID_TRANSITION":
      return "项目状态已变化，请刷新";
    case "IDEMPOTENCY_KEY_REUSED":
      return "操作标识与之前的请求不一致";
    default:
      return "操作未完成，请刷新状态后重试";
  }
}

async function run(action: "archive" | "restore" | "extend") {
  if (loading.value || !props.canManage) return;
  if (action === "archive" && !reason.value.trim()) {
    showToast("请填写归档原因");
    return;
  }
  const descriptions = {
    archive:
      "归档后所有成员仍可查看历史与下载已有文件，但不得继续提交、编辑或邀请；默认保留一年。确定归档吗？",
    restore: "恢复后项目将重新占用相关 Free 成员的活跃项目额度。确定恢复吗？",
    extend: `从当前保留期起延长 ${extensionDays.value} 天。确定吗？`,
  };
  try {
    await showConfirmDialog({
      title:
        action === "archive"
          ? "归档项目"
          : action === "restore"
            ? "恢复项目"
            : "延长保留期",
      message: descriptions[action],
      confirmButtonText: "确认",
    });
  } catch {
    return;
  }

  loading.value = true;
  try {
    const result =
      action === "archive"
        ? await archiveProject(
            props.projectId,
            props.version,
            reason.value.trim(),
          )
        : action === "restore"
          ? await restoreProject(props.projectId, props.version)
          : await extendProjectRetention(
              props.projectId,
              props.version,
              extensionDays.value,
            );
    if (!result.ok) {
      showToast(messageFor(result.code));
      return;
    }
    reason.value = "";
    showToast(
      action === "archive"
        ? "归档成功"
        : action === "restore"
          ? "恢复成功"
          : "保留期限已延长",
    );
    emit("updated", result);
    await refreshCycle();
  } catch (error) {
    showToast(error instanceof Error ? error.message : "网络请求失败");
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <section class="surface setting-section archive-action">
    <h2>项目归档</h2>
    <p v-if="archivedAt" role="status">
      本项目已归档，仅开放历史浏览、授权下载与导出。
    </p>
    <p v-else>归档后不再计入 Free 活跃项目额度，历史记录和贡献不会删除。</p>

    <template v-if="archivedAt">
      <p v-if="loadingCycle">正在读取保留期限…</p>
      <p v-else-if="cycleError" role="alert">{{ cycleError }}</p>
      <template v-else-if="cycle">
        <p>归档代际：{{ cycle.generation }}</p>
        <p>保留至：{{ new Date(cycle.retain_until).toLocaleDateString() }}</p>
        <p>
          仅恢复窗口结束：{{
            new Date(cycle.recovery_until).toLocaleDateString()
          }}
        </p>
        <p v-if="phase === 'recovery_only'">
          正式保留期已结束，目前只允许恢复。
        </p>
        <p v-if="phase === 'expired'">恢复窗口已结束，请联系项目管理人员。</p>
        <div v-if="canManage" class="archive-controls">
          <van-button
            size="small"
            type="primary"
            :loading="loading"
            :disabled="phase === 'expired'"
            @click="run('restore')"
            >恢复项目</van-button
          >
          <template v-if="phase === 'retained'">
            <label for="archive-retention-days">延长天数</label>
            <select id="archive-retention-days" v-model.number="extensionDays">
              <option :value="30">30 天</option>
              <option :value="90">90 天</option>
              <option :value="365">365 天</option>
            </select>
            <van-button size="small" :loading="loading" @click="run('extend')"
              >延长保留</van-button
            >
          </template>
        </div>
      </template>
    </template>

    <template v-else-if="canManage">
      <label for="project-archive-reason">归档原因（必填）</label>
      <textarea
        id="project-archive-reason"
        v-model="reason"
        maxlength="500"
        rows="2"
        placeholder="例如：课程项目已结束"
      />
      <van-button
        type="danger"
        plain
        size="small"
        :loading="loading"
        @click="run('archive')"
      >
        归档项目
      </van-button>
    </template>
  </section>
</template>

<style scoped>
.archive-action {
  display: grid;
  gap: 0.75rem;
}
.archive-action p {
  margin: 0;
}
.archive-action textarea {
  width: 100%;
  max-width: 36rem;
  min-height: 4.5rem;
}
.archive-controls {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.75rem;
}
.archive-controls select {
  min-height: 2.25rem;
  padding: 0.3rem;
}
</style>
