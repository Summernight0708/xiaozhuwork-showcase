export interface TaskGraphTask {
  id: string;
  title: string;
  status: string;
  assignee_id?: string | null;
  assignment_state?: string;
  deadline_at?: string;
}

export interface TaskGraphDependency {
  upstream_task_id: string;
  downstream_task_id: string;
}

export interface TaskGraphEdge {
  upstreamTaskId: string;
  downstreamTaskId: string;
}

export interface TaskGraphNode<T extends TaskGraphTask = TaskGraphTask> {
  task: T;
  rank: number;
  lane: number;
  waitingUpstream: boolean;
}

export interface TaskGraph<T extends TaskGraphTask = TaskGraphTask> {
  nodes: TaskGraphNode<T>[];
  edges: TaskGraphEdge[];
  hasCycle: boolean;
}

export type TaskGraphScope = "workflow" | "all" | "open" | "blocked";
export type SemanticZoomTier = 1 | 2 | 3;

export interface SemanticZoomMetrics {
  zoom: number;
  tier: SemanticZoomTier;
  nodeWidth: number;
  nodeHeight: number;
  padding: number;
  titleFontSize: number;
  metaFontSize: number;
  columnGap: number;
  rowGap: number;
}

function taskIsClosed(task: TaskGraphTask) {
  return task.status === "completed" || task.status === "canceled";
}

function normalizedEdges<T extends TaskGraphTask>(
  tasks: readonly T[],
  dependencies: readonly TaskGraphDependency[],
) {
  const taskIds = new Set(tasks.map((task) => task.id));
  const seen = new Set<string>();
  const edges: TaskGraphEdge[] = [];
  for (const dependency of dependencies) {
    if (
      !taskIds.has(dependency.upstream_task_id) ||
      !taskIds.has(dependency.downstream_task_id) ||
      dependency.upstream_task_id === dependency.downstream_task_id
    ) {
      continue;
    }
    const key = `${dependency.upstream_task_id}:${dependency.downstream_task_id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    edges.push({
      upstreamTaskId: dependency.upstream_task_id,
      downstreamTaskId: dependency.downstream_task_id,
    });
  }
  return edges;
}

export function buildTaskGraph<T extends TaskGraphTask>(
  tasks: readonly T[],
  dependencies: readonly TaskGraphDependency[],
): TaskGraph<T> {
  if (tasks.length === 0) return { nodes: [], edges: [], hasCycle: false };

  const taskOrder = new Map(tasks.map((task, index) => [task.id, index]));
  const tasksById = new Map(tasks.map((task) => [task.id, task]));
  const edges = normalizedEdges(tasks, dependencies);
  const incoming = new Map<string, string[]>();
  const outgoing = new Map<string, string[]>();
  const indegree = new Map(tasks.map((task) => [task.id, 0]));

  for (const edge of edges) {
    const upstream = outgoing.get(edge.upstreamTaskId) ?? [];
    upstream.push(edge.downstreamTaskId);
    outgoing.set(edge.upstreamTaskId, upstream);
    const downstream = incoming.get(edge.downstreamTaskId) ?? [];
    downstream.push(edge.upstreamTaskId);
    incoming.set(edge.downstreamTaskId, downstream);
    indegree.set(
      edge.downstreamTaskId,
      (indegree.get(edge.downstreamTaskId) ?? 0) + 1,
    );
  }

  const queue = tasks
    .filter((task) => (indegree.get(task.id) ?? 0) === 0)
    .map((task) => task.id);
  const rankById = new Map<string, number>();
  const orderedIds: string[] = [];

  while (queue.length > 0) {
    queue.sort(
      (left, right) => (taskOrder.get(left) ?? 0) - (taskOrder.get(right) ?? 0),
    );
    const current = queue.shift();
    if (!current) break;
    orderedIds.push(current);
    const parents = incoming.get(current) ?? [];
    rankById.set(
      current,
      parents.length === 0
        ? 0
        : Math.max(...parents.map((parent) => rankById.get(parent) ?? 0)) + 1,
    );
    for (const child of outgoing.get(current) ?? []) {
      const next = (indegree.get(child) ?? 0) - 1;
      indegree.set(child, next);
      if (next === 0) queue.push(child);
    }
  }

  const hasCycle = orderedIds.length !== tasks.length;
  if (hasCycle) {
    const remainder = tasks
      .map((task) => task.id)
      .filter((taskId) => !orderedIds.includes(taskId));
    const fallbackRank = Math.max(
      0,
      ...Array.from(rankById.values()).map((rank) => rank + 1),
    );
    for (const taskId of remainder) {
      rankById.set(taskId, fallbackRank);
      orderedIds.push(taskId);
    }
  }

  const idsByRank = new Map<number, string[]>();
  for (const taskId of orderedIds) {
    const rank = rankById.get(taskId) ?? 0;
    const rankIds = idsByRank.get(rank) ?? [];
    rankIds.push(taskId);
    idsByRank.set(rank, rankIds);
  }

  // Layered DAGs are much easier to scan when connected nodes stay vertically
  // aligned. Reorder each rank by the barycenter of its neighbours, sweeping
  // down and back up a few times. Original task order remains the stable
  // tie-breaker, so the same facts always produce the same layout.
  const normalizedPositionById = new Map<string, number>();
  const updateRankPositions = (rank: number) => {
    const rankIds = idsByRank.get(rank) ?? [];
    rankIds.forEach((taskId, index) => {
      normalizedPositionById.set(taskId, (index + 0.5) / rankIds.length);
    });
  };
  const ranks = [...idsByRank.keys()].sort((left, right) => left - right);
  for (const rank of ranks) updateRankPositions(rank);

  const reorderRank = (
    rank: number,
    neighboursById: ReadonlyMap<string, string[]>,
  ) => {
    const rankIds = idsByRank.get(rank);
    if (!rankIds || rankIds.length < 2) return;
    const currentOrder = new Map(
      rankIds.map((taskId, index) => [taskId, index]),
    );
    const score = (taskId: string) => {
      const neighbourPositions = (neighboursById.get(taskId) ?? [])
        .map((neighbourId) => normalizedPositionById.get(neighbourId))
        .filter((value): value is number => value !== undefined);
      if (neighbourPositions.length === 0) {
        return ((currentOrder.get(taskId) ?? 0) + 0.5) / rankIds.length;
      }
      return (
        neighbourPositions.reduce((sum, value) => sum + value, 0) /
        neighbourPositions.length
      );
    };

    rankIds.sort((left, right) => {
      const scoreDelta = score(left) - score(right);
      if (Math.abs(scoreDelta) > Number.EPSILON) return scoreDelta;
      const currentDelta =
        (currentOrder.get(left) ?? 0) - (currentOrder.get(right) ?? 0);
      if (currentDelta !== 0) return currentDelta;
      return (taskOrder.get(left) ?? 0) - (taskOrder.get(right) ?? 0);
    });
    updateRankPositions(rank);
  };

  for (let pass = 0; pass < 4; pass += 1) {
    for (const rank of ranks) {
      if (rank === ranks[0]) continue;
      reorderRank(rank, incoming);
    }
    for (const rank of [...ranks].reverse()) {
      if (rank === ranks[ranks.length - 1]) continue;
      reorderRank(rank, outgoing);
    }
  }

  // Center sparse ranks around the densest layer instead of pinning every
  // single-node merge to the top row. Lanes intentionally support halves.
  const maxLayerSize = Math.max(
    1,
    ...[...idsByRank.values()].map((rankIds) => rankIds.length),
  );
  const laneById = new Map<string, number>();
  for (const rankIds of idsByRank.values()) {
    const offset = (maxLayerSize - rankIds.length) / 2;
    rankIds.forEach((taskId, index) => laneById.set(taskId, offset + index));
  }

  const nodes = orderedIds
    .map((taskId) => tasksById.get(taskId))
    .filter((task): task is T => !!task)
    .map((task) => ({
      task,
      rank: rankById.get(task.id) ?? 0,
      lane: laneById.get(task.id) ?? 0,
      waitingUpstream: (incoming.get(task.id) ?? []).some(
        (upstreamId) => !taskIsClosed(tasksById.get(upstreamId)!),
      ),
    }));

  return { nodes, edges, hasCycle };
}

export function directRelationIds(
  taskId: string,
  dependencies: readonly TaskGraphDependency[],
) {
  const ids = new Set<string>([taskId]);
  for (const dependency of dependencies) {
    if (dependency.downstream_task_id === taskId)
      ids.add(dependency.upstream_task_id);
    if (dependency.upstream_task_id === taskId)
      ids.add(dependency.downstream_task_id);
  }
  return ids;
}

export function scopedTaskIds<T extends TaskGraphTask>(
  tasks: readonly T[],
  dependencies: readonly TaskGraphDependency[],
  scope: TaskGraphScope,
) {
  if (scope === "all") return new Set(tasks.map((task) => task.id));

  const tasksById = new Map(tasks.map((task) => [task.id, task]));
  const incoming = new Map<string, string[]>();
  for (const dependency of normalizedEdges(tasks, dependencies)) {
    const list = incoming.get(dependency.downstreamTaskId) ?? [];
    list.push(dependency.upstreamTaskId);
    incoming.set(dependency.downstreamTaskId, list);
  }

  if (scope === "open") {
    return new Set(
      tasks.filter((task) => !taskIsClosed(task)).map((task) => task.id),
    );
  }

  if (scope === "blocked") {
    const blocked = new Set<string>();
    for (const task of tasks) {
      const waiting = (incoming.get(task.id) ?? []).some(
        (id) => !taskIsClosed(tasksById.get(id)!),
      );
      if (task.status === "blocked" || waiting) {
        blocked.add(task.id);
        for (const upstreamId of incoming.get(task.id) ?? [])
          blocked.add(upstreamId);
      }
    }
    return blocked;
  }

  const visible = new Set(
    tasks.filter((task) => !taskIsClosed(task)).map((task) => task.id),
  );
  const stack = [...visible];
  while (stack.length > 0) {
    const taskId = stack.pop();
    if (!taskId) continue;
    for (const upstreamId of incoming.get(taskId) ?? []) {
      if (visible.has(upstreamId)) continue;
      visible.add(upstreamId);
      stack.push(upstreamId);
    }
  }
  return visible;
}

export function foldedHistoryCount<T extends TaskGraphTask>(
  tasks: readonly T[],
  visibleIds: ReadonlySet<string>,
) {
  return tasks.filter((task) => taskIsClosed(task) && !visibleIds.has(task.id))
    .length;
}

export function semanticZoomMetrics(rawZoom: number): SemanticZoomMetrics {
  const zoom = Math.min(160, Math.max(45, Math.round(rawZoom)));
  if (zoom > 100) {
    const scale = zoom / 100;
    return {
      zoom,
      tier: 1,
      nodeWidth: Math.round(236 * scale),
      nodeHeight: Math.round(96 * scale),
      padding: Math.round(15 * scale),
      titleFontSize: Number((15 * scale).toFixed(1)),
      metaFontSize: Number((12.5 * scale).toFixed(1)),
      columnGap: Math.round(82 * scale),
      rowGap: Math.round(30 * scale),
    };
  }
  if (zoom >= 82) {
    return {
      zoom,
      tier: 1,
      nodeWidth: 224,
      nodeHeight: 92,
      padding: 14,
      titleFontSize: 14,
      metaFontSize: 12,
      columnGap: 76,
      rowGap: 28,
    };
  }
  if (zoom >= 58) {
    return {
      zoom,
      tier: 2,
      nodeWidth: 184,
      nodeHeight: 68,
      padding: 12,
      titleFontSize: 13.5,
      metaFontSize: 12,
      columnGap: 62,
      rowGap: 24,
    };
  }
  return {
    zoom,
    tier: 3,
    nodeWidth: 156,
    nodeHeight: 50,
    padding: 10,
    titleFontSize: 13,
    metaFontSize: 12,
    columnGap: 50,
    rowGap: 20,
  };
}

export function bestReadableZoom(taskCount: number, viewportWidth: number) {
  if (taskCount <= 6 && viewportWidth >= 900) return 100;
  if (taskCount <= 14 && viewportWidth >= 720) return 82;
  return 58;
}
