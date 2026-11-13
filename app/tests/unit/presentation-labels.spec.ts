import { describe, expect, it } from "vitest";

import {
  displayMemberStateLabel,
  displayReviewLabel,
  displayStatusLabel,
} from "@/domain/presentation-labels";

describe("presentation labels", () => {
  it("keeps internal enum values out of user-facing status copy", () => {
    expect(displayStatusLabel("pending_acceptance")).toBe("待接受");
    expect(displayStatusLabel("in_progress")).toBe("进行中");
    expect(displayStatusLabel("awaiting_review")).toBe("待验收");
    expect(displayStatusLabel("completed_without_review")).toBe(
      "无需验收 · 已完成",
    );
  });

  it("fails closed to Chinese copy for new or unknown enum values", () => {
    expect(displayStatusLabel("future_internal_state")).toBe("状态待确认");
    expect(displayReviewLabel(null, "future_review_state")).toBe(
      "验收状态待确认",
    );
    expect(displayMemberStateLabel("future_member_state")).toBe(
      "成员状态待确认",
    );
  });

  it("prioritizes a review decision over the round state", () => {
    expect(displayReviewLabel("request_changes", "pending")).toBe("需修改");
    expect(displayReviewLabel(null, "pending")).toBe("待验收");
  });
});
