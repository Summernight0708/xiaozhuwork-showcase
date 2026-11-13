import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ContributionSharesPanel from "../../src/components/contributions/ContributionSharesPanel.vue";
import ContributionPenaltyPanel from "../../src/components/contributions/ContributionPenaltyPanel.vue";

const members = [
  { userId: "1", name: "Main", shareBps: 6500, confirmed: true },
  { userId: "2", name: "Collaborator", shareBps: 3500, confirmed: false },
];

describe("contribution governance independent components", () => {
  it("blocks unbalanced proposals and emits integer basis points for valid shares", async () => {
    const wrapper = mount(ContributionSharesPanel, {
      props: { members, canPropose: true, canConfirm: false, state: "pending" },
    });
    expect(wrapper.text()).toContain("100.00%");
    expect(wrapper.text()).toContain("待全员确认");
    await wrapper.findAll('input[type="number"]')[1]!.setValue("40");
    expect(
      wrapper.find('button[type="submit"]').attributes("disabled"),
    ).toBeDefined();
    await wrapper.findAll('input[type="number"]')[1]!.setValue("35");
    await wrapper.find("form").trigger("submit");
    expect(wrapper.emitted("propose")?.[0]?.[0]).toEqual([
      { userId: "1", shareBps: 6500 },
      { userId: "2", shareBps: 3500 },
    ]);
  });
  it("enforces individual confirmation display and emits proposal version", async () => {
    const wrapper = mount(ContributionSharesPanel, {
      props: {
        members,
        canPropose: false,
        canConfirm: true,
        state: "pending",
        proposalId: "p1",
        proposalVersion: 3,
      },
    });
    await wrapper.find("button").trigger("click");
    expect(wrapper.emitted("confirm")?.[0]).toEqual(["p1", 3]);
  });
  it("requires a reason to reject a pending allocation proposal", async () => {
    const wrapper = mount(ContributionSharesPanel, {
      props: {
        members,
        canPropose: false,
        canConfirm: true,
        state: "pending",
        proposalId: "p1",
        proposalVersion: 3,
      },
    });
    const rejectButton = wrapper.find('button[type="submit"]');
    expect(rejectButton.attributes("disabled")).toBeDefined();
    await wrapper.find("textarea").setValue("The allocation is incorrect.");
    await wrapper.findAll("form")[1]!.trigger("submit");
    expect(wrapper.emitted("reject")?.[0]).toEqual([
      "p1",
      3,
      "The allocation is incorrect.",
    ]);
  });
  it("shows penalty calculation and asks for a nonempty reason before appeal", async () => {
    const wrapper = mount(ContributionPenaltyPanel, {
      props: {
        canAppeal: true,
        canVote: false,
        penalty: {
          id: "pen1",
          kind: "late",
          sourceEventId: "evt1",
          effectiveStartAt: "2026-10-01",
          effectiveDeadlineAt: "2026-10-02",
          occurredAt: "2026-10-03",
          durationSeconds: 86400,
          delaySeconds: 86400,
          baseAmount: "4.0000",
          ratePercent: 75,
          amount: "-3.0000",
        },
      },
    });
    expect(wrapper.text()).toContain("-3.0000");
    expect(
      wrapper.find('button[type="submit"]').attributes("disabled"),
    ).toBeDefined();
    await wrapper.find("textarea").setValue("The deadline snapshot was wrong.");
    await wrapper.find("form").trigger("submit");
    expect(wrapper.emitted("appeal")?.[0]).toEqual([
      "pen1",
      "The deadline snapshot was wrong.",
    ]);
  });
});
