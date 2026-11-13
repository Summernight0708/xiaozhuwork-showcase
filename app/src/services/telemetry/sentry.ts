import * as Sentry from "@sentry/vue";

import {
  containsSensitiveTelemetryValue,
  sanitizeUrl,
} from "@shared/telemetry";

interface SentryRequestLike {
  url?: string;
  method?: string;
  data?: unknown;
  headers?: Record<string, string>;
  cookies?: unknown;
}

interface SentryUserLike {
  id?: string | number;
}

interface SentryBreadcrumbLike {
  category?: string;
  type?: string;
  message?: string;
  data?: Record<string, unknown>;
}

interface SentryEventLike {
  request?: SentryRequestLike;
  user?: SentryUserLike;
  extra?: Record<string, unknown>;
  transaction?: string;
  message?: string;
  exception?: unknown;
  breadcrumbs?: SentryBreadcrumbLike[];
  tags?: Record<
    string,
    string | number | boolean | bigint | symbol | null | undefined
  >;
}

const PRIVATE_HEADER_NAMES = new Set([
  "authorization",
  "cookie",
  "set-cookie",
  "x-api-key",
  "x-client-info",
]);

function routeTemplateFromUrl(rawUrl: string): string {
  const path = sanitizeUrl(rawUrl);

  const patterns: Array<[RegExp, string]> = [
    [/^\/invite\/[^/]+$/, "/invite/:token"],
    [/^\/projects\/:id\/tasks\/:id$/, "/projects/:projectId/tasks/:taskId"],
    [/^\/projects\/:id\/files\/:id$/, "/projects/:projectId/files/:fileId"],
    [
      /^\/projects\/:id\/reviews\/:id$/,
      "/projects/:projectId/reviews/:reviewRoundId",
    ],
    [
      /^\/projects\/:id\/contributions\/:id$/,
      "/projects/:projectId/contributions/:reportId",
    ],
    [/^\/projects\/:id\/tasks$/, "/projects/:projectId/tasks"],
    [/^\/projects\/:id\/tasks\/new$/, "/projects/:projectId/tasks/new"],
    [/^\/projects\/:id\/files$/, "/projects/:projectId/files"],
    [/^\/projects\/:id\/reviews$/, "/projects/:projectId/reviews"],
    [/^\/projects\/:id\/contributions$/, "/projects/:projectId/contributions"],
    [/^\/projects\/:id\/members$/, "/projects/:projectId/members"],
    [/^\/projects\/:id\/analytics$/, "/projects/:projectId/analytics"],
    [/^\/projects\/:id\/permissions$/, "/projects/:projectId/permissions"],
    [/^\/projects\/:id\/integrations$/, "/projects/:projectId/integrations"],
    [/^\/projects\/:id\/invitations$/, "/projects/:projectId/invitations"],
    [/^\/projects\/:id\/settings$/, "/projects/:projectId/settings"],
    [/^\/projects\/:id\/todos$/, "/projects/:projectId/todos"],
    [/^\/projects\/:id$/, "/projects/:projectId"],
  ];

  for (const [pattern, template] of patterns) {
    if (pattern.test(path)) return template;
  }
  return path;
}

function sanitizeHeaders(
  headers: Record<string, string> | undefined,
): Record<string, string> | undefined {
  if (!headers) return undefined;

  const entries = Object.entries(headers).filter(
    ([name, value]) =>
      !PRIVATE_HEADER_NAMES.has(name.toLowerCase()) &&
      !containsSensitiveTelemetryValue(value),
  );
  return entries.length ? Object.fromEntries(entries) : undefined;
}

function sanitizeBreadcrumbUrl(value: unknown): string | undefined {
  return typeof value === "string" ? routeTemplateFromUrl(value) : undefined;
}

export function sanitizeSentryBreadcrumb<T extends SentryBreadcrumbLike>(
  breadcrumb: T,
): T | null {
  const category = breadcrumb.category?.toLowerCase() ?? "";
  const type = breadcrumb.type?.toLowerCase() ?? "";

  if (category === "console" || category.startsWith("ui.") || type === "user") {
    return null;
  }

  const base = { ...breadcrumb } as T;

  if (category === "navigation") {
    const from = sanitizeBreadcrumbUrl(breadcrumb.data?.from);
    const to = sanitizeBreadcrumbUrl(breadcrumb.data?.to);
    base.data = {
      ...(from ? { from } : {}),
      ...(to ? { to } : {}),
    };
    delete base.message;
    return base;
  }

  if (category === "fetch" || category === "xhr") {
    const method =
      typeof breadcrumb.data?.method === "string"
        ? breadcrumb.data.method
        : undefined;
    const statusCode =
      typeof breadcrumb.data?.status_code === "number"
        ? breadcrumb.data.status_code
        : undefined;
    const url = sanitizeBreadcrumbUrl(breadcrumb.data?.url);

    base.data = {
      ...(method ? { method } : {}),
      ...(statusCode !== undefined ? { status_code: statusCode } : {}),
      ...(url ? { url } : {}),
    };
    delete base.message;
    return base;
  }

  if (
    (breadcrumb.message &&
      containsSensitiveTelemetryValue(breadcrumb.message)) ||
    (breadcrumb.data && containsSensitiveTelemetryValue(breadcrumb.data))
  ) {
    return null;
  }

  return base;
}

const REDACTED_SENSITIVE_MESSAGE = "[redacted sensitive message]";

function redactSensitiveMessage(value: unknown): unknown {
  if (typeof value !== "string") return value;
  return containsSensitiveTelemetryValue(value)
    ? REDACTED_SENSITIVE_MESSAGE
    : value;
}

export function sanitizeSentryEvent<T extends SentryEventLike>(event: T): T {
  const sanitized = { ...event } as T;

  delete sanitized.extra;
  delete sanitized.transaction;

  const messageEvent = sanitized as T & { message?: string };
  if (messageEvent.message) {
    messageEvent.message = redactSensitiveMessage(
      messageEvent.message,
    ) as string;
  }

  const exceptionEvent = sanitized as T & {
    exception?: { values?: Array<{ value?: string }> };
  };
  if (exceptionEvent.exception?.values) {
    exceptionEvent.exception = {
      ...exceptionEvent.exception,
      values: exceptionEvent.exception.values.map((value) => ({
        ...value,
        ...(value.value
          ? { value: redactSensitiveMessage(value.value) as string }
          : {}),
      })),
    };
  }

  if (event.request) {
    const request: SentryRequestLike = {
      ...event.request,
      ...(event.request.url
        ? { url: routeTemplateFromUrl(event.request.url) }
        : {}),
      headers: sanitizeHeaders(event.request.headers),
    };
    delete request.data;
    delete request.cookies;
    sanitized.request = request;
  }

  if (event.user?.id !== undefined && event.user?.id !== null) {
    sanitized.user = { id: String(event.user.id) };
  } else {
    delete sanitized.user;
  }

  if (event.breadcrumbs) {
    sanitized.breadcrumbs = event.breadcrumbs
      .map((breadcrumb) => sanitizeSentryBreadcrumb(breadcrumb))
      .filter(
        (breadcrumb): breadcrumb is SentryBreadcrumbLike => breadcrumb !== null,
      );
  }

  if (event.tags) {
    const safeTags = Object.fromEntries(
      Object.entries(event.tags).filter(
        ([, value]) =>
          value == null ||
          typeof value !== "string" ||
          !containsSensitiveTelemetryValue(value),
      ),
    );
    sanitized.tags = safeTags;
  }

  return sanitized;
}

export function syncSentryUser(userId: string | null | undefined): void {
  Sentry.setUser(userId ? { id: userId } : null);
}
