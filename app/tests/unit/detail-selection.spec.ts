import { describe, expect, it } from "vitest";

import { selectDetailRecord } from "@/domain/detail-selection";

describe("stable detail route selection", () => {
  const records = [{ id: "one" }, { id: "two" }];

  it("never substitutes another record for an invalid stable detail id", () => {
    expect(selectDetailRecord(records, "missing")).toBeNull();
  });

  it("selects the requested record even when it is not the first list item", () => {
    expect(selectDetailRecord(records, "two")?.id).toBe("two");
  });

  it("may fall back to the first record only when no detail id was requested", () => {
    expect(selectDetailRecord(records, null)?.id).toBe("one");
  });
});
