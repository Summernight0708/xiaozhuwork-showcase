<script setup lang="ts">
import ContextHelpLink from "@/components/help/ContextHelpLink.vue";
defineOptions({ name: "ProjectContributionsView" });

import { computed, onActivated, ref } from "vue";
import { useRoute } from "vue-router";
import { showToast } from "vant";
// Contribution examples are strictly explanatory and never issue export or review commands.

import PageState from "@/components/common/PageState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import TaskStars from "@/components/common/TaskStars.vue";
import EnhancedReportActions from "@/components/reports/EnhancedReportActions.vue";
import { PLAN_BENEFITS } from "@/components/upgrade/planBenefits";
import type { EnhancedReportAvailability } from "@/services/enhanced-report";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import { buildMemberContributionRows } from "@/domain/contribution-presentation";

const route = useRoute();
const { workspace, reload } = useWorkspaceRoute();

const reportLoaded = ref(false);
const exporting = ref<"csv" | "pdf" | null>(null);
const enhancedAvailability = computed<EnhancedReportAvailability>(() => {
  if (
    PLAN_BENEFITS.find((benefit) => benefit.name === "增强报告")?.status !==
    "released"
  )
    return "planned";
  return workspace.entitlement?.state === "active" ||
    workspace.entitlement?.state === "grace"
    ? "available"
    : "requires_pro";
});

const routedReportId = computed(() =>
  typeof route.params.reportId === "string" ? route.params.reportId : null,
);
const invalidReportDeepLink = computed(
  () =>
    reportLoaded.value &&
    !!routedReportId.value &&
    workspace.contributionReport?.reportId !== routedReportId.value,
);

const completedTasks = computed(() =>
  workspace.tasks.filter((task) => task.status === "completed"),
);
const activeTasks = computed(() =>
  workspace.tasks.filter((task) => task.status !== "canceled"),
);
const memberRows = computed(() =>
  buildMemberContributionRows({
    members: workspace.members,
    tasks: workspace.tasks,
    items: workspace.contributionReport?.items ?? [],
  }),
);
const recentContributions = computed(() =>
  [...(workspace.contributionReport?.items ?? [])]
    .sort(
      (left, right) =>
        Date.parse(right.completedAt) - Date.parse(left.completedAt),
    )
    .slice(0, 6),
);
const hasConfirmed = computed(() =>
  workspace.contributionConfirmations.some(
    (item) => item.user_id === workspace.currentUserId,
  ),
);
const projectPeriod = computed(() => {
  const project = workspace.project;
  if (!project) return "—";
  const start = project.start_at
    ? new Date(project.start_at).toLocaleDateString()
    : "未设置";
  return `${start} - ${new Date(project.deadline_at).toLocaleDateString()}`;
});

function roleLabel(role: string) {
  if (role === "leader") return "组长";
  if (role === "admin") return "管理员";
  if (role === "observer") return "观察者";
  return "成员";
}

function responsibilityLabel(taskId: string, memberUserId?: string) {
  const task = workspace.findTask(taskId);
  if (memberUserId && task?.assignee_id === memberUserId) {
    return "主负责 · 已通过";
  }
  return "已认可贡献";
}

async function load() {
  reportLoaded.value = false;
  await workspace.loadContributionReport();
  reportLoaded.value = true;
}

async function createReport() {
  const result = await workspace.createContributionReport();
  showToast(
    result.ok ? "贡献报告已生成" : workspace.actionError || "无法生成贡献报告",
  );
}

async function confirm() {
  const result = await workspace.confirmContributionReport();
  showToast(
    result.ok
      ? result.data.formalized
        ? "贡献报告已正式确认"
        : "已确认贡献报告"
      : workspace.actionError || "确认失败",
  );
}

async function exportReport(format: "csv" | "pdf") {
  exporting.value = format;
  try {
    const blob = await workspace.exportReport(format);
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `xiaozhu-project-report.${format}`;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    showToast("报告已导出");
  } catch {
    showToast("报告导出失败，请重试");
  } finally {
    exporting.value = null;
  }
}

onActivated(() => void load());
void load();
</script>

<template>
  <div class="xiaozhuwork-page contribution-page">
    <header class="page-heading">
      <div>
        <div class="page-title-line">
          <h1>贡献与报告</h1>
          <ContextHelpLink example-id="contribution" />
        </div>
      </div>
    </header>

    <PageState
      :loading="workspace.loading || !reportLoaded"
      :error="workspace.error"
      :not-found-or-denied="
        !workspace.project || !workspace.membership || invalidReportDeepLink
      "
      @retry="
        async () => {
          await reload();
          await load();
        }
      "
    >
      <section v-if="!workspace.contributionReport" class="contribution-empty">
        <div>
          <h2>还没有贡献记录</h2>
          <p>任务完成并通过验收后，贡献会显示在这里。</p>
        </div>
        <van-button
          v-if="workspace.capabilities.canCreateContributionReport"
          type="primary"
          :loading="workspace.pendingAction === 'create-report'"
          @click="createReport"
          >生成贡献报告</van-button
        >
        <p v-else class="muted">项目全部任务完成后，由组长生成贡献报告。</p>
      </section>

      <template v-else>
        <section
          class="project-progress"
          aria-labelledby="project-progress-title"
        >
          <div class="section-heading">
            <div>
              <h2 id="project-progress-title">项目完成情况</h2>
              <p>{{ workspace.project?.name }}</p>
            </div>
            <StatusBadge :status="workspace.contributionReport.state" />
          </div>
          <div class="summary-grid">
            <div>
              <strong
                >{{ completedTasks.length }} / {{ activeTasks.length }}</strong
              >
              <span>已完成任务</span>
            </div>
            <div>
              <strong>{{ workspace.contributionReport.items.length }}</strong>
              <span>已认可成果</span>
            </div>
            <div>
              <strong>
                {{ workspace.contributionReport.confirmedCount }} /
                {{ workspace.contributionReport.eligibleCount }}
              </strong>
              <span>成员已确认</span>
            </div>
          </div>
        </section>

        <section class="member-section" aria-labelledby="member-title">
          <div class="section-heading standalone">
            <div>
              <h2 id="member-title">成员贡献</h2>
              <p>保持项目成员顺序，不按贡献分排序。</p>
            </div>
          </div>

          <div class="member-grid">
            <article
              v-for="member in memberRows"
              :key="member.userId"
              class="member-card"
            >
              <header>
                <strong>{{ member.displayName }}</strong>
                <span>{{ roleLabel(member.role) }}</span>
              </header>
              <dl>
                <div>
                  <dt>主负责完成</dt>
                  <dd>{{ member.primaryCompleted ?? "—" }}</dd>
                </div>
                <div>
                  <dt>协作参与</dt>
                  <dd v-if="member.collaboratorParticipated !== null">
                    {{ member.collaboratorParticipated }}
                  </dd>
                  <dd
                    v-else
                    class="authority-pending"
                    title="当前权威贡献快照尚未提供协作者参与事实"
                  >
                    —
                  </dd>
                </div>
                <div v-if="member.contributionScore !== null">
                  <dt>贡献分</dt>
                  <dd>{{ member.contributionScore }}</dd>
                </div>
              </dl>
            </article>
          </div>

          <p class="authority-note">
            当前权威贡献快照只记录主负责人完成事实；协作者参与不会由前端推算，待统一贡献事实提供后再显示。
          </p>
        </section>

        <section
          v-if="recentContributions.length"
          class="recent-section"
          aria-labelledby="recent-title"
        >
          <div class="section-heading">
            <div>
              <h2 id="recent-title">最近贡献</h2>
              <p>星级表示任务难度 / 贡献权重。</p>
            </div>
          </div>
          <div class="recent-list">
            <article
              v-for="item in recentContributions"
              :key="item.taskId"
              class="recent-item"
            >
              <div>
                <strong>{{ item.taskTitle }}</strong>
                <span>{{
                  responsibilityLabel(item.taskId, item.memberUserId)
                }}</span>
              </div>
              <TaskStars v-if="item.taskWeight" :value="item.taskWeight" />
            </article>
          </div>
        </section>

        <section class="report-section" aria-labelledby="report-title">
          <div class="section-heading">
            <div>
              <h2 id="report-title">项目报告</h2>
              <p>确认与导出都以服务端正式报告状态为准。</p>
            </div>
            <StatusBadge :status="workspace.contributionReport.state" />
          </div>

          <dl class="report-facts">
            <div>
              <dt>项目</dt>
              <dd>{{ workspace.project?.name }}</dd>
            </div>
            <div>
              <dt>课程</dt>
              <dd>{{ workspace.project?.course_name || "未设置" }}</dd>
            </div>
            <div>
              <dt>项目周期</dt>
              <dd>{{ projectPeriod }}</dd>
            </div>
            <div>
              <dt>任务完成</dt>
              <dd>{{ completedTasks.length }} / {{ activeTasks.length }}</dd>
            </div>
            <div>
              <dt>成员确认</dt>
              <dd>
                {{ workspace.contributionReport.confirmedCount }} /
                {{ workspace.contributionReport.eligibleCount }}
                <small>
                  正式阈值 {{ workspace.contributionReport.requiredCount }}
                </small>
              </dd>
            </div>
            <div>
              <dt>报告状态</dt>
              <dd>
                {{
                  workspace.contributionReport.state === "formal"
                    ? "已正式确认"
                    : "等待成员确认"
                }}
              </dd>
            </div>
          </dl>

          <div
            v-if="workspace.contributionReport.state === 'draft'"
            class="report-actions"
          >
            <van-button
              v-if="workspace.capabilities.canConfirmContributionReport"
              type="primary"
              :disabled="hasConfirmed"
              :loading="workspace.pendingAction === 'confirm-report'"
              @click="confirm"
            >
              {{ hasConfirmed ? "你已确认" : "确认贡献报告" }}
            </van-button>
            <p class="muted">
              报告达到成员确认阈值后正式化；正式化前不开放 CSV / PDF 导出。
            </p>
          </div>

          <div v-else class="report-actions">
            <div class="action-row" aria-label="报告导出">
              <van-button
                plain
                :loading="exporting === 'csv'"
                :disabled="exporting !== null"
                @click="exportReport('csv')"
                >导出 CSV</van-button
              >
              <van-button
                type="primary"
                plain
                :loading="exporting === 'pdf'"
                :disabled="exporting !== null"
                @click="exportReport('pdf')"
                >导出 PDF</van-button
              >
            </div>
            <p class="muted">
              导出能力调用现有服务端报告接口；若服务端权限或 entitlement
              不允许，前端不会绕过。
            </p>
          </div>

          <EnhancedReportActions
            :report-id="workspace.contributionReport.reportId"
            :report-state="workspace.contributionReport.state"
            :can-read="Boolean(workspace.membership)"
            :availability="enhancedAvailability"
          />

          <p class="report-disclaimer">
            贡献记录仅反映项目内已完成并被认可的任务事实，不代表教师评分、成员能力评价或排行榜。
          </p>
        </section>
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.contribution-page {
}
.project-progress,
.recent-section,
.report-section {
  padding: var(--space-lg) 0;
  margin-bottom: var(--space-sm);
  border-bottom: 1px solid var(--tu-border);
}
.section-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  margin-bottom: 18px;
}
.section-heading.standalone {
  margin: 0 0 12px;
}
.section-heading h2,
.section-heading p {
  margin: 0;
}
.section-heading h2 {
  font-size: 19px;
}
.section-heading p {
  margin-top: 5px;
  color: var(--tu-muted);
  line-height: 1.5;
}
.summary-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 1px;
  overflow: hidden;
  border: 1px solid var(--tu-border);
  border-radius: 0;
  background: var(--tu-border);
}
.summary-grid > div {
  display: grid;
  gap: 3px;
  padding: 18px;
  background: var(--tu-surface);
}
.summary-grid strong {
  font-size: 24px;
  line-height: 1.2;
}
.summary-grid span,
.member-card header span,
.recent-item span,
.report-facts dt,
.report-facts small {
  color: var(--tu-muted);
  font-size: 13px;
}
.member-section {
  margin-bottom: 20px;
}
.member-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
  gap: var(--space-lg);
}
.member-card {
  padding: var(--space-md) 0;
  border-top: 1px solid var(--tu-border);
}
.member-card header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 10px;
  padding-bottom: 13px;
  border-bottom: 1px solid var(--tu-border);
}
.member-card dl {
  display: grid;
  gap: 10px;
  margin: 14px 0 0;
}
.member-card dl div {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.member-card dt {
  color: var(--tu-muted);
}
.member-card dd {
  margin: 0;
  font-weight: 700;
}
.authority-pending {
  color: var(--tu-muted);
}
.authority-note {
  margin: 10px 2px 0;
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.6;
}
.recent-list {
  display: grid;
}
.recent-item {
  min-height: 58px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  padding: 11px 0;
  border-top: 1px solid var(--tu-border);
}
.recent-item:first-child {
  border-top: 0;
}
.recent-item strong,
.recent-item span {
  display: block;
}
.recent-item span {
  margin-top: 4px;
}
.report-facts {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  margin: 0;
  border-top: 1px solid var(--tu-border);
}
.report-facts div {
  display: grid;
  grid-template-columns: 110px 1fr;
  gap: 14px;
  padding: 13px 0;
  border-bottom: 1px solid var(--tu-border);
}
.report-facts div:nth-child(odd) {
  padding-right: 24px;
}
.report-facts dd {
  margin: 0;
}
.report-facts small {
  display: block;
  margin-top: 3px;
}
.report-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  margin-top: 18px;
}
.report-actions p {
  margin: 0;
  line-height: 1.5;
}
.report-disclaimer {
  margin: 18px 0 0;
  padding: 12px 14px;
  border-left: 2px solid var(--tu-action);
  background: transparent;
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.6;
}
.contribution-empty {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  padding: var(--space-lg) 0;
}
.contribution-empty h2,
.contribution-empty p {
  margin: 0;
}
.contribution-empty p {
  margin-top: 7px;
  color: var(--tu-muted);
}
@media (max-width: 720px) {
  .summary-grid,
  .report-facts {
    grid-template-columns: 1fr;
  }
  .report-facts div:nth-child(odd) {
    padding-right: 0;
  }
  .report-actions,
  .contribution-empty {
    align-items: stretch;
    flex-direction: column;
  }
}
</style>
