<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showConfirmDialog, showToast } from "vant";
import ExternalEvidenceForm from "@/components/evidence/ExternalEvidenceForm.vue";
import ExternalEvidenceList from "@/components/evidence/ExternalEvidenceList.vue";
import { createExternalEvidenceRepository } from "@/features/external-evidence/repository";
import type {
  EvidenceDraft,
  ExternalEvidence,
  ExternalEvidenceRevision,
} from "@/features/external-evidence/types";
import { getBackend } from "@/services/backend";

const props = defineProps<{
  projectId: string;
  taskId: string;
  taskVersion: number;
  canWrite: boolean;
  canManage: boolean;
  userId: string | null;
  memberNames?: Record<string, string>;
}>();
const items = ref<ExternalEvidence[]>([]);
const revisions = ref<ExternalEvidenceRevision[]>([]);
const historyItem = ref<ExternalEvidence | null>(null);
const editing = ref<ExternalEvidence | null>(null);
const formOpen = ref(false);
const busy = ref(false);
const loading = ref(false);
const error = ref("");
const retry = ref<{ fingerprint: string; requestId: string } | null>(null);

function repository() {
  const backend = getBackend();
  if (!backend) throw new Error("后端暂不可用");
  return createExternalEvidenceRepository(backend.client);
}
const editableIds = computed(() =>
  !props.canWrite
    ? []
    : items.value
        .filter(
          (item) =>
            !item.revokedAt &&
            (props.canManage ||
              (!!props.userId && item.submittedBy === props.userId)),
        )
        .map((item) => item.id),
);
function idFor(payload: unknown) {
  const fingerprint = JSON.stringify(payload);
  if (retry.value?.fingerprint !== fingerprint)
    retry.value = { fingerprint, requestId: crypto.randomUUID() };
  return retry.value.requestId;
}
async function refresh() {
  loading.value = true;
  error.value = "";
  try {
    items.value = await repository().list(props.projectId, props.taskId);
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "读取证据失败";
  } finally {
    loading.value = false;
  }
}
watch(
  () => [props.projectId, props.taskId],
  () => {
    editing.value = null;
    formOpen.value = false;
    historyItem.value = null;
    revisions.value = [];
    retry.value = null;
    void refresh();
  },
  { immediate: true },
);
function closeForm() {
  editing.value = null;
  formOpen.value = false;
  retry.value = null;
}
async function save(draft: EvidenceDraft) {
  if (!props.canWrite || busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    const target = editing.value;
    const requestId = idFor({
      action: target ? "update" : "create",
      targetId: target?.id ?? props.taskId,
      version: target?.version ?? props.taskVersion,
      draft,
    });
    const result = target
      ? await repository().update({
          projectId: props.projectId,
          evidenceId: target.id,
          requestId,
          expectedVersion: target.version,
          ...draft,
        })
      : await repository().create({
          projectId: props.projectId,
          taskId: props.taskId,
          requestId,
          expectedVersion: props.taskVersion,
          ...draft,
        });
    if (!result.ok) throw new Error(result.code);
    closeForm();
    await refresh();
    showToast("外部证据已保存");
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "保存失败";
  } finally {
    busy.value = false;
  }
}
async function revoke(item: ExternalEvidence) {
  if (!editableIds.value.includes(item.id) || busy.value) return;
  try {
    await showConfirmDialog({
      title: "撤销外部链接",
      message:
        "撤销只影响 XiaozhuWork 中的引用，第三方内容不会被删除。确认撤销？",
    });
  } catch {
    return;
  }
  busy.value = true;
  error.value = "";
  try {
    const requestId = idFor({
      action: "revoke",
      id: item.id,
      version: item.version,
    });
    const result = await repository().remove({
      projectId: props.projectId,
      evidenceId: item.id,
      requestId,
      expectedVersion: item.version,
    });
    if (!result.ok) throw new Error(result.code);
    retry.value = null;
    await refresh();
    showToast("已撤销");
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "撤销失败";
  } finally {
    busy.value = false;
  }
}
async function history(item: ExternalEvidence) {
  historyItem.value = item;
  revisions.value = [];
  error.value = "";
  try {
    revisions.value = await repository().revisions(props.projectId, item.id);
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "读取修订失败";
  }
}
</script>

<template>
  <div class="task-evidence">
    <div class="task-evidence__head">
      <strong>外部链接证据</strong>
      <button type="button" :disabled="busy || loading" @click="refresh">
        刷新
      </button>
    </div>
    <p>只保存链接元数据，不抓取、托管或版本管理第三方内容。</p>
    <p v-if="error" role="alert" class="task-evidence__error">{{ error }}</p>
    <p v-if="loading" role="status">正在读取…</p>
    <ExternalEvidenceList
      v-else
      :items="items"
      :editable-ids="editableIds"
      :busy="busy"
      :member-names="memberNames"
      @edit="
        (item) => {
          editing = item;
          formOpen = true;
          retry = null;
        }
      "
      @remove="revoke"
      @history="history"
    />
    <button
      v-if="canWrite && !formOpen"
      type="button"
      :disabled="busy"
      @click="formOpen = true"
    >
      添加外部证据
    </button>
    <ExternalEvidenceForm
      v-if="canWrite && formOpen"
      :initial="
        editing
          ? { httpsUrl: editing.httpsUrl, description: editing.description }
          : undefined
      "
      :editing="!!editing"
      :busy="busy"
      @submit="save"
      @cancel="closeForm"
    />
    <section
      v-if="historyItem"
      class="task-evidence__history"
      aria-label="链接修订"
    >
      <div class="task-evidence__head">
        <strong>{{ historyItem.host }} · 修订历史</strong>
        <button type="button" @click="historyItem = null">收起</button>
      </div>
      <p v-if="!revisions.length">暂无修订。</p>
      <ul v-else>
        <li v-for="revision in revisions" :key="revision.id">
          第 {{ revision.version }} 版 ·
          {{ revision.action === "removed" ? "撤销" : "编辑" }} ·
          {{ new Date(revision.changedAt).toLocaleString() }}
        </li>
      </ul>
    </section>
  </div>
</template>

<style scoped>
.task-evidence {
  display: grid;
  gap: 0.75rem;
}
.task-evidence__head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 0.8rem;
}
.task-evidence p {
  margin: 0;
  line-height: 1.6;
}
.task-evidence button {
  min-height: 36px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 0.4rem 0.8rem;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.task-evidence__error {
  color: var(--tu-danger);
}
.task-evidence__history {
  border-top: 1px solid var(--tu-border);
  padding-top: 0.8rem;
}
</style>
