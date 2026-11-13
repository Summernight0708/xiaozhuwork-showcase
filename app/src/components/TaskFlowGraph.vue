<script setup lang="ts">
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from "vue";

import { displayStatusLabel } from "@/domain/presentation-labels";

import {
  bestReadableZoom,
  buildTaskGraph,
  directRelationIds,
  foldedHistoryCount,
  scopedTaskIds,
  semanticZoomMetrics,
  type TaskGraphDependency,
  type TaskGraphNode,
  type TaskGraphScope,
  type TaskGraphTask,
} from "@/domain/task-dependency-graph";

const props = withDefaults(
  defineProps<{
    tasks: TaskGraphTask[];
    dependencies: TaskGraphDependency[];
    memberName?: (userId: string | null | undefined) => string;
    currentUserId?: string | null;
    collaboratorCounts?: Record<string, number>;
    newArtifactTaskIds?: string[];
    initialState?: Partial<{
      zoom: number;
      panX: number;
      panY: number;
      scope: TaskGraphScope;
      search: string;
      focusTaskId: string | null;
      historyExpanded: boolean;
    }>;
  }>(),
  {
    memberName: (userId: string | null | undefined) =>
      userId ? "成员" : "未分配",
    currentUserId: null,
    collaboratorCounts: () => ({}),
    newArtifactTaskIds: () => [],
    initialState: () => ({}),
  },
);

const emit = defineEmits<{
  (event: "open-task", taskId: string): void;
  (
    event: "state-change",
    state: {
      zoom: number;
      panX: number;
      panY: number;
      scope: TaskGraphScope;
      search: string;
      focusTaskId: string | null;
      historyExpanded: boolean;
    },
  ): void;
}>();

const graphRoot = ref<HTMLElement | null>(null);
const zoom = ref(props.initialState.zoom ?? 100);
const panX = ref(props.initialState.panX ?? 18);
const panY = ref(props.initialState.panY ?? 18);
const scope = ref<TaskGraphScope>(props.initialState.scope ?? "workflow");
const search = ref(props.initialState.search ?? "");
const focusTaskId = ref<string | null>(props.initialState.focusTaskId ?? null);
const historyExpanded = ref(props.initialState.historyExpanded ?? false);
const viewportWidth = ref(960);
const viewportHeight = ref(480);
const dragging = ref(false);
const dragMoved = ref(false);
const dragStart = ref({ x: 0, y: 0, panX: 0, panY: 0 });
const pointers = new Map<number, { x: number; y: number }>();
let pinchDistance = 0;
let resizeObserver: ResizeObserver | undefined;

const metrics = computed(() => semanticZoomMetrics(zoom.value));
const newArtifactSet = computed(() => new Set(props.newArtifactTaskIds));

const scopeIds = computed(() => {
  if (scope.value === "workflow" && historyExpanded.value) {
    return new Set(props.tasks.map((task) => task.id));
  }
  return scopedTaskIds(props.tasks, props.dependencies, scope.value);
});

const historyCount = computed(() =>
  scope.value === "workflow"
    ? foldedHistoryCount(props.tasks, scopeIds.value)
    : 0,
);

const visibleIds = computed(() => {
  if (!focusTaskId.value) return scopeIds.value;
  return directRelationIds(focusTaskId.value, props.dependencies);
});

const visibleTasks = computed(() =>
  props.tasks.filter((task) => visibleIds.value.has(task.id)),
);
const visibleDependencies = computed(() =>
  props.dependencies.filter(
    (dependency) =>
      visibleIds.value.has(dependency.upstream_task_id) &&
      visibleIds.value.has(dependency.downstream_task_id),
  ),
);
const graph = computed(() =>
  buildTaskGraph(visibleTasks.value, visibleDependencies.value),
);

const compactStages = computed(() => {
  const byRank = new Map<number, TaskGraphNode[]>();
  for (const node of graph.value.nodes) {
    const stage = byRank.get(node.rank) ?? [];
    stage.push(node);
    byRank.set(node.rank, stage);
  }
  return [...byRank.entries()]
    .sort(([left], [right]) => left - right)
    .map(([rank, nodes]) => ({
      rank,
      nodes: [...nodes].sort((left, right) => left.lane - right.lane),
    }));
});

const compactRelations = computed(() => {
  const tasksById = new Map(
    graph.value.nodes.map((node) => [node.task.id, node.task]),
  );
  const relations = new Map<
    string,
    { upstream: TaskGraphTask[]; downstream: TaskGraphTask[] }
  >();

  for (const node of graph.value.nodes) {
    relations.set(node.task.id, { upstream: [], downstream: [] });
  }
  for (const edge of graph.value.edges) {
    const upstreamTask = tasksById.get(edge.upstreamTaskId);
    const downstreamTask = tasksById.get(edge.downstreamTaskId);
    if (!upstreamTask || !downstreamTask) continue;
    relations.get(edge.downstreamTaskId)?.upstream.push(upstreamTask);
    relations.get(edge.upstreamTaskId)?.downstream.push(downstreamTask);
  }
  return relations;
});

function compactRelationLabel(taskId: string) {
  const relation = compactRelations.value.get(taskId);
  if (!relation) return "无依赖";

  const formatSide = (label: "上游" | "下游", tasks: TaskGraphTask[]) => {
    if (tasks.length === 0) return label === "上游" ? "起点" : "终点";
    const visible = tasks.slice(0, 2).map((task) => task.title);
    return `${label} ${visible.join("、")}${
      tasks.length > 2 ? ` 等 ${tasks.length} 项` : ""
    }`;
  };

  return `${formatSide("上游", relation.upstream)} · ${formatSide(
    "下游",
    relation.downstream,
  )}`;
}

const maxRank = computed(() =>
  Math.max(0, ...graph.value.nodes.map((node) => node.rank)),
);
const maxLane = computed(() =>
  Math.max(0, ...graph.value.nodes.map((node) => node.lane)),
);
const naturalWidth = computed(
  () =>
    80 +
    (maxRank.value + 1) * metrics.value.nodeWidth +
    maxRank.value * metrics.value.columnGap,
);
const naturalHeight = computed(
  () =>
    80 +
    (maxLane.value + 1) * metrics.value.nodeHeight +
    maxLane.value * metrics.value.rowGap,
);

function nodePosition(rank: number, lane: number) {
  return {
    x: 40 + rank * (metrics.value.nodeWidth + metrics.value.columnGap),
    y: 40 + lane * (metrics.value.nodeHeight + metrics.value.rowGap),
  };
}

function edgeKey(edge: { upstreamTaskId: string; downstreamTaskId: string }) {
  return `${edge.upstreamTaskId}:${edge.downstreamTaskId}`;
}

const pathByEdge = computed(() => {
  const byId = new Map(graph.value.nodes.map((node) => [node.task.id, node]));
  const paths = new Map<string, string>();
  for (const edge of graph.value.edges) {
    const upstream = byId.get(edge.upstreamTaskId);
    const downstream = byId.get(edge.downstreamTaskId);
    if (!upstream || !downstream) continue;
    const start = nodePosition(upstream.rank, upstream.lane);
    const end = nodePosition(downstream.rank, downstream.lane);
    const x1 = start.x + metrics.value.nodeWidth;
    const y1 = start.y + metrics.value.nodeHeight / 2;
    const x2 = end.x;
    const y2 = end.y + metrics.value.nodeHeight / 2;
    const mid = (x1 + x2) / 2;
    paths.set(
      edgeKey(edge),
      `M ${x1} ${y1} C ${mid} ${y1}, ${mid} ${y2}, ${x2} ${y2}`,
    );
  }
  return paths;
});

const searchTerm = computed(() => search.value.trim().toLocaleLowerCase());
const matchingTaskIds = computed(() => {
  if (!searchTerm.value) return new Set<string>();
  return new Set(
    props.tasks
      .filter((task) =>
        task.title.toLocaleLowerCase().includes(searchTerm.value),
      )
      .map((task) => task.id),
  );
});
const searchResults = computed(() =>
  searchTerm.value
    ? props.tasks
        .filter((task) => matchingTaskIds.value.has(task.id))
        .slice(0, 6)
    : [],
);

function taskStatus(task: TaskGraphTask, waitingUpstream: boolean) {
  if (
    task.status !== "completed" &&
    task.status !== "canceled" &&
    waitingUpstream
  ) {
    return "等待上游";
  }
  if (
    task.assignment_state === "pending_acceptance" &&
    task.status !== "completed"
  ) {
    return "待接受";
  }
  return displayStatusLabel(task.status);
}

function ownerLabel(task: TaskGraphTask) {
  if (!task.assignee_id) return "未分配";
  if (task.assignee_id === props.currentUserId) return "我";
  return props.memberName(task.assignee_id);
}

function accessibleLabel(
  task: TaskGraphTask,
  waitingUpstream: boolean,
): string {
  const parts = [
    task.title,
    taskStatus(task, waitingUpstream),
    `主负责人：${ownerLabel(task)}`,
  ];
  const collaborators = props.collaboratorCounts[task.id] ?? 0;
  if (collaborators > 0) parts.push(`${collaborators} 名协作者`);
  if (newArtifactSet.value.has(task.id)) parts.push("有新成果");
  return parts.join("；");
}

function stateSnapshot() {
  return {
    zoom: zoom.value,
    panX: Math.round(panX.value),
    panY: Math.round(panY.value),
    scope: scope.value,
    search: search.value,
    focusTaskId: focusTaskId.value,
    historyExpanded: historyExpanded.value,
  };
}

watch(
  [zoom, panX, panY, scope, search, focusTaskId, historyExpanded],
  () => emit("state-change", stateSnapshot()),
  { flush: "post" },
);

function updateZoom(next: number, originX?: number, originY?: number) {
  const oldMetrics = metrics.value;
  const bounded = Math.min(160, Math.max(45, Math.round(next)));
  if (bounded === zoom.value) return;
  const nextMetrics = semanticZoomMetrics(bounded);
  const ratio = nextMetrics.nodeWidth / oldMetrics.nodeWidth;
  const x = originX ?? viewportWidth.value / 2;
  const y = originY ?? viewportHeight.value / 2;
  panX.value = x - (x - panX.value) * ratio;
  panY.value = y - (y - panY.value) * ratio;
  zoom.value = bounded;
}

function bestView() {
  zoom.value = bestReadableZoom(props.tasks.length, viewportWidth.value);
  panX.value = 18;
  panY.value = 18;
}

function onWheel(event: WheelEvent) {
  event.preventDefault();
  updateZoom(
    zoom.value + (event.deltaY > 0 ? -5 : 5),
    event.offsetX,
    event.offsetY,
  );
}

function onPointerDown(event: PointerEvent) {
  const target = event.target as Element | null;
  if (target?.closest("button, input, select, .task-flow__minimap")) return;
  pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
  if (pointers.size === 2) {
    const [first, second] = [...pointers.values()];
    if (first && second) {
      pinchDistance = Math.hypot(second.x - first.x, second.y - first.y);
    }
    return;
  }
  dragging.value = true;
  dragMoved.value = false;
  dragStart.value = {
    x: event.clientX,
    y: event.clientY,
    panX: panX.value,
    panY: panY.value,
  };
  (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
}

function onPointerMove(event: PointerEvent) {
  if (pointers.has(event.pointerId)) {
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
  }
  if (pointers.size >= 2) {
    const [first, second] = [...pointers.values()];
    if (!first || !second) return;
    const distance = Math.hypot(second.x - first.x, second.y - first.y);
    if (pinchDistance > 0) {
      updateZoom(zoom.value * (distance / pinchDistance));
    }
    pinchDistance = distance;
    return;
  }
  if (!dragging.value) return;
  const dx = event.clientX - dragStart.value.x;
  const dy = event.clientY - dragStart.value.y;
  if (Math.abs(dx) + Math.abs(dy) > 4) dragMoved.value = true;
  panX.value = dragStart.value.panX + dx;
  panY.value = dragStart.value.panY + dy;
}

function onPointerUp(event: PointerEvent) {
  pointers.delete(event.pointerId);
  if (pointers.size < 2) pinchDistance = 0;
  dragging.value = false;
}

async function centerTask(taskId: string) {
  const node = graph.value.nodes.find((item) => item.task.id === taskId);
  if (!node) return;
  const position = nodePosition(node.rank, node.lane);
  panX.value =
    viewportWidth.value / 2 - position.x - metrics.value.nodeWidth / 2;
  panY.value =
    viewportHeight.value / 2 - position.y - metrics.value.nodeHeight / 2;
  await nextTick();
}

async function locateSearchResult(taskId: string) {
  if (!scopeIds.value.has(taskId)) scope.value = "all";
  focusTaskId.value = null;
  await nextTick();
  await centerTask(taskId);
}

async function activateTask(taskId: string) {
  if (dragMoved.value) {
    dragMoved.value = false;
    return;
  }
  focusTaskId.value = taskId;
  await nextTick();
  await centerTask(taskId);
  emit("state-change", stateSnapshot());
  emit("open-task", taskId);
}

function clearFocus() {
  focusTaskId.value = null;
}

function updateViewport() {
  viewportWidth.value =
    graphRoot.value?.clientWidth || globalThis.innerWidth || 960;
  viewportHeight.value = graphRoot.value?.clientHeight || 480;
}

const minimap = computed(() => {
  const width = 156;
  const height = 96;
  const scale = Math.min(
    width / Math.max(naturalWidth.value, 1),
    height / Math.max(naturalHeight.value, 1),
  );
  const contentWidth = naturalWidth.value * scale;
  const contentHeight = naturalHeight.value * scale;
  const viewport = {
    x: Math.max(0, Math.min(contentWidth, -panX.value * scale)),
    y: Math.max(0, Math.min(contentHeight, -panY.value * scale)),
    width: Math.min(contentWidth, viewportWidth.value * scale),
    height: Math.min(contentHeight, viewportHeight.value * scale),
  };
  return { width, height, scale, contentWidth, contentHeight, viewport };
});

onMounted(() => {
  updateViewport();
  globalThis.addEventListener("resize", updateViewport);
  if (typeof globalThis.ResizeObserver !== "function") return;
  resizeObserver = new globalThis.ResizeObserver(updateViewport);
  if (graphRoot.value) resizeObserver.observe(graphRoot.value);
});

onBeforeUnmount(() => {
  globalThis.removeEventListener("resize", updateViewport);
  resizeObserver?.disconnect();
});

defineExpose({ bestView, centerTask, stateSnapshot });
</script>

<template>
  <section
    class="task-flow"
    :data-zoom-tier="metrics.tier"
    :data-zoom="metrics.zoom"
    aria-label="任务依赖流程图"
  >
    <header class="task-flow__toolbar">
      <div class="task-flow__scope">
        <label>
          <span class="sr-only">流程图范围</span>
          <select v-model="scope" aria-label="流程图范围">
            <option value="workflow">当前工作流</option>
            <option value="all">全部任务</option>
            <option value="open">未完成</option>
            <option value="blocked">阻塞 / 等待</option>
          </select>
        </label>
        <button
          v-if="historyCount > 0 && !historyExpanded"
          type="button"
          class="history-toggle"
          @click="historyExpanded = true"
        >
          更早已完成 · {{ historyCount }}
        </button>
        <button
          v-else-if="historyExpanded && scope === 'workflow'"
          type="button"
          class="history-toggle"
          @click="historyExpanded = false"
        >
          收起历史
        </button>
      </div>

      <div class="task-flow__search">
        <label>
          <span class="sr-only">搜索任务</span>
          <input
            v-model="search"
            type="search"
            placeholder="搜索任务"
            aria-label="搜索任务"
            @keydown.enter.prevent="
              searchResults[0] && locateSearchResult(searchResults[0].id)
            "
          />
        </label>
        <div
          v-if="searchTerm && searchResults.length > 0"
          class="search-results"
          aria-label="任务搜索结果"
        >
          <button
            v-for="task in searchResults"
            :key="task.id"
            type="button"
            @click="locateSearchResult(task.id)"
          >
            {{ task.title }}
          </button>
        </div>
      </div>

      <div class="task-flow__zoom" aria-label="流程图缩放">
        <button
          type="button"
          aria-label="缩小流程图"
          @click="updateZoom(zoom - 10)"
        >
          −
        </button>
        <button type="button" class="best-view" @click="bestView">
          最佳视图
        </button>
        <button
          type="button"
          aria-label="放大流程图"
          @click="updateZoom(zoom + 10)"
        >
          +
        </button>
        <input
          :value="zoom"
          type="range"
          min="45"
          max="160"
          step="1"
          aria-label="缩放比例"
          @input="updateZoom(Number(($event.target as HTMLInputElement).value))"
        />
        <output>{{ zoom }}%</output>
      </div>
    </header>

    <div v-if="focusTaskId" class="focus-banner">
      <span>
        聚焦：{{
          tasks.find((task) => task.id === focusTaskId)?.title || "当前任务"
        }}
        · 上/下游关系 {{ Math.max(0, visibleIds.size - 1) }} 个
      </span>
      <button type="button" @click="clearFocus">返回全局图</button>
    </div>

    <p v-if="graph.hasCycle" class="task-flow__warning" role="status">
      任务关系存在异常循环，已使用安全回退布局展示。
    </p>

    <div v-if="tasks.length === 0" class="task-flow__empty">
      <strong>还没有任务</strong>
      <p>创建任务后，这里会显示上下游关系。</p>
      <slot name="empty-action" />
    </div>

    <div v-if="tasks.length > 0" class="task-flow__compact">
      <section
        v-for="stage in compactStages"
        :key="stage.rank"
        class="task-flow__compact-stage"
        :aria-label="`第 ${stage.rank + 1} 阶段`"
      >
        <header>
          <strong>阶段 {{ stage.rank + 1 }}</strong>
          <span>{{ stage.nodes.length }} 项</span>
        </header>
        <button
          v-for="node in stage.nodes"
          :key="node.task.id"
          type="button"
          class="task-flow__compact-node"
          :class="[
            `status-${node.task.status}`,
            { 'is-waiting': node.waitingUpstream },
          ]"
          :data-compact-task-id="node.task.id"
          :aria-label="accessibleLabel(node.task, node.waitingUpstream)"
          @click="activateTask(node.task.id)"
        >
          <span class="task-flow__compact-title">{{ node.task.title }}</span>
          <span class="task-flow__compact-meta">
            {{ taskStatus(node.task, node.waitingUpstream) }} · 主负责
            {{ ownerLabel(node.task) }}
          </span>
          <span class="task-flow__compact-relations">
            {{ compactRelationLabel(node.task.id) }}
          </span>
        </button>
      </section>
    </div>

    <div
      v-if="tasks.length > 0"
      ref="graphRoot"
      class="task-flow__canvas"
      :class="{ 'is-dragging': dragging }"
      :data-pan-x="Math.round(panX)"
      :data-pan-y="Math.round(panY)"
      @wheel="onWheel"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerUp"
      @pointercancel="onPointerUp"
    >
      <div
        class="task-flow__world"
        :style="{
          width: naturalWidth + 'px',
          height: naturalHeight + 'px',
          transform: `translate(${panX}px, ${panY}px)`,
        }"
      >
        <svg
          class="task-flow__edges"
          :viewBox="`0 0 ${naturalWidth} ${naturalHeight}`"
          aria-hidden="true"
        >
          <path
            v-for="edge in graph.edges"
            :key="edgeKey(edge)"
            :d="pathByEdge.get(edgeKey(edge)) || ''"
          />
        </svg>

        <button
          v-for="node in graph.nodes"
          :key="node.task.id"
          type="button"
          class="task-flow__node"
          :class="[
            `tier-${metrics.tier}`,
            `status-${node.task.status}`,
            {
              'is-waiting': node.waitingUpstream,
              'is-search-match': matchingTaskIds.has(node.task.id),
              'is-search-dimmed':
                !!searchTerm && !matchingTaskIds.has(node.task.id),
              'has-new-artifact': newArtifactSet.has(node.task.id),
            },
          ]"
          :style="{
            left: nodePosition(node.rank, node.lane).x + 'px',
            top: nodePosition(node.rank, node.lane).y + 'px',
            width: metrics.nodeWidth + 'px',
            height: metrics.nodeHeight + 'px',
            padding: metrics.padding + 'px',
            '--node-title-size': metrics.titleFontSize + 'px',
            '--node-meta-size': metrics.metaFontSize + 'px',
          }"
          :aria-label="accessibleLabel(node.task, node.waitingUpstream)"
          :data-task-id="node.task.id"
          @click.stop="activateTask(node.task.id)"
        >
          <span class="task-flow__node-title">{{ node.task.title }}</span>

          <span v-if="metrics.tier === 1" class="task-flow__node-owner">
            <span>主负责 {{ ownerLabel(node.task) }}</span>
            <span v-if="(collaboratorCounts[node.task.id] || 0) > 0">
              +{{ collaboratorCounts[node.task.id] }} 协作者
            </span>
          </span>

          <span v-if="metrics.tier !== 3" class="task-flow__node-status">
            {{ taskStatus(node.task, node.waitingUpstream) }}
          </span>

          <span
            v-if="metrics.tier === 1 && newArtifactSet.has(node.task.id)"
            class="task-flow__artifact"
          >
            新成果
          </span>
        </button>
      </div>

      <div class="task-flow__minimap" aria-label="任务图缩略图">
        <svg :viewBox="`0 0 ${minimap.width} ${minimap.height}`">
          <circle
            v-for="node in graph.nodes"
            :key="node.task.id"
            :cx="
              (nodePosition(node.rank, node.lane).x + metrics.nodeWidth / 2) *
              minimap.scale
            "
            :cy="
              (nodePosition(node.rank, node.lane).y + metrics.nodeHeight / 2) *
              minimap.scale
            "
            r="2.4"
          />
          <rect
            class="minimap-viewport"
            :x="minimap.viewport.x"
            :y="minimap.viewport.y"
            :width="Math.max(8, minimap.viewport.width)"
            :height="Math.max(8, minimap.viewport.height)"
          />
        </svg>
      </div>
    </div>
  </section>
</template>

<style scoped>
.task-flow {
  container-name: task-flow;
  container-type: inline-size;
  overflow: hidden;
  border: 1px solid var(--tu-border);
  border-radius: 14px;
  background: var(--tu-surface);
}

.task-flow__toolbar {
  min-height: 58px;
  display: grid;
  grid-template-columns: minmax(170px, auto) minmax(180px, 1fr) auto;
  align-items: center;
  gap: 12px;
  padding: 9px 12px;
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
}

.task-flow__scope,
.task-flow__zoom {
  display: flex;
  align-items: center;
  gap: 6px;
}

.task-flow select,
.task-flow input[type="search"] {
  min-height: 38px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}

.task-flow select {
  padding: 0 28px 0 10px;
  font-size: 13px;
}

.history-toggle,
.task-flow__zoom button,
.focus-banner button {
  min-height: 36px;
  padding: 0 9px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: transparent;
  color: var(--tu-muted);
  cursor: pointer;
  font-size: 12px;
}

.task-flow__search {
  position: relative;
  width: min(360px, 100%);
  justify-self: center;
}

.task-flow__search label,
.task-flow__search input {
  width: 100%;
}

.task-flow__search input {
  padding: 0 12px;
}

.search-results {
  position: absolute;
  z-index: 12;
  top: 43px;
  right: 0;
  left: 0;
  display: grid;
  padding: 6px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-surface);
  box-shadow: var(--tu-shadow);
}

.search-results button {
  min-height: 38px;
  padding: 7px 9px;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}

.search-results button:hover {
  background: var(--tu-bg);
}

.task-flow__zoom {
  justify-self: end;
}

.task-flow__zoom > button:first-child,
.task-flow__zoom > button:nth-child(3) {
  width: 34px;
  padding: 0;
  font-size: 18px;
}

.task-flow__zoom input[type="range"] {
  width: 84px;
  accent-color: var(--tu-ink);
}

.task-flow__zoom output {
  width: 42px;
  color: var(--tu-muted);
  font-size: 12px;
  text-align: right;
}

.focus-banner {
  min-height: 42px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 7px 13px;
  border-bottom: 1px solid var(--tu-border);
  background: #f5f1ea;
  color: var(--tu-ink);
  font-size: 13px;
}

.task-flow__warning {
  margin: 0;
  padding: 9px 13px;
  border-bottom: 1px solid #f1d095;
  background: #fff8e7;
  color: #7b4d08;
  font-size: 13px;
}

.task-flow__empty {
  min-height: 280px;
  display: grid;
  place-content: center;
  text-align: center;
}

.task-flow__empty p {
  margin: 8px 0 0;
  color: var(--tu-muted);
}

.task-flow__compact {
  display: none;
}

.task-flow__canvas {
  position: relative;
  height: clamp(380px, 58vh, 660px);
  overflow: hidden;
  touch-action: none;
  cursor: grab;
  background:
    radial-gradient(circle at 1px 1px, rgb(80 72 62 / 0.09) 1px, transparent 0)
      0 0 / 22px 22px,
    #faf8f4;
}

.task-flow__canvas.is-dragging {
  cursor: grabbing;
}

.task-flow__world {
  position: absolute;
  top: 0;
  left: 0;
  transform-origin: 0 0;
  transition: none;
}

.task-flow__edges {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  overflow: visible;
  pointer-events: none;
}

.task-flow__edges path {
  fill: none;
  stroke: #b8b0a5;
  stroke-width: 1.5;
  vector-effect: non-scaling-stroke;
}

.task-flow__node {
  position: absolute;
  display: grid;
  align-content: center;
  gap: 7px;
  overflow: hidden;
  border: 1px solid #d7d1c7;
  border-radius: 11px;
  background: #fffdf9;
  color: #282521;
  text-align: left;
  cursor: pointer;
  box-shadow: 0 3px 10px rgb(55 44 30 / 0.035);
  transition:
    opacity 120ms ease,
    border-color 120ms ease,
    box-shadow 120ms ease;
}

.task-flow__node:hover,
.task-flow__node:focus-visible {
  border-color: #8d857a;
  box-shadow: 0 5px 16px rgb(55 44 30 / 0.08);
}

.task-flow__node-title {
  min-width: 0;
  overflow: hidden;
  color: inherit;
  font-size: var(--node-title-size);
  font-weight: 720;
  line-height: 1.28;
  text-overflow: ellipsis;
}

.tier-1 .task-flow__node-title,
.tier-2 .task-flow__node-title {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.tier-3 .task-flow__node-title {
  white-space: nowrap;
}

.task-flow__node-owner {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 8px;
  min-width: 0;
  overflow: hidden;
  color: #766f65;
  font-size: var(--node-meta-size);
  line-height: 1.25;
  white-space: nowrap;
}

.task-flow__node-status {
  width: fit-content;
  max-width: 100%;
  overflow: hidden;
  padding: 3px 7px;
  border-radius: 999px;
  background: #efebe4;
  color: #5e574f;
  font-size: var(--node-meta-size);
  line-height: 1.2;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tier-2 {
  grid-template-rows: minmax(0, 1fr) auto;
  gap: 5px;
}

.tier-2 .task-flow__node-status {
  padding: 0;
  border-radius: 0;
  background: transparent;
  font-weight: 650;
}

.tier-3 {
  min-height: 50px;
  min-width: 156px;
}

.task-flow__artifact {
  position: absolute;
  top: 8px;
  right: 8px;
  padding: 2px 5px;
  border-radius: 999px;
  background: #f4ead1;
  color: #795d20;
  font-size: max(10px, calc(var(--node-meta-size) - 1px));
  font-weight: 700;
}

.task-flow__node.is-waiting,
.task-flow__node.status-blocked {
  border-color: #d6b9a4;
}

.task-flow__node.status-completed {
  background: #fbfaf7;
  color: #706a62;
}

.task-flow__node.status-awaiting_review {
  border-color: #d6c38d;
}

.task-flow__node.is-search-match {
  border-color: #4e6678;
  box-shadow: 0 0 0 2px rgb(78 102 120 / 0.14);
}

.task-flow__node.is-search-dimmed {
  opacity: 0.28;
}

.task-flow__minimap {
  position: absolute;
  right: 13px;
  bottom: 13px;
  width: 166px;
  height: 106px;
  padding: 5px;
  border: 1px solid rgb(151 142 130 / 0.55);
  border-radius: 9px;
  background: rgb(255 253 249 / 0.9);
  box-shadow: 0 5px 16px rgb(55 44 30 / 0.06);
  pointer-events: none;
}

.task-flow__minimap svg {
  width: 156px;
  height: 96px;
}

.task-flow__minimap circle {
  fill: #716a61;
}

.task-flow__minimap .minimap-viewport {
  fill: rgb(78 102 120 / 0.07);
  stroke: #4e6678;
  stroke-width: 1;
}

html[data-theme="dark"] .task-flow__canvas {
  background:
    radial-gradient(
        circle at 1px 1px,
        rgb(230 220 205 / 0.08) 1px,
        transparent 0
      )
      0 0 / 22px 22px,
    #181715;
}

html[data-theme="dark"] .task-flow__node {
  border-color: #403c35;
  background: #211f1c;
  color: #f1ece5;
}

html[data-theme="dark"] .task-flow__node-owner {
  color: #aaa398;
}

html[data-theme="dark"] .task-flow__node-status,
html[data-theme="dark"] .focus-banner {
  background: #2c2924;
  color: #d7d0c7;
}

html[data-theme="dark"] .task-flow__minimap {
  background: rgb(33 31 28 / 0.92);
}

@container task-flow (max-width: 720px) {
  .task-flow__toolbar {
    grid-template-columns: minmax(0, 1fr) auto;
  }

  .task-flow__scope {
    min-width: 0;
    flex-wrap: wrap;
  }

  .task-flow__search {
    grid-column: 1 / -1;
    grid-row: 2;
    width: 100%;
    order: 3;
  }

  .task-flow__zoom input[type="range"],
  .task-flow__zoom .best-view {
    display: none;
  }
}

@media (max-width: 767px) {
  .task-flow__zoom {
    display: none;
  }

  .task-flow__canvas,
  .task-flow__minimap {
    display: none;
  }

  .task-flow__compact {
    display: grid;
    gap: 12px;
    padding: 12px;
    background: #faf8f4;
  }

  .task-flow__compact-stage {
    min-width: 0;
    display: grid;
    gap: 8px;
    padding-left: 12px;
    border-left: 2px solid var(--tu-border);
  }

  .task-flow__compact-stage > header {
    min-width: 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    color: var(--tu-muted);
    font-size: 12px;
  }

  .task-flow__compact-stage > header strong {
    color: var(--tu-ink);
    font-size: 13px;
  }

  .task-flow__compact-node {
    min-width: 0;
    width: 100%;
    display: grid;
    gap: 5px;
    padding: 11px 12px;
    border: 1px solid #d7d1c7;
    border-radius: 10px;
    background: var(--tu-surface);
    color: var(--tu-ink);
    text-align: left;
    cursor: pointer;
  }

  .task-flow__compact-node.is-waiting,
  .task-flow__compact-node.status-blocked {
    border-color: #d6b9a4;
  }

  .task-flow__compact-node:hover,
  .task-flow__compact-node:focus-visible {
    border-color: #8d857a;
  }

  .task-flow__compact-title,
  .task-flow__compact-meta,
  .task-flow__compact-relations {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .task-flow__compact-title {
    display: -webkit-box;
    overflow: hidden;
    font-size: 14px;
    font-weight: 720;
    line-height: 1.35;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
  }

  .task-flow__compact-meta,
  .task-flow__compact-relations {
    color: var(--tu-muted);
    font-size: 11px;
    line-height: 1.45;
  }

  .task-flow__compact-relations {
    display: -webkit-box;
    overflow: hidden;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
  }

  html[data-theme="dark"] .task-flow__compact {
    background: #181715;
  }

  html[data-theme="dark"] .task-flow__compact-node {
    border-color: #403c35;
    background: #211f1c;
  }
}
</style>
