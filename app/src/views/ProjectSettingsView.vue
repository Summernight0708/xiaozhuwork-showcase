<script setup lang="ts">
import { computed, reactive, watch } from "vue";
import { useRouter } from "vue-router";
import { showConfirmDialog, showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import ArchiveProjectAction from "@/components/projects/ArchiveProjectAction.vue";
import ProjectPenaltyPolicyPanel from "@/components/contributions/ProjectPenaltyPolicyPanel.vue";
import { formatProjectEntitlement } from "@/domain/entitlements";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";

const { workspace, reload } = useWorkspaceRoute();
const router = useRouter();

const activePrimaryTaskCount = computed(
  () =>
    workspace.tasks.filter(
      (task) =>
        task.assignee_id === workspace.currentUserId &&
        task.status !== "completed" &&
        task.status !== "canceled",
    ).length,
);
const canLeaveProject = computed(
  () =>
    workspace.project?.lifecycle_state === "active" &&
    workspace.role !== "leader" &&
    activePrimaryTaskCount.value === 0,
);

const entitlementPresentation = computed(() =>
  workspace.entitlement
    ? formatProjectEntitlement(workspace.entitlement)
    : null,
);

const form = reactive({
  name: "",
  courseName: "",
  description: "",
  startAt: "",
  deadlineAt: "",
  timezone: "",
  contributionMode: "weighted" as "weighted" | "facts_only",
  allowMemberTaskCreation: true,
  requireRealName: false,
  requireStudentNumber: false,
});

const contributionModeLocked = computed(() => workspace.tasks.length > 0);
const enableStarContribution = computed({
  get: () => form.contributionMode === "weighted",
  set: (enabled: boolean) => {
    form.contributionMode = enabled ? "weighted" : "facts_only";
  },
});
const identityEscalationLocked = computed(
  () =>
    workspace.members.filter(
      (member) => member.member_state === "active" && member.user_id,
    ).length > 1,
);

function toDatetimeLocal(value: string) {
  const date = new Date(value);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function syncForm() {
  const project = workspace.project;
  if (!project) return;
  form.name = project.name;
  form.courseName = project.course_name ?? "";
  form.description = project.description ?? "";
  form.startAt = project.start_at ? toDatetimeLocal(project.start_at) : "";
  form.deadlineAt = toDatetimeLocal(project.deadline_at);
  form.timezone = project.timezone;
  form.contributionMode =
    project.contribution_mode === "facts_only" ? "facts_only" : "weighted";
  form.allowMemberTaskCreation = project.allow_member_task_creation;
  form.requireRealName = project.require_real_name;
  form.requireStudentNumber = project.require_student_number;
}

async function save() {
  if (!workspace.project) return;
  const deadline = new Date(form.deadlineAt);
  const start = form.startAt ? new Date(form.startAt) : null;
  if (
    !form.name.trim() ||
    Number.isNaN(deadline.getTime()) ||
    (start && (Number.isNaN(start.getTime()) || start >= deadline))
  ) {
    showToast("请填写有效的项目名称，并确保开始时间早于项目 DDL");
    return;
  }
  const result = await workspace.updateProjectSettings({
    name: form.name.trim(),
    courseName: form.courseName.trim() || undefined,
    description: form.description.trim() || undefined,
    startAt: start?.toISOString(),
    deadlineAt: deadline.toISOString(),
    timezone: form.timezone.trim(),
    contributionMode: form.contributionMode,
    allowMemberTaskCreation: form.allowMemberTaskCreation,
    autoPenaltyEnabled: workspace.project.auto_penalty_enabled,
    requireRealName: form.requireRealName,
    requireStudentNumber: form.requireStudentNumber,
  });
  showToast(result.ok ? "项目设置已保存" : workspace.actionError || "保存失败");
  syncForm();
}

async function leaveProject() {
  if (!canLeaveProject.value) return;
  try {
    await showConfirmDialog({
      title: "退出项目",
      message: "退出后你将失去项目访问权限，已经产生的协作与贡献记录仍会保留。",
      confirmButtonText: "确认退出",
    });
  } catch {
    return;
  }

  const result = await workspace.leaveProject();
  if (!result.ok) {
    showToast(workspace.actionError || "退出项目失败");
    return;
  }
  showToast("已退出项目");
  await router.replace("/projects");
}

watch(() => workspace.project, syncForm, { immediate: true });
</script>

<template>
  <div class="xiaozhuwork-page settings-page">
    <header class="page-heading">
      <div>
        <h1>项目设置</h1>
      </div>
      <van-button
        v-if="workspace.capabilities.canUpdateProjectSettings"
        type="primary"
        :loading="workspace.pendingAction === 'project-settings'"
        @click="save"
        >保存设置</van-button
      >
    </header>

    <div v-if="workspace.actionError" class="error-banner" role="alert">
      {{ workspace.actionError }}
    </div>

    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :empty="!workspace.project"
      empty-title="项目不存在或无权访问"
      @retry="reload"
    >
      <template v-if="workspace.project">
        <section
          v-if="entitlementPresentation"
          class="surface setting-section entitlement-section"
        >
          <div class="entitlement-heading">
            <div>
              <h2>项目方案</h2>
              <p class="plan-name">{{ entitlementPresentation.label }}</p>
            </div>
            <RouterLink class="learn-pro-link" to="/upgrade"
              >了解 Pro</RouterLink
            >
          </div>
          <p>{{ entitlementPresentation.detail }}</p>
          <p
            v-if="
              entitlementPresentation.isGrace &&
              entitlementPresentation.graceExpiryLabel
            "
          >
            宽限至 {{ entitlementPresentation.graceExpiryLabel }}
          </p>
        </section>

        <section class="surface setting-section">
          <h2>基本信息</h2>
          <template v-if="workspace.capabilities.canUpdateProjectSettings">
            <div class="form-grid">
              <label>
                <span>项目名称</span>
                <input
                  v-model="form.name"
                  name="projectName"
                  maxlength="120"
                  autocomplete="off"
                />
              </label>
              <label>
                <span>课程</span>
                <input
                  v-model="form.courseName"
                  name="courseName"
                  maxlength="120"
                  autocomplete="off"
                />
              </label>
              <label class="wide">
                <span>描述</span>
                <textarea
                  v-model="form.description"
                  name="description"
                  autocomplete="off"
                  rows="4"
                  maxlength="2000"
                />
              </label>
              <label>
                <span>开始时间（可选）</span>
                <input
                  id="project-start-at"
                  v-model="form.startAt"
                  name="startAt"
                  autocomplete="off"
                  type="datetime-local"
                />
              </label>
              <label>
                <span>项目 DDL</span>
                <input
                  v-model="form.deadlineAt"
                  name="deadlineAt"
                  type="datetime-local"
                  autocomplete="off"
                />
              </label>
              <label>
                <span>时区</span>
                <input
                  v-model="form.timezone"
                  name="timezone"
                  placeholder="Asia/Shanghai"
                  autocomplete="off"
                />
              </label>
            </div>
          </template>
          <dl v-else>
            <div>
              <dt>项目名称</dt>
              <dd>{{ workspace.project.name }}</dd>
            </div>
            <div>
              <dt>课程</dt>
              <dd>{{ workspace.project.course_name || "未设置" }}</dd>
            </div>
            <div>
              <dt>开始时间</dt>
              <dd>
                {{
                  workspace.project.start_at
                    ? new Date(workspace.project.start_at).toLocaleString()
                    : "未设置"
                }}
              </dd>
            </div>
            <div>
              <dt>项目 DDL</dt>
              <dd>
                {{ new Date(workspace.project.deadline_at).toLocaleString() }}
              </dd>
            </div>
            <div>
              <dt>时区</dt>
              <dd>{{ workspace.project.timezone }}</dd>
            </div>
            <div>
              <dt>贡献模式</dt>
              <dd>
                {{
                  workspace.project.contribution_mode === "weighted"
                    ? "按任务工作量星级统计"
                    : "仅记录贡献事实"
                }}
              </dd>
            </div>
          </dl>
        </section>

        <section class="surface setting-section">
          <h2>成员与数据</h2>
          <div
            v-if="workspace.capabilities.canUpdateProjectSettings"
            class="toggle-list"
          >
            <label>
              <input
                v-model="form.allowMemberTaskCreation"
                name="allowMemberTaskCreation"
                type="checkbox"
              />
              <span>允许普通成员创建任务</span>
            </label>
            <label>
              <input
                v-model="enableStarContribution"
                name="enableStarContribution"
                type="checkbox"
                aria-describedby="star-contribution-hint"
                :disabled="contributionModeLocked"
              />
              <span>启用星级贡献统计</span>
            </label>
            <p id="star-contribution-hint">
              星级表示预计工作量，不是成员评分。关闭后仍保留任务和验收事实，不计算星级权重。
            </p>
            <p v-if="contributionModeLocked">
              已有任务，不能切换星级贡献统计。
            </p>
            <label>
              <input
                v-model="form.requireRealName"
                name="requireRealName"
                type="checkbox"
                :disabled="
                  identityEscalationLocked &&
                  !workspace.project.require_real_name
                "
              />
              <span>要求真实姓名</span>
            </label>
            <label>
              <input
                v-model="form.requireStudentNumber"
                name="requireStudentNumber"
                type="checkbox"
                :disabled="
                  identityEscalationLocked &&
                  !workspace.project.require_student_number
                "
              />
              <span>要求学号</span>
            </label>
          </div>
          <template v-else>
            <p>
              普通成员创建任务：{{
                workspace.project.allow_member_task_creation ? "允许" : "禁止"
              }}
            </p>
            <p>
              星级贡献统计：{{
                workspace.project.contribution_mode === "weighted"
                  ? "启用"
                  : "关闭（仅记录事实）"
              }}
            </p>
            <p>
              真实姓名：{{
                workspace.project.require_real_name ? "需要" : "不强制"
              }}
            </p>
            <p>
              学号：{{
                workspace.project.require_student_number ? "需要" : "不强制"
              }}
            </p>
          </template>
        </section>

        <section class="surface setting-section">
          <h2>项目规则</h2>
          <p>
            已有任务时，切换贡献模式以及提高实名或学号要求仍需额外治理确认；本页不会绕开原有安全限制。
          </p>
        </section>
        <ProjectPenaltyPolicyPanel
          v-if="
            workspace.project.contribution_mode === 'weighted' &&
            typeof workspace.project.version === 'number'
          "
          :project-id="workspace.project.id"
          :project-version="workspace.project.version"
          :enabled="workspace.project.auto_penalty_enabled"
          :active-member-ids="
            (workspace.members ?? [])
              .filter(
                (member) =>
                  member.user_id &&
                  member.member_state === 'active' &&
                  !member.is_observer &&
                  member.role !== 'observer',
              )
              .map((member) => member.user_id!)
          "
          :user-id="workspace.currentUserId"
          :can-manage="
            workspace.role === 'leader' && !workspace.project.archived_at
          "
          :can-consent="
            workspace.role !== 'observer' &&
            !!workspace.membership &&
            !workspace.project.archived_at
          "
          @updated="reload"
        />
        <section
          class="membership-exit"
          aria-labelledby="membership-exit-title"
        >
          <h2 id="membership-exit-title">成员关系</h2>
          <p v-if="workspace.role === 'leader'">
            组长需先转让组长身份，再退出项目。
          </p>
          <p v-else-if="activePrimaryTaskCount > 0">
            你还有
            {{ activePrimaryTaskCount }}
            个未完成的主负责人任务，请先完成或移交。
          </p>
          <p v-else-if="workspace.project.lifecycle_state !== 'active'">
            项目已进入收口状态，可继续保留历史访问记录。
          </p>
          <template v-else>
            <p>不再参与该项目时，可以主动退出；历史协作记录不会被删除。</p>
            <button
              type="button"
              class="leave-project-action"
              :disabled="workspace.pendingAction === 'leave-project'"
              @click="leaveProject"
            >
              退出项目
            </button>
          </template>
        </section>
        <ArchiveProjectAction
          :project-id="workspace.project.id"
          :version="workspace.project.version"
          :archived-at="workspace.project.archived_at"
          :can-manage="workspace.role === 'leader'"
          @updated="reload"
        />
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.settings-page {
  width: 100%;
  max-width: none;
}
.setting-section {
  padding: 22px;
  margin-bottom: 16px;
}
.setting-section h2 {
  margin: 0 0 14px;
  font-size: 18px;
}
.entitlement-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
}
.learn-pro-link {
  min-height: 42px;
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  padding: 8px 10px;
  border-radius: 8px;
  color: var(--tu-blue-strong);
  font-weight: 650;
}
@media (hover: hover) {
  .learn-pro-link:hover {
    background: var(--tu-blue-soft);
  }
}
.plan-name {
  margin: 0 0 8px;
  font-size: 22px;
  font-weight: 700;
  color: var(--tu-ink) !important;
}
.setting-section dl {
  margin: 0;
}
.setting-section dl div {
  display: grid;
  grid-template-columns: 180px 1fr;
  gap: 16px;
  padding: 12px 0;
  border-top: 1px solid var(--tu-border);
}
.setting-section dt,
.setting-section p,
.form-grid span {
  color: var(--tu-muted);
}
.setting-section dd {
  margin: 0;
}
.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}
.form-grid label,
.toggle-list {
  display: grid;
  gap: 7px;
}
.form-grid .wide {
  grid-column: 1 / -1;
}
.form-grid input,
.form-grid textarea,
.form-grid select {
  width: 100%;
  min-height: 42px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  padding: 9px 11px;
  background: var(--tu-surface);
  font: inherit;
}
.form-grid textarea {
  resize: vertical;
}
.toggle-list label {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 9px 0;
}
.membership-exit {
  padding: 18px 0;
  margin-top: 8px;
  border-top: 1px solid var(--tu-border);
}
.membership-exit h2 {
  margin: 0 0 8px;
  font-size: 16px;
}
.membership-exit p {
  margin: 0 0 10px;
  color: var(--tu-muted);
}
.leave-project-action {
  border: 0;
  padding: 4px 0;
  background: transparent;
  color: var(--tu-danger);
  font: inherit;
  font-weight: 650;
  cursor: pointer;
}
.leave-project-action:disabled {
  opacity: 0.55;
  cursor: default;
}

@media (max-width: 600px) {
  .entitlement-heading {
    align-items: stretch;
    flex-direction: column;
  }
  .setting-section dl div,
  .form-grid {
    grid-template-columns: 1fr;
  }
  .form-grid .wide {
    grid-column: auto;
  }
}
</style>
