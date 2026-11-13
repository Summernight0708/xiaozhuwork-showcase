import { getBackend } from "./backend";

export type EnhancedReportFormat = "csv" | "pdf";
export type EnhancedReportAvailability =
  "planned" | "requires_pro" | "available";

export class EnhancedReportDownloadError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "EnhancedReportDownloadError";
  }
}

const ERROR_LABELS: Record<string, string> = {
  UNAUTHENTICATED: "登录已失效，请重新登录",
  NOT_FOUND_OR_NOT_AUTHORIZED: "无权查看该报告或报告不存在",
  REPORT_NOT_READY: "贡献报告尚未正式化",
  CAPABILITY_NOT_AVAILABLE: "增强报告功能尚未发布",
  CAPABILITY_REQUIRES_PRO: "当前项目需要 Pro 权益",
  VALIDATION_FAILED: "报告参数无效",
  SERVICE_UNAVAILABLE: "服务暂时不可用，请稍后重试",
};

export function enhancedReportErrorMessage(error: unknown): string {
  if (error instanceof EnhancedReportDownloadError)
    return ERROR_LABELS[error.code] ?? ERROR_LABELS.SERVICE_UNAVAILABLE!;
  if (error instanceof Error && error.name === "AbortError")
    return "下载已取消";
  return ERROR_LABELS.SERVICE_UNAVAILABLE!;
}

export function isEnhancedReportAbort(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

export async function downloadEnhancedReport(
  reportId: string,
  format: EnhancedReportFormat,
  signal?: AbortSignal,
): Promise<Blob> {
  const backend = getBackend();
  if (!backend) throw new EnhancedReportDownloadError("SERVICE_UNAVAILABLE");
  if (signal?.aborted)
    throw new DOMException("Download cancelled", "AbortError");
  const { data, error } = await backend.client.functions.invoke(
    "export-enhanced-project-report",
    { body: { reportId, format }, signal },
  );
  if (signal?.aborted)
    throw new DOMException("Download cancelled", "AbortError");
  if (error) {
    const context = (error as { context?: unknown }).context;
    if (context instanceof Response) {
      try {
        const body: unknown = await context.clone().json();
        if (
          body &&
          typeof body === "object" &&
          "code" in body &&
          typeof (body as { code?: unknown }).code === "string"
        ) {
          throw new EnhancedReportDownloadError(
            (body as { code: string }).code,
          );
        }
      } catch (err) {
        if (err instanceof EnhancedReportDownloadError) throw err;
      }
    }
    throw new EnhancedReportDownloadError("SERVICE_UNAVAILABLE");
  }
  // functions-js returns text/csv as text and application/pdf as Blob.
  const blob =
    format === "csv" && typeof data === "string"
      ? new Blob([data], { type: "text/csv; charset=utf-8" })
      : data;
  if (!(blob instanceof Blob)) {
    throw new EnhancedReportDownloadError("SERVICE_UNAVAILABLE");
  }
  const expected = format === "pdf" ? "application/pdf" : "text/csv";
  if (!blob.type.startsWith(expected) || blob.size === 0) {
    throw new EnhancedReportDownloadError("SERVICE_UNAVAILABLE");
  }
  return blob;
}
