<script setup lang="ts">
defineOptions({ name: "CrossProjectOverviewView" });

import { computed, onActivated, onMounted, ref } from "vue";

import CrossProjectList from "@/components/cross-project/CrossProjectList.vue";
import CrossProjectStatistics from "@/components/cross-project/CrossProjectStatistics.vue";
import CrossProjectTrend from "@/components/cross-project/CrossProjectTrend.vue";
import {
  loadCrossProjectAnalytics,
  searchCrossProjects,
  type CrossProject,
  type CrossProjectAnalytics,
} from "@/services/cross-project";

const DAY_MS = 86_400_000;
const initialNow = Date.now();
const utcDate = (ms: number) => new Date(ms).toISOString().slice(0, 10);

const searchText = ref("");
const appliedSearch = ref("");
const projects = ref<CrossProject[]>([]);
const nextCursor = ref<string | null>(null);
const selectedIds = ref<string[]>([]);
const includeAll = ref(true);
const fromDate = ref(utcDate(initialNow - 30 * DAY_MS));
const toDate = ref(utcDate(initialNow));
const loading = ref(false);
const analyzing = ref(false);
const accessError = ref<string | null>(null);
const accessCode = ref<string | null>(null);
const analyticsError = ref<string | null>(null);
const analytics = ref<CrossProjectAnalytics | null>(null);
let listGeneration = 0;
let analyticsGeneration = 0;

const planned = computed(() => accessCode.value === "CAPABILITY_NOT_AVAILABLE");
const noPro = computed(() => accessCode.value === "CAPABILITY_REQUIRES_PRO");

function errorText(error: unknown) {
  return error instanceof Error ? error.message : "加载失败，请重试。";
}

async function loadProjects(reset = true) {
  const generation = ++listGeneration;
  const cursor = reset ? null : nextCursor.value;
  if (reset) {
    projects.value = [];
    nextCursor.value = null;
  }
  loading.value = true;
  accessError.value = null;
  accessCode.value = null;
  try {
    const page = await searchCrossProjects(appliedSearch.value, cursor);
    if (generation !== listGeneration) return;
    const existing = new Set(projects.value.map((p) => p.projectId));
    const additional = page.projects.filter((p) => !existing.has(p.projectId));
    projects.value = reset ? page.projects : [...projects.value, ...additional];
    nextCursor.value = page.nextCursor;
  } catch (error) {
    if (generation !== listGeneration) return;
    accessError.value = errorText(error);
    accessCode.value =
      error && typeof error === "object" && "code" in error
        ? String(error.code)
        : null;
  } finally {
    if (generation === listGeneration) loading.value = false;
  }
}

function applySearch() {
  appliedSearch.value = searchText.value.trim();
  void loadProjects(true);
}

function toggleSelection(id: string) {
  if (includeAll.value) {
    includeAll.value = false;
    selectedIds.value = [id];
    return;
  }
  selectedIds.value = selectedIds.value.includes(id)
    ? selectedIds.value.filter((candidate) => candidate !== id)
    : [...selectedIds.value, id];
}

function resetSelection() {
  // Preserve the checkbox's new value: unchecked means an explicit selection.
  selectedIds.value = [];
}

function buildWindow() {
  const from = Date.parse(fromDate.value + "T00:00:00Z");
  const endExclusive = Date.parse(toDate.value + "T00:00:00Z") + DAY_MS;
  const to = Math.min(endExclusive, Date.now());
  if (
    !Number.isFinite(from) ||
    !Number.isFinite(to) ||
    from >= to ||
    to - from > 180 * DAY_MS
  )
    throw new Error("请选择不超过 180 天且起点早于终点的 UTC 日期范围。");
  return { from: new Date(from).toISOString(), to: new Date(to).toISOString() };
}

async function loadAnalytics() {
  const generation = ++analyticsGeneration;
  analyzing.value = true;
  analyticsError.value = null;
  analytics.value = null;
  try {
    const window = buildWindow();
    const value = await loadCrossProjectAnalytics({
      ...window,
      ...(includeAll.value ? {} : { projectIds: selectedIds.value }),
    });
    if (generation === analyticsGeneration) analytics.value = value;
  } catch (error) {
    if (generation === analyticsGeneration)
      analyticsError.value = errorText(error);
  } finally {
    if (generation === analyticsGeneration) analyzing.value = false;
  }
}

onMounted(() => void loadProjects());
onActivated(() => void loadProjects());
</script>

<template>
  <main class="xiaozhuwork-page cross-project">
    <header class="page-heading">
      <div>
        <h1>跨项目工作台</h1>
        <p>账号 Pro 专属：跨项目搜索、状态总览与 UTC 任务趋势。</p>
      </div>
      <RouterLink to="/projects">返回我的项目</RouterLink>
    </header>

    <div v-if="planned" class="notice" role="status">
      此能力正在准备中，尚未正式发布。原有「我的项目」仍可正常使用。
    </div>
    <div v-else-if="noPro" class="notice" role="status">
      当前账号不具备有效 Account Pro。项目 Pro 身份不能替代账号 Pro 权益。
    </div>
    <div v-else-if="accessError" class="notice" role="alert">
      {{ accessError }}
      <button type="button" @click="loadProjects()">重试</button>
    </div>
    <template v-else>
      <section class="panel">
        <h2>项目搜索</h2>
        <form class="search-row" @submit.prevent="applySearch">
          <label class="search-field">
            项目或课程名称
            <input
              v-model="searchText"
              maxlength="100"
              type="search"
              placeholder="搜索项目名称、课程名称"
            />
          </label>
          <button type="submit" :disabled="loading">搜索</button>
        </form>
        <p class="helper">
          仅返回当前仍有访问权限的项目；搜索为服务端匹配，结果按项目 ID
          稳定分页。
        </p>
        <div class="selection-options">
          <label
            ><input
              v-model="includeAll"
              type="checkbox"
              @change="resetSelection"
            />
            汇总全部可访问项目（最多 100 个）</label
          >
          <span v-if="!includeAll">已选择 {{ selectedIds.length }} 项</span>
        </div>
        <div v-if="loading && !projects.length" role="status">
          正在查询项目…
        </div>
        <CrossProjectList
          :projects="projects"
          :selected-ids="selectedIds"
          :include-all="includeAll"
          :loading="loading"
          :has-next="!!nextCursor"
          @toggle="toggleSelection"
          @more="loadProjects(false)"
        />
      </section>

      <section class="panel">
        <h2>跨项目统计</h2>
        <div class="filter-row">
          <label>开始日期（UTC）<input v-model="fromDate" type="date" /></label>
          <label>结束日期（UTC）<input v-model="toDate" type="date" /></label>
          <button
            type="button"
            :disabled="analyzing || loading"
            @click="loadAnalytics"
          >
            {{ analyzing ? "正在汇总…" : "生成统计" }}
          </button>
        </div>
        <p class="helper">
          默认最近 30 天，时间窗口为 [from, to)，当天结束于当前 UTC
          时刻。统计会重新核验账号权益和项目成员权限。
        </p>
        <p v-if="analyticsError" class="notice" role="alert">
          {{ analyticsError }}
        </p>
        <div v-if="analyzing" role="status">正在加载统计…</div>
        <template v-if="analytics">
          <CrossProjectStatistics :data="analytics" />
          <CrossProjectTrend :trends="analytics.trends" />
        </template>
        <p v-else-if="!analyzing" class="helper">选择项目及日期后生成统计。</p>
      </section>
    </template>
  </main>
</template>

<style scoped>
.cross-project {
  display: grid;
  gap: 20px;
}
.cross-project .page-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  flex-wrap: wrap;
}
.cross-project h1 {
  margin: 0;
}
.cross-project h2 {
  margin: 0 0 12px;
  font-size: 20px;
}
.panel {
  min-width: 0;
  display: grid;
  gap: var(--space-md);
  padding: var(--space-lg) 0;
  border-top: 1px solid var(--tu-border);
}
.search-row,
.filter-row {
  display: flex;
  align-items: end;
  flex-wrap: wrap;
  gap: 14px;
}
.search-field {
  flex: 1;
  min-width: 200px;
}
.search-field,
.filter-row label {
  display: grid;
  gap: 7px;
  font-size: 14px;
  font-weight: 600;
}
input[type="search"],
input[type="date"] {
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  min-height: 42px;
  padding: 9px 12px;
  background: var(--tu-subtle-surface);
  color: var(--tu-ink);
  max-width: 100%;
}
button[type="submit"],
.filter-row button {
  border: 0;
  border-radius: var(--radius-control);
  min-height: 42px;
  padding: 10px 20px;
  color: var(--tu-action-contrast);
  background: var(--tu-action);
  cursor: pointer;
}
button:disabled {
  opacity: 0.6;
  cursor: default;
}
.helper {
  margin: 0;
  color: var(--tu-muted);
  font-size: 13px;
  line-height: 1.6;
}
.selection-options {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  align-items: center;
  font-size: 14px;
}
.selection-options label {
  display: flex;
  align-items: center;
  gap: 8px;
}
.notice {
  background: var(--tu-warning-surface);
  border-left: 2px solid var(--tu-border);
  padding: var(--space-md);
  color: var(--tu-warning-ink);
}
.notice button {
  background: transparent;
  color: inherit;
  border: 1px solid;
  border-radius: var(--radius-control);
  padding: 5px 12px;
  margin-left: 10px;
  cursor: pointer;
}
@media (max-width: 600px) {
  .panel {
    padding: var(--space-md) 0;
  }
  .search-row > * {
    width: 100%;
  }
  .filter-row label {
    flex: 1 1 140px;
  }
}
</style>
