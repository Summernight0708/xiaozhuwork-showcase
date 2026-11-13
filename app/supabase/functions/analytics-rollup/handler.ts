export type AnalyticsRollupInput = {
  fromDate: string;
  toDate: string;
  definitionVersion: 1;
};

export type AnalyticsRollupResult =
  { ok: true; data: unknown } | { ok: false; code: string };

export type AnalyticsRollupDependencies = {
  serviceCredential: string;
  now: () => Date;
  runRollup: (input: AnalyticsRollupInput) => Promise<AnalyticsRollupResult>;
};

const DATE = /^\d{4}-\d{2}-\d{2}$/;

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

function validDate(value: unknown): value is string {
  if (typeof value !== "string" || !DATE.test(value)) return false;
  const parsed = Date.parse(value + "T00:00:00.000Z");
  return (
    Number.isFinite(parsed) &&
    new Date(parsed).toISOString().slice(0, 10) === value
  );
}

function shiftDate(date: string, days: number): string {
  const instant = new Date(date + "T00:00:00.000Z");
  instant.setUTCDate(instant.getUTCDate() + days);
  return instant.toISOString().slice(0, 10);
}

function shanghaiDate(now: Date): string {
  return new Date(now.getTime() + 8 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

function parseInput(body: unknown, now: Date): AnalyticsRollupInput | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const data = body as Record<string, unknown>;
  const keys = Object.keys(data);
  if (
    keys.some(
      (key) =>
        key !== "fromDate" && key !== "toDate" && key !== "definitionVersion",
    )
  ) {
    return null;
  }
  if (data.definitionVersion !== 1) return null;

  const hasFrom = data.fromDate !== undefined;
  const hasTo = data.toDate !== undefined;
  if (hasFrom !== hasTo) return null;

  if (!hasFrom) {
    const previous = shiftDate(shanghaiDate(now), -1);
    return {
      fromDate: shiftDate(previous, -6),
      toDate: previous,
      definitionVersion: 1,
    };
  }

  if (!validDate(data.fromDate) || !validDate(data.toDate)) return null;
  if (data.fromDate > data.toDate) return null;

  return {
    fromDate: data.fromDate,
    toDate: data.toDate,
    definitionVersion: 1,
  };
}

export async function handleAnalyticsRollupRequest(
  request: Request,
  deps: AnalyticsRollupDependencies,
): Promise<Response> {
  if (request.method !== "POST") {
    return json({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  }

  const auth = request.headers.get("authorization") ?? "";
  const bearer = /^Bearer\s+(\S+)$/i.exec(auth)?.[1] ?? "";
  if (!bearer) {
    return json({ ok: false, code: "UNAUTHENTICATED" }, 401);
  }
  if (
    !deps.serviceCredential ||
    !constantTimeEqual(bearer, deps.serviceCredential)
  ) {
    return json({ ok: false, code: "FORBIDDEN" }, 403);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, code: "VALIDATION_FAILED" }, 400);
  }

  const input = parseInput(body, deps.now());
  if (!input) {
    return json({ ok: false, code: "VALIDATION_FAILED" }, 400);
  }

  try {
    const result = await deps.runRollup(input);
    if (result.ok) return json(result, 200);
    return json(result, 503);
  } catch {
    return json({ ok: false, code: "ROLLUP_FAILED" }, 503);
  }
}
