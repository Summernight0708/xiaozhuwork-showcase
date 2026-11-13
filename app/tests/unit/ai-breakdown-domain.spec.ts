import { describe, expect, it } from "vitest";

import { sortSubmissionFileTypes } from "@/domain/submission-file-types";
import {
  clampDuration,
  createDrafts,
  draftToTaskInput,
  resolveDraftWeight,
  suggestDeadlines,
  validateDraft,
  type AiBreakdownItem,
} from "@/domain/ai-breakdown";

const NOW = Date.parse("2026-10-21T08:00:00.000Z");
const DDL = "2026-10-28T08:00:00.000Z";

function items(durations: number[]): Array<{ durationDays: number }> {
  return durations.map((durationDays) => ({ durationDays }));
}

describe("clampDuration", () => {
  it("clamps into the valid range", () => {
    expect(clampDuration(0)).toBe(1);
    expect(clampDuration(100)).toBe(30);
    expect(clampDuration(2.6)).toBe(3);
    expect(clampDuration(NaN)).toBe(3);
  });
});

describe("suggestDeadlines", () => {
  it("keeps deadlines inside the project DDL and non-decreasing", () => {
    const deadlines = suggestDeadlines(items([2, 5, 3]), DDL, NOW);
    expect(deadlines).toHaveLength(3);
    const times = deadlines.map((value) => Date.parse(value));
    for (const time of times) {
      expect(time).toBeGreaterThan(NOW);
      expect(time).toBeLessThanOrEqual(Date.parse(DDL));
    }
    expect(times[0]).toBeLessThanOrEqual(times[1]!);
    expect(times[1]).toBeLessThanOrEqual(times[2]!);
  });

  it("weights deadlines by duration, long tasks claim more of the window", () => {
    const deadlines = suggestDeadlines(items([8, 1]), DDL, NOW);
    const [first, second] = deadlines.map((value) => Date.parse(value));
    // The 8-day task ends at 8/9 of the window; the 1-day task at the DDL.
    expect(second! - first!).toBeCloseTo((Date.parse(DDL) - NOW) / 9, -3);
    expect(second!).toBe(Date.parse(DDL));
  });

  it("returns empty for no items", () => {
    expect(suggestDeadlines([], DDL, NOW)).toEqual([]);
  });

  it("falls back to forward spread when the DDL is invalid", () => {
    const deadlines = suggestDeadlines(items([3]), "not-a-date", NOW);
    const time = Date.parse(deadlines[0]!);
    expect(time).toBe(NOW + 3 * 86_400_000);
  });

  it("caps every deadline at an already-reached DDL", () => {
    const deadlines = suggestDeadlines(items([2]), DDL, Date.parse(DDL));
    expect(Date.parse(deadlines[0]!)).toBe(Date.parse(DDL));
  });
});

describe("createDrafts", () => {
  const source: AiBreakdownItem[] = [
    {
      title: "问卷设计",
      description: "设计 20 题问卷",
      durationDays: 2,
      fileTypes: ["docx"],
    },
    {
      title: "数据分析",
      description: "清洗并分析数据",
      durationDays: 4,
      fileTypes: ["xlsx", "csv"],
    },
  ];

  it("builds unique, selected drafts with deadlines", () => {
    const drafts = createDrafts(source, DDL, NOW);
    expect(drafts).toHaveLength(2);
    expect(new Set(drafts.map((draft) => draft.key)).size).toBe(2);
    expect(drafts.every((draft) => draft.selected)).toBe(true);
    expect(
      drafts.every((draft) => Number.isFinite(Date.parse(draft.deadlineAt))),
    ).toBe(true);
    expect(drafts[0]!.fileTypes).toEqual(["docx"]);
  });
});

describe("draftToTaskInput", () => {
  it("maps a draft to the workspace createTask input shape", () => {
    const draft = createDrafts(
      [
        {
          title: "  调研报告  ",
          description: "  ",
          durationDays: 5,
          fileTypes: ["pdf"],
        },
      ],
      DDL,
      NOW,
    )[0]!;
    const input = draftToTaskInput(draft);
    expect(input.title).toBe("调研报告");
    expect(input.description).toBeUndefined();
    expect(input.assignmentMode).toBe("claimable");
    expect(input.requiredSubmissionFileTypes).toEqual(["pdf"]);
    expect(input.requiresReview).toBe(true);
    expect(input.deadlineAt).toBe(draft.deadlineAt);
  });
});

describe("sortSubmissionFileTypes", () => {
  it("orders values by the canonical master list", () => {
    expect(sortSubmissionFileTypes(["docx", "pdf", "xlsx"])).toEqual([
      "pdf",
      "docx",
      "xlsx",
    ]);
    expect(sortSubmissionFileTypes(["pptx"])).toEqual(["pptx"]);
  });
});

describe("resolveDraftWeight", () => {
  it("uses the default score unless the project is facts-only", () => {
    expect(resolveDraftWeight("weighted")).toBe(3);
    expect(resolveDraftWeight("facts_only")).toBeUndefined();
    expect(resolveDraftWeight(null)).toBe(3);
    expect(resolveDraftWeight(undefined)).toBe(3);
  });
});

describe("validateDraft", () => {
  function draft(
    overrides: Partial<ReturnType<typeof createDrafts>[number]> = {},
  ) {
    const base = createDrafts(
      [{ title: "任务", description: "", durationDays: 3, fileTypes: [] }],
      DDL,
      NOW,
    )[0]!;
    return { ...base, ...overrides };
  }

  it("rejects empty titles, past deadlines and deadlines after the DDL", () => {
    expect(validateDraft(draft({ title: "  " }), DDL, NOW)).toBe(
      "请填写任务名称",
    );
    expect(
      validateDraft(
        draft({ deadlineAt: "2026-10-20T08:00:00.000Z" }),
        DDL,
        NOW,
      ),
    ).toBe("任务截止时间必须晚于当前时间");
    expect(
      validateDraft(
        draft({ deadlineAt: "2026-10-29T08:00:00.000Z" }),
        DDL,
        NOW,
      ),
    ).toBe("任务截止时间不能晚于项目 DDL");
  });

  it("accepts a valid draft", () => {
    expect(validateDraft(draft(), DDL, NOW)).toBeNull();
  });
});
