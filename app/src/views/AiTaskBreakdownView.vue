<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import {
  AI_BREAKDOWN,
  createDrafts,
  draftToTaskInput,
  resolveDraftWeight,
  suggestDeadlines,
  validateDraft,
  type AiTaskDraft,
} from "@/domain/ai-breakdown";
import { submissionFileTypeLabel } from "@/domain/submission-file-types";
import {
  aiTaskBreakdownErrorMessage,
  isAiTaskBreakdownAbort,
  requestAiTaskBreakdown,
} from "@/services/ai-task-breakdown";

const router = useRouter();
const { workspace, projectId, reload } = useWorkspaceRoute();

const prompt = ref("");
const taskCount = ref(AI_BREAKDOWN.defaultTasks);
const generating = ref(false);
const generatedModel = ref("");
const drafts = ref<AiTaskDraft[]>([]);
const importing = ref(false);
const importProgress = ref("");
let generationAbort: AbortController | null = null;

const selectedCount = computed(
  () => drafts.value.filter((draft) => draft.selected).length,
);

function projectDeadlineAt() {
  return workspace.project?.deadline_at ?? "";
}

function deadlineText(iso: string): string {
  const date = new Date(iso);
  if (!Number.isFinite(date.getTime())) return "—";
  return date.toLocaleString("zh-CN", {
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

async function generate() {
  const text = prompt.value.trim();
  if (text.length < AI_BREAKDOWN.minPromptChars) {
    showToast(`请先粘贴作业要求（至少 ${AI_BREAKDOWN.minPromptChars} 个字）`);
    return;
  }
  generationAbort?.abort();
  generationAbort = new AbortController();
  generating.value = true;
  generatedModel.value = "";
  try {
    const result = await requestAiTaskBreakdown(
      text,
      taskCount.value,
      generationAbort.signal,
    );
    const deadlineAt = projectDeadlineAt();
    if (!deadlineAt) {
      showToast("项目信息不可用，请稍后重试");
      return;
    }
    drafts.value = createDrafts(result.items, deadlineAt);
    generatedModel.value = result.model;
    showToast(`已生成 ${drafts.value.length} 个任务建议，请确认后导入`);
  } catch (caught) {
    if (isAiTaskBreakdownAbort(caught)) return;
    showToast(aiTaskBreakdownErrorMessage(caught));
  } finally {
    generating.value = false;
  }
}

function updateDuration(draft: AiTaskDraft, value: number | string) {
  draft.durationDays = Math.min(
    AI_BREAKDOWN.maxDurationDays,
    Math.max(AI_BREAKDOWN.minDurationDays, Number(value) || 1),
  );
  const deadlineAt = projectDeadlineAt();
  if (!deadlineAt) return;
  const deadlines = suggestDeadlines(drafts.value, deadlineAt);
  drafts.value.forEach((item, index) => {
    item.deadlineAt = deadlines[index] ?? "";
  });
}

async function importSelected() {
  if (importing.value) return;
  const selected = drafts.value.filter((draft) => draft.selected);
  if (!selected.length) {
    showToast("请先勾选要导入的任务");
    return;
  }
  if (!workspace.project || !workspace.membership) {
    showToast("项目信息不可用，请稍后重试");
    return;
  }
  const deadlineAt = projectDeadlineAt();
  for (const draft of selected) {
    const validationError = validateDraft(draft, deadlineAt);
    if (validationError) {
      showToast(`「${draft.title.trim()}」${validationError}`);
      return;
    }
  }

  importing.value = true;
  let imported = 0;
  try {
    await reload();
    if (
      !workspace.project ||
      !workspace.membership ||
      !workspace.capabilities.canCreateTask
    ) {
      showToast("你当前没有在此项目创建任务的权限，成员身份可能已变化。");
      return;
    }
    if (workspace.project.lifecycle_state !== "active") {
      showToast("项目状态已变化，当前不能再创建任务。");
      return;
    }
    for (const draft of selected) {
      importProgress.value = `正在导入 ${imported + 1}/${selected.length}`;
      const result = await workspace.createTask({
        ...draftToTaskInput(draft),
        weight: resolveDraftWeight(workspace.project.contribution_mode),
      });
      if (!result.ok) {
        showToast(
          workspace.actionError ||
            `「${draft.title.trim()}」导入失败，已导入 ${imported} 个任务`,
        );
        return;
      }
      imported += 1;
    }
    showToast(`已导入 ${imported} 个任务`);
    await router.replace({
      name: "project-tasks",
      params: { projectId: projectId.value },
    });
  } finally {
    importing.value = false;
    importProgress.value = "";
  }
}
</script>

<template>
  <div class="xiaozhuwork-page form-page">
    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :permission-denied="
        !!workspace.membership && !workspace.capabilities.canCreateTask
      "
      @retry="reload"
    >
      <template v-if="workspace.capabilities.canCreateTask">
        <header class="page-heading">
          <div>
            <h1>AI 智能拆解</h1>
            <p>粘贴课程作业要求，AI 生成任务清单，确认后一键导入项目。</p>
          </div>
        </header>

        <section class="form-surface ai-source">
          <van-field
            v-model="prompt"
            type="textarea"
            rows="5"
            autosize
            maxlength="4000"
            show-word-limit
            label="作业要求"
            placeholder="粘贴老师发布的作业要求原文，例如：完成一份市场调研报告，包含问卷设计、数据分析和 PPT 汇报……"
          />
          <div class="ai-options">
            <span class="ai-options-label">拆解任务数</span>
            <van-stepper
              v-model="taskCount"
              :min="AI_BREAKDOWN.minTasks"
              :max="AI_BREAKDOWN.maxTasks"
            />
          </div>
          <div class="ai-actions">
            <van-button
              type="primary"
              block
              :loading="generating"
              loading-text="AI 生成中…"
              @click="generate"
            >
              生成任务建议
            </van-button>
          </div>
          <p class="ai-note">
            AI
            生成内容仅供参考，请确认后导入；作业描述仅用于本次生成，不会被保存。
          </p>
        </section>

        <section v-if="drafts.length" class="form-surface ai-results">
          <div class="ai-results-head">
            <h2>
              任务建议<span v-if="generatedModel"> · {{ generatedModel }}</span>
            </h2>
            <span class="ai-selected-count">
              已选 {{ selectedCount }}/{{ drafts.length }}
            </span>
          </div>
          <div
            v-for="(draft, index) in drafts"
            :key="draft.key"
            class="ai-draft"
          >
            <div class="ai-draft-head">
              <van-checkbox v-model="draft.selected" :name="draft.key" />
              <span class="ai-draft-index">{{ index + 1 }}</span>
              <van-field
                v-model="draft.title"
                class="ai-draft-title"
                maxlength="60"
                placeholder="任务名称"
              />
            </div>
            <van-field
              v-model="draft.description"
              type="textarea"
              rows="2"
              autosize
              maxlength="200"
              placeholder="任务说明（产出物与验收标准）"
            />
            <div class="ai-draft-meta">
              <div class="ai-draft-duration">
                <span>工期（天）</span>
                <van-stepper
                  :model-value="draft.durationDays"
                  :min="AI_BREAKDOWN.minDurationDays"
                  :max="AI_BREAKDOWN.maxDurationDays"
                  @change="updateDuration(draft, $event)"
                />
              </div>
              <div class="ai-draft-deadline">
                <span>建议截止</span>
                <strong>{{ deadlineText(draft.deadlineAt) }}</strong>
              </div>
            </div>
            <div v-if="draft.fileTypes.length" class="ai-draft-tags">
              <span class="ai-draft-tags-label">提交格式</span>
              <van-tag
                v-for="type in draft.fileTypes"
                :key="type"
                plain
                type="primary"
              >
                {{ submissionFileTypeLabel(type) }}
              </van-tag>
            </div>
          </div>
          <div class="ai-actions">
            <van-button
              type="primary"
              block
              :loading="importing"
              :loading-text="importProgress || '导入中…'"
              @click="importSelected"
            >
              导入所选任务（{{ selectedCount }}）
            </van-button>
          </div>
        </section>
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.form-page {
  width: 100%;
  max-width: none;
}

.ai-source,
.ai-results {
  margin-bottom: var(--space-lg);
}

.ai-options {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-md);
  padding: var(--space-sm) var(--space-md) 0;
}

.ai-options-label {
  font-size: var(--text-sm);
  color: var(--tu-muted);
}

.ai-actions {
  padding: var(--space-md);
}

.ai-note {
  margin: 0;
  padding: 0 var(--space-md) var(--space-md);
  font-size: var(--text-xs);
  color: var(--tu-muted);
}

.ai-results-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: var(--space-md);
  padding: var(--space-md) var(--space-md) 0;
}

.ai-results-head h2 {
  margin: 0;
  font-size: var(--text-lg);
  letter-spacing: -0.02em;
}

.ai-selected-count {
  font-size: var(--text-sm);
  color: var(--tu-muted);
}

.ai-draft {
  border-bottom: 1px solid var(--tu-border);
  padding: var(--space-sm) var(--space-md) var(--space-md);
}

.ai-draft:last-of-type {
  border-bottom: none;
}

.ai-draft-head {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.ai-draft-index {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  font-size: var(--text-xs);
  flex-shrink: 0;
}

.ai-draft-title {
  flex: 1;
}

.ai-draft-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-md);
  padding-top: var(--space-xs);
}

.ai-draft-duration {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.ai-draft-duration > span,
.ai-draft-deadline > span,
.ai-draft-tags-label {
  font-size: var(--text-xs);
  color: var(--tu-muted);
}

.ai-draft-deadline {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.ai-draft-deadline strong {
  font-size: var(--text-sm);
  font-weight: 600;
}

.ai-draft-tags {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--space-2xs);
  padding-top: var(--space-sm);
}
</style>
