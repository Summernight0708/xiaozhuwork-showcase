import { describe, expect, it } from "vitest";

import {
  bestReadableZoom,
  buildTaskGraph,
  directRelationIds,
  foldedHistoryCount,
  scopedTaskIds,
  semanticZoomMetrics,
  type TaskGraphDependency,
  type TaskGraphTask,
} from "@/domain/task-dependency-graph";

function task(id: string, status = "in_progress"): TaskGraphTask {
  return { id, title: id, status };
}

function dependency(upstream: string, downstream: string): TaskGraphDependency {
  return {
    upstream_task_id: upstream,
    downstream_task_id: downstream,
  };
}

describe("task dependency graph layout", () => {
  it("lays out branches and merges by topological rank", () => {
    const graph = buildTaskGraph(
      [task("A"), task("B"), task("C"), task("D")],
      [
        dependency("A", "B"),
        dependency("A", "C"),
        dependency("B", "D"),
        dependency("C", "D"),
      ],
    );
    expect(
      Object.fromEntries(graph.nodes.map((node) => [node.task.id, node.rank])),
    ).toEqual({ A: 0, B: 1, C: 1, D: 2 });
    expect(graph.nodes.map((node) => [node.task.id, node.lane])).toEqual([
      ["A", 0.5],
      ["B", 0],
      ["C", 1],
      ["D", 0.5],
    ]);
  });

  it("reorders crossed branches by neighbour barycenter", () => {
    const graph = buildTaskGraph(
      [task("A"), task("B"), task("X"), task("Y")],
      [dependency("A", "Y"), dependency("B", "X")],
    );
    const lanes = Object.fromEntries(
      graph.nodes.map((node) => [node.task.id, node.lane]),
    );

    expect(lanes.A!).toBeLessThan(lanes.B!);
    expect(lanes.Y!).toBeLessThan(lanes.X!);
  });

  it("keeps multi-branch layout deterministic across repeated builds", () => {
    const tasks = [
      task("start"),
      task("left"),
      task("middle"),
      task("right"),
      task("merge-a"),
      task("merge-b"),
      task("finish"),
    ];
    const dependencies = [
      dependency("start", "left"),
      dependency("start", "middle"),
      dependency("start", "right"),
      dependency("left", "merge-b"),
      dependency("middle", "merge-a"),
      dependency("right", "merge-a"),
      dependency("merge-a", "finish"),
      dependency("merge-b", "finish"),
    ];
    const snapshot = () =>
      buildTaskGraph(tasks, dependencies).nodes.map((node) => ({
        id: node.task.id,
        rank: node.rank,
        lane: node.lane,
      }));

    expect(snapshot()).toEqual(snapshot());
    expect(snapshot()).toEqual(snapshot());
  });

  it("keeps disconnected tasks stable and drops bad duplicate edges", () => {
    const graph = buildTaskGraph(
      [task("B"), task("A"), task("C")],
      [dependency("A", "C"), dependency("A", "C"), dependency("missing", "C")],
    );
    expect(graph.edges).toEqual([
      { upstreamTaskId: "A", downstreamTaskId: "C" },
    ]);
    expect(new Set(graph.nodes.map((node) => node.task.id))).toEqual(
      new Set(["A", "B", "C"]),
    );
  });

  it("falls back safely when an unexpected cycle reaches the UI", () => {
    const graph = buildTaskGraph(
      [task("outside"), task("A"), task("B")],
      [dependency("A", "B"), dependency("B", "A")],
    );
    expect(graph.hasCycle).toBe(true);
    expect(graph.nodes).toHaveLength(3);
    expect(new Set(graph.nodes.map((node) => node.task.id))).toEqual(
      new Set(["outside", "A", "B"]),
    );
  });

  it("derives waiting-upstream state from incomplete parents", () => {
    const graph = buildTaskGraph(
      [task("done", "completed"), task("open"), task("target")],
      [dependency("done", "target"), dependency("open", "target")],
    );
    expect(
      graph.nodes.find((node) => node.task.id === "target")?.waitingUpstream,
    ).toBe(true);
  });
});

describe("graph scopes and focus", () => {
  const tasks = [
    task("history", "completed"),
    task("required", "completed"),
    task("open"),
    task("blocked", "blocked"),
  ];
  const dependencies = [
    dependency("required", "open"),
    dependency("open", "blocked"),
  ];

  it("shows active work plus necessary completed upstream in workflow scope", () => {
    const ids = scopedTaskIds(tasks, dependencies, "workflow");
    expect(ids).toEqual(new Set(["required", "open", "blocked"]));
    expect(foldedHistoryCount(tasks, ids)).toBe(1);
  });

  it("supports all, open, and blocked/waiting scopes", () => {
    expect(scopedTaskIds(tasks, dependencies, "all").size).toBe(4);
    expect(scopedTaskIds(tasks, dependencies, "open")).toEqual(
      new Set(["open", "blocked"]),
    );
    expect(scopedTaskIds(tasks, dependencies, "blocked")).toEqual(
      new Set(["open", "blocked"]),
    );
  });

  it("focuses only the current task and direct relations", () => {
    expect(directRelationIds("open", dependencies)).toEqual(
      new Set(["required", "open", "blocked"]),
    );
  });
});

describe("semantic zoom", () => {
  it("uses full detail at 82% and above", () => {
    expect(semanticZoomMetrics(82).tier).toBe(1);
    expect(semanticZoomMetrics(100).tier).toBe(1);
  });

  it("uses title plus status from 58% through 81%", () => {
    expect(semanticZoomMetrics(58).tier).toBe(2);
    expect(semanticZoomMetrics(81).tier).toBe(2);
  });

  it("uses title-only nodes below 58% with readable floors", () => {
    const metrics = semanticZoomMetrics(50);
    expect(metrics.tier).toBe(3);
    expect(metrics.titleFontSize).toBeGreaterThanOrEqual(13);
    expect(metrics.nodeWidth).toBeGreaterThanOrEqual(156);
    expect(metrics.nodeHeight).toBeGreaterThanOrEqual(50);
  });

  it("scales card, font, padding, and gaps together above 100%", () => {
    const base = semanticZoomMetrics(100);
    const zoomed = semanticZoomMetrics(150);
    expect(zoomed.nodeWidth).toBeGreaterThan(base.nodeWidth);
    expect(zoomed.nodeHeight).toBeGreaterThan(base.nodeHeight);
    expect(zoomed.titleFontSize).toBeGreaterThan(base.titleFontSize);
    expect(zoomed.padding).toBeGreaterThan(base.padding);
    expect(zoomed.columnGap).toBeGreaterThan(base.columnGap);
  });

  it("chooses a readable best view instead of shrinking arbitrarily to fit all", () => {
    expect(bestReadableZoom(4, 1200)).toBe(100);
    expect(bestReadableZoom(10, 900)).toBe(82);
    expect(bestReadableZoom(80, 500)).toBe(58);
  });
});
