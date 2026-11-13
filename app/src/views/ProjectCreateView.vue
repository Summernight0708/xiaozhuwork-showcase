<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { showToast } from "vant";

import { useProjectsStore } from "@/stores/projects";

const router = useRouter();
const projects = useProjectsStore();
const name = ref("");
const courseName = ref("");
const description = ref("");
const startDate = ref("");
const deadline = ref("");
const allowMemberTaskCreation = ref(true);
const enableStarContribution = ref(true);
const requireRealName = ref(false);
const requireStudentNumber = ref(false);
const confirming = ref(false);
const submitting = ref(false);

const valid = computed(() => {
  if (!name.value.trim() || !deadline.value) return false;
  if (
    startDate.value &&
    Date.parse(deadline.value) <= Date.parse(startDate.value)
  )
    return false;
  return Date.parse(deadline.value) > Date.now();
});

function review() {
  if (!valid.value) {
    showToast("请填写项目名称，并设置有效的未来 DDL");
    return;
  }
  confirming.value = true;
}

async function create() {
  submitting.value = true;
  try {
    const result = await projects.createProject({
      name: name.value.trim(),
      courseName: courseName.value.trim() || undefined,
      description: description.value.trim() || undefined,
      startAt: startDate.value
        ? new Date(startDate.value).toISOString()
        : undefined,
      deadlineAt: new Date(deadline.value).toISOString(),
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      contributionMode: enableStarContribution.value
        ? "weighted"
        : "facts_only",
      allowMemberTaskCreation: allowMemberTaskCreation.value,
      requireRealName: requireRealName.value,
      requireStudentNumber: requireStudentNumber.value,
    });
    if (!result.ok) {
      showToast(projects.error || "创建失败");
      return;
    }
    showToast("项目已创建");
    await router.replace({
      name: "project-overview",
      params: { projectId: result.data.projectId },
    });
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <div class="xiaozhuwork-page form-page">
    <header class="page-heading">
      <div>
        <h1>创建项目</h1>
      </div>
    </header>

    <form v-if="!confirming" class="form-surface" @submit.prevent="review">
      <van-field
        v-model="name"
        name="projectName"
        autocomplete="off"
        label="项目名称"
        required
        maxlength="80"
        placeholder="例如：计算机视觉课程设计"
      />
      <van-field
        v-model="courseName"
        name="courseName"
        autocomplete="off"
        label="所属课程"
        maxlength="80"
        placeholder="可选"
      />
      <van-field
        v-model="description"
        name="description"
        autocomplete="off"
        label="项目描述"
        type="textarea"
        rows="4"
        maxlength="800"
        show-word-limit
        placeholder="可选，说明项目目标与交付内容"
      />
      <div class="native-field">
        <label for="start-date">开始日期 <span>可选</span></label>
        <input
          id="start-date"
          v-model="startDate"
          name="startAt"
          type="datetime-local"
          autocomplete="off"
        />
      </div>
      <div class="native-field">
        <label for="deadline">项目 DDL</label>
        <input
          id="deadline"
          v-model="deadline"
          name="deadlineAt"
          autocomplete="off"
          type="datetime-local"
          required
        />
      </div>
      <fieldset class="rules-fieldset">
        <legend>项目规则</legend>
        <label class="checkbox-row">
          <input
            v-model="allowMemberTaskCreation"
            name="allowMemberTaskCreation"
            type="checkbox"
          />
          <span>允许普通成员创建任务</span>
        </label>
        <label class="checkbox-row">
          <input
            v-model="enableStarContribution"
            name="enableStarContribution"
            type="checkbox"
          />
          <span>启用星级贡献统计</span>
        </label>
        <small
          >星级表示预计工作量，不是成员评分。关闭后仍保留任务和验收事实，不计算星级权重。</small
        >
      </fieldset>
      <fieldset class="rules-fieldset">
        <legend>成员资料要求</legend>
        <label class="checkbox-row">
          <input
            v-model="requireRealName"
            name="requireRealName"
            type="checkbox"
          />
          <span>要求真实姓名</span>
        </label>
        <label class="checkbox-row">
          <input
            v-model="requireStudentNumber"
            name="requireStudentNumber"
            type="checkbox"
          />
          <span>要求学号</span>
        </label>
      </fieldset>
      <div class="capability-note">
        默认成员角色固定为“成员”。创建完成后可通过成员管理调整角色；这里不展示后端尚未提供的伪配置。
      </div>
      <div class="form-actions">
        <RouterLink to="/projects"
          ><van-button plain>取消</van-button></RouterLink
        ><van-button type="primary" native-type="submit">继续确认</van-button>
      </div>
    </form>

    <section v-else class="confirmation">
      <h2>确认创建</h2>
      <dl>
        <div>
          <dt>项目名称</dt>
          <dd>{{ name }}</dd>
        </div>
        <div>
          <dt>课程</dt>
          <dd>{{ courseName || "未设置" }}</dd>
        </div>
        <div>
          <dt>描述</dt>
          <dd>{{ description || "未设置" }}</dd>
        </div>
        <div>
          <dt>开始时间</dt>
          <dd>
            {{ startDate ? new Date(startDate).toLocaleString() : "未设置" }}
          </dd>
        </div>
        <div>
          <dt>项目 DDL</dt>
          <dd>{{ new Date(deadline).toLocaleString() }}</dd>
        </div>
        <div>
          <dt>普通成员创建任务</dt>
          <dd>{{ allowMemberTaskCreation ? "允许" : "禁止" }}</dd>
        </div>
        <div>
          <dt>星级贡献统计</dt>
          <dd>{{ enableStarContribution ? "启用" : "关闭（仅记录事实）" }}</dd>
        </div>
        <div>
          <dt>真实姓名要求</dt>
          <dd>{{ requireRealName ? "需要" : "不强制" }}</dd>
        </div>
        <div>
          <dt>学号要求</dt>
          <dd>{{ requireStudentNumber ? "需要" : "不强制" }}</dd>
        </div>
        <div>
          <dt>默认成员角色</dt>
          <dd>成员</dd>
        </div>
      </dl>
      <p class="notice">
        创建后你将成为组长；项目初始只有你本人，后续通过邀请链接邀请成员。
      </p>
      <div class="form-actions">
        <van-button plain @click="confirming = false">返回修改</van-button>
        <van-button type="primary" :loading="submitting" @click="create"
          >确认创建</van-button
        >
      </div>
    </section>
  </div>
</template>

<style scoped>
.form-page {
  width: 100%;
  max-width: none;
}
.form-surface,
.confirmation {
  padding: var(--space-lg) 0;
  border-top: 1px solid var(--tu-border);
}
.native-field {
  display: grid;
  grid-template-columns: 130px 1fr;
  gap: 16px;
  align-items: center;
  min-height: 54px;
  padding: 8px 16px;
  border-bottom: 1px solid var(--tu-border);
}
.native-field label {
  font-size: 14px;
  color: var(--tu-muted);
}
.native-field label span {
  color: var(--tu-muted);
  margin-left: 4px;
}
.native-field input {
  min-height: 40px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 0 10px;
}
.rules-fieldset {
  display: grid;
  gap: 10px;
  margin: 18px 0 0;
  padding: 16px;
  border: 0;
  border-top: 1px solid var(--tu-border);
  border-radius: 0;
}
.rules-fieldset legend {
  padding: 0 6px;
  font-weight: 700;
}
.checkbox-row {
  display: flex;
  align-items: center;
  gap: 9px;
  min-height: 40px;
}
.checkbox-row input {
  width: 18px;
  height: 18px;
}
.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 22px;
}
.confirmation h2 {
  margin-top: 0;
}
.confirmation dl {
  display: grid;
  gap: 0;
}
.confirmation dl div {
  display: grid;
  grid-template-columns: 130px 1fr;
  gap: 16px;
  padding: 13px 0;
  border-bottom: 1px solid var(--tu-border);
}
.confirmation dt {
  color: var(--tu-muted);
}
.confirmation dd {
  margin: 0;
  white-space: pre-wrap;
}
.notice {
  padding: 12px 14px;
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
}
@media (max-width: 600px) {
  .form-surface,
  .confirmation {
    padding: var(--space-md) 0;
  }
  .native-field,
  .confirmation dl div {
    grid-template-columns: 1fr;
    gap: 6px;
  }
}
</style>
