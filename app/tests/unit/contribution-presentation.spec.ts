import { describe, expect, it } from "vitest";

import { buildMemberContributionRows } from "@/domain/contribution-presentation";

describe("contribution presentation", () => {
  const members = [
    {
      id: "m2",
      user_id: "user-b",
      display_name_snapshot: "李四",
      is_observer: false,
      member_state: "active",
      role: "member",
    },
    {
      id: "m1",
      user_id: "user-a",
      display_name_snapshot: "张三",
      is_observer: false,
      member_state: "active",
      role: "leader",
    },
    {
      id: "observer",
      user_id: "user-o",
      display_name_snapshot: "观察者",
      is_observer: true,
      member_state: "active",
      role: "observer",
    },
  ];

  const tasks = [
    { id: "task-a", assignee_id: "user-a" },
    { id: "task-b", assignee_id: "user-b" },
    { id: "task-c", assignee_id: "user-a" },
  ];

  it("preserves project member order and only counts authoritative primary completions", () => {
    const rows = buildMemberContributionRows({
      members,
      tasks,
      items: [
        {
          taskId: "task-a",
          memberUserId: "user-a",
          taskWeight: 4,
          share: 1,
          contributionValue: 4,
          taskTitle: "数据分析",
          completedAt: "2026-10-01T00:00:00Z",
        },
        {
          taskId: "task-b",
          memberUserId: "user-b",
          taskWeight: 2,
          share: 1,
          contributionValue: 2,
          taskTitle: "问卷整理",
          completedAt: "2026-10-02T00:00:00Z",
        },
        {
          taskId: "task-c",
          memberUserId: "user-a",
          taskWeight: 3,
          share: 1,
          contributionValue: 3,
          taskTitle: "结果复核",
          completedAt: "2026-10-03T00:00:00Z",
        },
      ],
    });

    expect(rows.map((row) => row.userId)).toEqual(["user-b", "user-a"]);
    expect(rows.map((row) => row.primaryCompleted)).toEqual([1, 2]);
    expect(rows.map((row) => row.contributionScore)).toEqual([2, 7]);
    expect(rows.every((row) => row.collaboratorParticipated === null)).toBe(
      true,
    );
  });

  it("counts one completed primary task despite multiple ledger entries", () => {
    const rows = buildMemberContributionRows({
      members: [members[1]!],
      tasks: [tasks[0]!],
      items: [
        {
          taskId: "task-a",
          memberUserId: "user-a",
          share: 0.65,
          contributionValue: 2.6,
          taskTitle: "协作分析",
          completedAt: "2026-10-01T00:00:00Z",
        },
        {
          taskId: "task-a",
          memberUserId: "user-a",
          share: 0,
          contributionValue: -0.26,
          taskTitle: "协作分析",
          completedAt: "2026-10-01T00:00:00Z",
        },
      ],
    });
    expect(rows[0]?.primaryCompleted).toBe(1);
    expect(rows[0]?.contributionScore).toBeCloseTo(2.34);
  });

  it("does not fabricate a score when the authoritative report is facts-only", () => {
    const rows = buildMemberContributionRows({
      members: [members[1]!],
      tasks: [tasks[0]!],
      items: [
        {
          taskId: "task-a",
          memberUserId: "user-a",
          share: 1,
          taskTitle: "数据分析",
          completedAt: "2026-10-01T00:00:00Z",
        },
      ],
    });

    expect(rows[0]?.primaryCompleted).toBe(1);
    expect(rows[0]?.contributionScore).toBeNull();
    expect(rows[0]?.collaboratorParticipated).toBeNull();
  });
  it("retains redacted contribution values as one unattributable aggregate", () => {
    const rows = buildMemberContributionRows({
      members,
      tasks,
      items: [
        {
          taskId: "task-a",
          memberUserId: "user-a",
          share: 1,
          contributionValue: 3,
          taskTitle: "ordinary member work",
          completedAt: "2026-10-03T00:00:00Z",
        },
        {
          taskId: "task-b",
          share: 0.7,
          contributionValue: 2.5,
          taskTitle: "historical masked task",
          completedAt: "2026-10-02T00:00:00Z",
        },
        {
          taskId: "task-c",
          share: 0.5,
          contributionValue: -0.5,
          taskTitle: "historical adjustment",
          completedAt: "2026-10-01T00:00:00Z",
        },
      ],
    });

    expect(rows.map((row) => row.userId)).toEqual([
      "user-b",
      "user-a",
      "anonymous-contribution-aggregate",
    ]);
    expect(rows[0]?.primaryCompleted).toBeNull();
    expect(rows[1]?.contributionScore).toBe(3);
    expect(rows[2]).toMatchObject({
      displayName: "匿名贡献（汇总）",
      primaryCompleted: null,
      collaboratorParticipated: null,
      contributionScore: 2,
    });
    expect(rows[2]?.items).toHaveLength(2);
    expect(
      rows.reduce((sum, row) => sum + (row.contributionScore ?? 0), 0),
    ).toBe(5);
  });

  it("does not invent numbers for masked facts-only contributions", () => {
    const rows = buildMemberContributionRows({
      members: [],
      tasks,
      items: [
        {
          taskId: "task-b",
          share: 1,
          taskTitle: "masked facts-only task",
          completedAt: "2026-10-02T00:00:00Z",
        },
      ],
    });
    expect(rows).toHaveLength(1);
    expect(rows[0]?.displayName).toBe("匿名贡献（汇总）");
    expect(rows[0]?.primaryCompleted).toBeNull();
    expect(rows[0]?.contributionScore).toBeNull();
  });
});
