import { beforeEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
const mocks = vi.hoisted(() => ({
  user: { id: "alpha" } as { id: string },
  list: vi.fn(),
  save: vi.fn(),
}));
vi.mock("@/stores/auth", () => ({
  useAuthStore: () => ({ user: mocks.user }),
}));
vi.mock("@/services/backend", () => ({ getBackend: () => ({ client: {} }) }));
vi.mock("@/services/help-preferences", () => ({
  listHelpDismissals: mocks.list,
  saveHelpDismissal: mocks.save,
}));
import { useHelpStore } from "@/stores/help";
describe("cross-device dismissal preferences", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    mocks.user.id = "alpha";
    vi.resetAllMocks();
  });
  it("loads and independently dismisses hints without overwriting others", async () => {
    mocks.list.mockResolvedValue(["v1:intro:leader"]);
    mocks.save.mockResolvedValue(undefined);
    const store = useHelpStore();
    await store.loadForUser("alpha");
    expect(store.dismissed.has("v1:intro:leader")).toBe(true);
    expect(await store.dismiss("v1:intro:member")).toEqual({ synced: true });
    expect(store.dismissed.has("v1:intro:leader")).toBe(true);
    expect(mocks.save).toHaveBeenCalledWith(
      expect.anything(),
      "alpha",
      "v1:intro:member",
    );
  });
  it("discards previous account response after account switch", async () => {
    let finish!: (keys: string[]) => void;
    mocks.list
      .mockReturnValueOnce(
        new Promise((resolve) => {
          finish = resolve;
        }),
      )
      .mockResolvedValueOnce([]);
    const store = useHelpStore();
    const oldLoad = store.loadForUser("alpha");
    mocks.user.id = "beta";
    await store.loadForUser("beta");
    finish(["v1:intro:leader"]);
    await oldLoad;
    expect(store.loadedForUserId).toBe("beta");
    expect(store.dismissed.has("v1:intro:leader")).toBe(false);
  });
  it("keeps local dismissal but reports unsynced when offline", async () => {
    mocks.list.mockResolvedValue([]);
    mocks.save.mockRejectedValue(new Error("offline"));
    const store = useHelpStore();
    await store.loadForUser("alpha");
    expect(await store.dismiss("v1:intro:leader")).toEqual({ synced: false });
    expect(store.syncError).toBe(true);
  });
});
