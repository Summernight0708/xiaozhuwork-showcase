import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import EnhancedReportActions from "@/components/reports/EnhancedReportActions.vue";
import {
  EnhancedReportDownloadError,
  downloadEnhancedReport,
  enhancedReportErrorMessage,
} from "@/services/enhanced-report";
import { getBackend } from "@/services/backend";

vi.mock("@/services/backend", () => ({ getBackend: vi.fn() }));
const REPORT = "b8000000-0000-4000-8000-000000000001";
const props = {
  reportId: REPORT,
  reportState: "formal" as const,
  canRead: true,
};
const originalCreate = URL.createObjectURL;
const originalRevoke = URL.revokeObjectURL;

beforeEach(() => {
  Object.defineProperty(URL, "createObjectURL", {
    configurable: true,
    value: vi.fn(() => "blob:report-test"),
  });
  Object.defineProperty(URL, "revokeObjectURL", {
    configurable: true,
    value: vi.fn(),
  });
  vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(
    () => undefined,
  );
});
afterEach(() => {
  vi.restoreAllMocks();
  Object.defineProperty(URL, "createObjectURL", {
    configurable: true,
    value: originalCreate,
  });
  Object.defineProperty(URL, "revokeObjectURL", {
    configurable: true,
    value: originalRevoke,
  });
});

describe("B standalone enhanced report actions (not globally released)", () => {
  test("conceals actions when no read privilege", () => {
    const wrapper = mount(EnhancedReportActions, {
      props: { ...props, canRead: false, availability: "available" },
    });
    expect(wrapper.find("section").exists()).toBe(false);
  });

  test("planned defaults to fail-closed and never runs downloads", async () => {
    const action = vi.fn();
    const wrapper = mount(EnhancedReportActions, {
      props: { ...props, exportAction: action },
    });
    expect(wrapper.text()).toContain("尚未开放");
    expect(wrapper.findAll("button")).toHaveLength(0);
    expect(action).not.toHaveBeenCalled();
  });

  test("draft and Free explain reasons without starting export", async () => {
    const action = vi.fn();
    const draft = mount(EnhancedReportActions, {
      props: {
        ...props,
        reportState: "draft",
        availability: "available",
        exportAction: action,
      },
    });
    expect(draft.text()).toContain("正式化");
    expect(draft.findAll("button")).toHaveLength(0);
    const free = mount(EnhancedReportActions, {
      props: { ...props, availability: "requires_pro", exportAction: action },
    });
    expect(free.text()).toContain("Pro 权益");
    expect(free.findAll("button")).toHaveLength(0);
    expect(action).not.toHaveBeenCalled();
  });

  test("downloads CSV and blocks duplicate submissions while pending", async () => {
    let done!: (value: Blob) => void;
    const action = vi.fn(
      () => new Promise<Blob>((resolve) => (done = resolve)),
    );
    const wrapper = mount(EnhancedReportActions, {
      props: { ...props, availability: "available", exportAction: action },
    });
    await wrapper.findAll("button")[1]!.trigger("click");
    expect(wrapper.text()).toContain("正在生成 CSV");
    expect(wrapper.findAll("button")[0]!.attributes("disabled")).toBeDefined();
    expect(action).toHaveBeenCalledTimes(1);
    done(new Blob(["a,b"], { type: "text/csv" }));
    await flushPromises();
    expect(URL.createObjectURL).toHaveBeenCalledOnce();
    expect(HTMLAnchorElement.prototype.click).toHaveBeenCalledOnce();
    expect(
      wrapper.findAll("button")[0]!.attributes("disabled"),
    ).toBeUndefined();
    wrapper.unmount();
  });

  test("cancels an in-flight request without leaking links", async () => {
    const action = vi.fn(
      (_id: string, _format: string, signal: AbortSignal) =>
        new Promise<Blob>((_, reject) =>
          signal.addEventListener("abort", () =>
            reject(new DOMException("Abort", "AbortError")),
          ),
        ),
    );
    const wrapper = mount(EnhancedReportActions, {
      props: { ...props, availability: "available", exportAction: action },
    });
    await wrapper.findAll("button")[0]!.trigger("click");
    await wrapper.findAll("button")[2]!.trigger("click");
    await flushPromises();
    expect(wrapper.text()).not.toContain("下载失败");
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(wrapper.findAll("button")).toHaveLength(2);
    wrapper.unmount();
  });

  test("cancellation immediately unblocks UI even when transport ignores abort", async () => {
    const resolvers: Array<(file: Blob) => void> = [];
    const action = vi.fn(
      () => new Promise<Blob>((resolve) => resolvers.push(resolve)),
    );
    const wrapper = mount(EnhancedReportActions, {
      props: { ...props, availability: "available", exportAction: action },
    });
    await wrapper.findAll("button")[0]!.trigger("click");
    await wrapper.findAll("button")[2]!.trigger("click");
    expect(wrapper.findAll("button")).toHaveLength(2);
    await wrapper.findAll("button")[1]!.trigger("click");
    expect(wrapper.findAll("button")[0]!.attributes("disabled")).toBeDefined();
    resolvers[0]!(new Blob(["old"], { type: "application/pdf" }));
    await flushPromises();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(wrapper.findAll("button")[0]!.attributes("disabled")).toBeDefined();
    resolvers[1]!(new Blob(["new"], { type: "text/csv" }));
    await flushPromises();
    expect(URL.createObjectURL).toHaveBeenCalledOnce();
    expect(
      wrapper.findAll("button")[0]!.attributes("disabled"),
    ).toBeUndefined();
    wrapper.unmount();
  });

  test("maps entitlement error from service into user-visible text", async () => {
    const action = vi.fn(async () => {
      throw new EnhancedReportDownloadError("CAPABILITY_REQUIRES_PRO");
    });
    const wrapper = mount(EnhancedReportActions, {
      props: { ...props, availability: "available", exportAction: action },
    });
    await wrapper.findAll("button")[0]!.trigger("click");
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain("Pro 权益");
  });
});

describe("B enhanced report standalone service transport", () => {
  test("converts text/csv returned by functions-js to downloadable CSV Blob", async () => {
    const invoke = vi.fn(async () => ({
      data: "col1,col2\r\n中文,2\r\n",
      error: null,
    }));
    vi.mocked(getBackend).mockReturnValue({
      client: { functions: { invoke } },
    } as unknown as ReturnType<typeof getBackend>);
    const file = await downloadEnhancedReport(REPORT, "csv");
    expect(file).toBeInstanceOf(Blob);
    expect(file.type).toContain("text/csv");
    const text = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error);
      reader.readAsText(file);
    });
    expect(text).toContain("中文");
    expect(invoke).toHaveBeenCalledWith(
      "export-enhanced-project-report",
      expect.objectContaining({ body: { reportId: REPORT, format: "csv" } }),
    );
  });
  test("accepts PDF Blob while refusing empty and mismatched MIME", async () => {
    const invoke = vi.fn(async () => ({
      data: new Blob(["%PDF-1.4"], { type: "application/pdf" }),
      error: null,
    }));
    vi.mocked(getBackend).mockReturnValue({
      client: { functions: { invoke } },
    } as unknown as ReturnType<typeof getBackend>);
    expect((await downloadEnhancedReport(REPORT, "pdf")).type).toBe(
      "application/pdf",
    );
    invoke.mockResolvedValueOnce({
      data: new Blob(["bad"], { type: "text/plain" }),
      error: null,
    });
    await expect(downloadEnhancedReport(REPORT, "pdf")).rejects.toMatchObject({
      code: "SERVICE_UNAVAILABLE",
    });
  });
  test("handles RPC error code via FunctionsHttpError context", async () => {
    const context = new Response(
      JSON.stringify({ ok: false, code: "REPORT_NOT_READY" }),
      {
        status: 409,
        headers: { "content-type": "application/json" },
      },
    );
    const invoke = vi.fn(async () => ({ data: null, error: { context } }));
    vi.mocked(getBackend).mockReturnValue({
      client: { functions: { invoke } },
    } as unknown as ReturnType<typeof getBackend>);
    await expect(downloadEnhancedReport(REPORT, "pdf")).rejects.toMatchObject({
      code: "REPORT_NOT_READY",
    });
    expect(
      enhancedReportErrorMessage(
        new EnhancedReportDownloadError("REPORT_NOT_READY"),
      ),
    ).toContain("正式");
  });
});
