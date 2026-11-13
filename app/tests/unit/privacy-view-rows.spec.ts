import { describe, expect, it } from "vitest";
import {
  checkedPrivacyRow,
  checkedPrivacyRows,
} from "@/domain/privacy-view-rows";

describe("privacy view non-null contracts", () => {
  const membership = {
    created_at: "2026-10-11T00:00:00Z",
    id: "member-1",
    is_observer: false,
    joined_at: "2026-10-11T00:00:00Z",
    member_state: "active",
    project_id: "project-1",
    role: "member",
    version: 1,
    display_name_snapshot: "已注销成员",
    user_id: null,
    departed_at: null,
  };

  it("accepts complete view data while preserving nullable user identity", () => {
    expect(checkedPrivacyRow("project_members", membership).user_id).toBeNull();
    expect(
      checkedPrivacyRows("project_members", [membership])[0]?.version,
    ).toBe(1);
  });

  it("fails closed when an authoritative required field is nullable", () => {
    expect(() =>
      checkedPrivacyRow("project_members", { ...membership, version: null }),
    ).toThrow("Invalid privacy view row: project_members.version");
  });

  it("accepts empty authorized results without inventing data", () => {
    expect(checkedPrivacyRows("project_members", null)).toEqual([]);
  });
});
