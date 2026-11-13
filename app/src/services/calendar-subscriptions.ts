import { getBackend } from "@/services/backend";

export type CalendarSubscription = {
  id: string;
  createdAt: string;
  expiresAt: string;
  revokedAt: string | null;
  version: number;
  showTitles: boolean;
};

export type CalendarResult<T> =
  | { ok: true; data: T; replayed?: boolean; aggregateVersion?: number }
  | { ok: false; code: string; currentVersion?: number; field?: string };

type RpcClient = {
  rpc: (
    name: string,
    args: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: { message: string } | null }>;
};

async function request<T>(
  name: string,
  args: Record<string, unknown>,
): Promise<CalendarResult<T>> {
  const backend = getBackend();
  if (!backend) return { ok: false, code: "SERVICE_UNAVAILABLE" };
  // G regenerates and registers shared generated RPC types at integration.
  const client = backend.client as unknown as RpcClient;
  try {
    const { data, error } = await client.rpc(name, args);
    if (error || !data || typeof data !== "object" || Array.isArray(data)) {
      return { ok: false, code: "SERVICE_UNAVAILABLE" };
    }
    const response = data as Partial<CalendarResult<T>>;
    if (response.ok === true && "data" in response) {
      return response as CalendarResult<T>;
    }
    if (response.ok === false && typeof response.code === "string") {
      return response as CalendarResult<T>;
    }
  } catch {
    // Network and transport errors never expose backend internals.
  }
  return { ok: false, code: "SERVICE_UNAVAILABLE" };
}

export function listCalendarSubscriptions(projectId: string) {
  return request<{
    projectVersion: number;
    subscriptions: CalendarSubscription[];
  }>("get_project_calendar_subscriptions", { p_project_id: projectId });
}

export function createCalendarSubscription(
  projectId: string,
  expectedVersion: number,
  showTitles: boolean,
  requestId: string = crypto.randomUUID(),
) {
  return request<CalendarSubscription & { token: string | null }>(
    "cmd_create_calendar_feed_subscription",
    {
      p_project_id: projectId,
      p_request_id: requestId,
      p_expected_version: expectedVersion,
      p_show_titles: showTitles,
    },
  );
}

export function revokeCalendarSubscription(
  projectId: string,
  subscriptionId: string,
  expectedVersion: number,
  requestId: string = crypto.randomUUID(),
) {
  return request<Pick<CalendarSubscription, "id" | "version" | "revokedAt">>(
    "cmd_revoke_calendar_feed_subscription",
    {
      p_project_id: projectId,
      p_subscription_id: subscriptionId,
      p_request_id: requestId,
      p_expected_version: expectedVersion,
    },
  );
}

export function calendarSubscriptionUrl(
  token: string,
  supabaseUrl: string = import.meta.env.VITE_SUPABASE_URL ?? "",
): string {
  if (!/^[a-f0-9]{64}$/.test(token))
    throw new Error("Invalid subscription token");
  const base = new URL(supabaseUrl);
  if (
    base.protocol !== "https:" &&
    base.hostname !== "localhost" &&
    base.hostname !== "127.0.0.1"
  ) {
    throw new Error("Subscription endpoint must use HTTPS");
  }
  // G validates the public proxy route before the release flag is enabled.
  return new URL(
    `functions/v1/calendar-feed/${token}.ics`,
    base.href.replace(/\/?$/, "/"),
  ).toString();
}
