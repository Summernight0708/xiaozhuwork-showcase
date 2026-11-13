import { describe, expect, it } from "vitest";
import {
  allocateContributionPool,
  formatUnits,
  freeAbandonSeconds,
  penaltyAmountUnits,
  penaltyRateBps,
} from "../../src/features/contribution-governance/math";

describe("authoritative contribution arithmetic preview", () => {
  it("splits four stars into 6500/3500 with no double counting", () => {
    const a = allocateContributionPool(40000n, [
      { userId: "a", shareBps: 6500 },
      { userId: "b", shareBps: 3500 },
    ]);
    expect(a.map((x) => formatUnits(x.amountUnits))).toEqual([
      "2.6000",
      "1.4000",
    ]);
    expect(a.reduce((s, x) => s + x.amountUnits, 0n)).toBe(40000n);
  });
  it("conserves 0.0001 residual in stable user id order", () => {
    const input = [
      { userId: "z", shareBps: 3333 },
      { userId: "a", shareBps: 3333 },
      { userId: "m", shareBps: 3334 },
    ];
    const a = allocateContributionPool(10001n, input);
    expect(a.reduce((s, x) => s + x.amountUnits, 0n)).toBe(10001n);
    expect(a.find((x) => x.userId === "a")?.amountUnits).toBe(3334n);
    expect(a.find((x) => x.userId === "z")?.amountUnits).toBe(3333n);
  });
  it("rejects repeated participants, negative or non-integer bps, and non-100% sums", () => {
    expect(() =>
      allocateContributionPool(40000n, [{ userId: "a", shareBps: 9999 }]),
    ).toThrow();
    expect(() =>
      allocateContributionPool(40000n, [
        { userId: "a", shareBps: 5000 },
        { userId: "a", shareBps: 5000 },
      ]),
    ).toThrow();
    expect(() =>
      allocateContributionPool(40000n, [{ userId: "a", shareBps: 10000.1 }]),
    ).toThrow();
  });
  it("implements all PEN-006 exact inclusive thresholds", () => {
    expect(
      [100n, 101n, 300n, 301n, 600n, 601n, 1000n, 1001n].map((d) =>
        penaltyRateBps("late", d, 1000n),
      ),
    ).toEqual([1000, 2500, 2500, 5000, 5000, 7500, 7500, 10000]);
    expect(
      [100n, 101n, 300n, 301n, 600n, 601n, 1000n, 1001n].map((d) =>
        penaltyRateBps("abandon", d, 1000n),
      ),
    ).toEqual([2500, 5000, 5000, 7500, 7500, 10000, 10000, 15000]);
  });
  it("uses floor 10% for free abandonment and permits negative contribution totals", () => {
    expect(freeAbandonSeconds(19n)).toBe(1n);
    expect(formatUnits(20000n + penaltyAmountUnits(40000n, 15000))).toBe(
      "-4.0000",
    );
  });
});
