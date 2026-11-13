import type { Router } from "vue-router";

import {
  containsSensitiveTelemetryValue,
  normalizeRouteTemplate,
  sanitizeUrl,
  type TelemetryRouteLike,
} from "@shared/telemetry";

export interface UmamiTracker {
  track(payload: { website: string; url: string; title: string }): void;
}

interface UmamiRouter {
  afterEach(callback: (route: TelemetryRouteLike) => void): unknown;
}

export interface UmamiConfig {
  hostUrl: string;
  websiteId: string;
}

type UmamiPayload = {
  website?: unknown;
  url?: unknown;
  title?: unknown;
  [key: string]: unknown;
};

declare global {
  interface Window {
    umami?: UmamiTracker;
    xiaozhuworkUmamiBeforeSend?: (
      type: string,
      payload: UmamiPayload,
    ) => UmamiPayload | false;
  }
}

const ALLOWED_PAGEVIEW_FIELDS = new Set(["website", "url", "title"]);

function normalizedHostUrl(hostUrl: string): string {
  return hostUrl.trim().replace(/\/+$/, "");
}

function validPageviewPayload(
  payload: UmamiPayload,
  expectedWebsiteId: string,
): boolean {
  const keys = Object.keys(payload);
  if (
    keys.length !== ALLOWED_PAGEVIEW_FIELDS.size ||
    keys.some((key) => !ALLOWED_PAGEVIEW_FIELDS.has(key))
  ) {
    return false;
  }

  const website = payload.website;
  const url = payload.url;
  const title = payload.title;
  if (
    typeof website !== "string" ||
    website !== expectedWebsiteId ||
    typeof url !== "string" ||
    !url.startsWith("/") ||
    typeof title !== "string" ||
    !title.trim()
  ) {
    return false;
  }

  if (url.includes("?") || url.includes("#")) return false;
  if (sanitizeUrl(url) !== url) return false;
  return !containsSensitiveTelemetryValue({ url, title });
}

export function createXiaozhuWorkUmamiBeforeSend(
  websiteId: string,
): (type: string, payload: UmamiPayload) => UmamiPayload | false {
  const expectedWebsiteId = websiteId.trim();

  return (type: string, payload: UmamiPayload): UmamiPayload | false => {
    if (type !== "event" || !expectedWebsiteId) return false;
    if (!validPageviewPayload(payload, expectedWebsiteId)) return false;

    return {
      website: expectedWebsiteId,
      url: payload.url,
      title: payload.title,
    };
  };
}

function trackRoute(websiteId: string, route: TelemetryRouteLike): boolean {
  const tracker = window.umami;
  if (!tracker) return false;

  const normalized = normalizeRouteTemplate(route);
  tracker.track({
    website: websiteId,
    url: normalized.url,
    title: normalized.title,
  });
  return true;
}

export function initializeUmami(
  router: Pick<Router, "afterEach"> | UmamiRouter,
  config: UmamiConfig,
): void {
  const hostUrl = normalizedHostUrl(config.hostUrl);
  const websiteId = config.websiteId.trim();
  if (!hostUrl || !websiteId || typeof document === "undefined") return;

  window.xiaozhuworkUmamiBeforeSend =
    createXiaozhuWorkUmamiBeforeSend(websiteId);

  let pendingRoute: TelemetryRouteLike | null = null;
  router.afterEach((route) => {
    if (trackRoute(websiteId, route)) {
      pendingRoute = null;
      return;
    }
    pendingRoute = route;
  });

  if (document.querySelector('script[data-xiaozhuwork-umami="true"]')) return;

  const script = document.createElement("script");
  script.defer = true;
  script.src = hostUrl + "/script.js";
  script.dataset.xiaozhuworkUmami = "true";
  script.dataset.websiteId = websiteId;
  script.dataset.autoPageview = "false";
  script.dataset.excludeSearch = "true";
  script.dataset.excludeHash = "true";
  script.dataset.doNotTrack = "true";
  script.dataset.beforeSend = "xiaozhuworkUmamiBeforeSend";
  script.addEventListener("load", () => {
    if (pendingRoute) {
      const route = pendingRoute;
      if (trackRoute(websiteId, route)) pendingRoute = null;
    }
  });
  document.head.append(script);
}
