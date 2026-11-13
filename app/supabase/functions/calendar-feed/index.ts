declare const Deno: {
  env: { get: (name: string) => string | undefined };
  serve: (handler: (request: Request) => Promise<Response>) => void;
};

import {
  renderCalendarFeed,
  type CalendarFeed,
} from "../_shared/calendar-ics.ts";

const SECURITY_HEADERS: Record<string, string> = {
  "cache-control": "private, no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};
const TOKEN_URL = /(?:^|\/)calendar-feed\/([a-f0-9]{64})\.ics$/;
const MAX_REQUESTS_PER_MINUTE_PER_INSTANCE = 1200;

let bucketMinute = -1;
let bucketRequests = 0;
function allowInstanceRequest(now: number): boolean {
  const current = Math.floor(now / 60_000);
  if (current !== bucketMinute) {
    bucketMinute = current;
    bucketRequests = 0;
  }
  bucketRequests += 1;
  return bucketRequests <= MAX_REQUESTS_PER_MINUTE_PER_INSTANCE;
}

type Dependencies = {
  env?: (key: string) => string | undefined;
  fetcher?: typeof fetch;
  allowRequest?: () => boolean;
  now?: () => Date;
};

function unavailable(status = 404): Response {
  return new Response(null, { status, headers: SECURITY_HEADERS });
}

export async function handleCalendarFeedRequest(
  request: Request,
  dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method !== "GET") {
    return new Response(null, {
      status: 405,
      headers: { ...SECURITY_HEADERS, allow: "GET" },
    });
  }
  const now = dependencies.now?.() ?? new Date();
  if (!(dependencies.allowRequest?.() ?? allowInstanceRequest(now.getTime()))) {
    return unavailable(429);
  }
  let url: URL;
  try {
    url = new URL(request.url);
  } catch {
    return unavailable();
  }
  // Exact HTTP request path only. No token is read from query or headers.
  const match = TOKEN_URL.exec(url.pathname);
  if (!match || url.search || url.hash) return unavailable();
  // Edge TLS termination may happen at a trusted reverse proxy. G must
  // enforce HTTPS at the public ingress; this strict switch is for direct TLS.
  const env = dependencies.env ?? ((key: string) => Deno.env.get(key));
  if (
    env("CALENDAR_FEED_ENFORCE_HTTPS") === "true" &&
    url.protocol !== "https:"
  ) {
    return unavailable();
  }

  const serviceUrl = env("SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceUrl || !serviceKey) return unavailable(503);
  try {
    const upstream = await (dependencies.fetcher ?? fetch)(
      `${serviceUrl.replace(/\/$/, "")}/rest/v1/rpc/phase2_calendar_feed_lookup`,
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          authorization: `Bearer ${serviceKey}`,
          "content-type": "application/json",
          "cache-control": "no-store",
        },
        body: JSON.stringify({ p_token: match[1] }),
        signal: AbortSignal.timeout(5000),
      },
    );
    if (!upstream.ok) return unavailable();
    const payload: unknown = await upstream.json();
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return unavailable();
    }
    const feed = payload as Partial<CalendarFeed>;
    if (
      feed.ok !== true ||
      !Array.isArray(feed.events) ||
      typeof feed.showTitles !== "boolean" ||
      typeof feed.truncated !== "boolean"
    ) {
      return unavailable();
    }
    const ics = renderCalendarFeed(feed as CalendarFeed, now);
    return new Response(ics, {
      status: 200,
      headers: {
        ...SECURITY_HEADERS,
        "content-type": "text/calendar; charset=utf-8",
        "content-disposition": 'inline; filename="calendar.ics"',
      },
    });
  } catch {
    // Do not log request URL, secret, headers, upstream body or raw error.
    return unavailable();
  }
}

if (typeof Deno !== "undefined" && import.meta.main) {
  Deno.serve((request) => handleCalendarFeedRequest(request));
}
