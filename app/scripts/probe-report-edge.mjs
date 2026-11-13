import { execFileSync, spawn } from "node:child_process";
import { clearTimeout, setTimeout } from "node:timers";
import { performance } from "node:perf_hooks";

const isWindows = process.platform === "win32";
const corepack = isWindows ? (process.env.ComSpec ?? "cmd.exe") : "corepack";
const spawnOptions = {
  cwd: process.cwd(),
  stdio: ["ignore", "pipe", "pipe"],
};

function corepackArgs(args) {
  return isWindows ? ["/d", "/s", "/c", "corepack", ...args] : args;
}

function runCorepack(args) {
  return execFileSync(corepack, corepackArgs(args), {
    cwd: process.cwd(),
    encoding: "utf8",
  });
}

function startCorepack(args) {
  return spawn(corepack, corepackArgs(args), spawnOptions);
}

function waitForReady(child, timeoutMs = 30_000) {
  const startedAt = performance.now();
  return new Promise((resolve, reject) => {
    let settled = false;
    let output = "";

    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(performance.now() - startedAt);
    };

    const onData = (chunk) => {
      const text = chunk.toString();
      output = (output + text).slice(-16_000);
      process.stderr.write(text);
      if (output.includes("Serving functions on")) finish();
    };

    const onExit = (code) => {
      finish(
        new Error(
          `Supabase Edge runtime exited before becoming ready (exit ${code ?? "unknown"}).`,
        ),
      );
    };

    const timer = setTimeout(() => {
      finish(
        new Error(
          `Timed out waiting for Supabase Edge runtime. Recent output:\n${output}`,
        ),
      );
    }, timeoutMs);

    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.on("exit", onExit);
  });
}

async function stop(child) {
  if (!child || child.exitCode !== null || child.killed) return;
  if (isWindows && child.pid) {
    await new Promise((resolve) => {
      const killer = spawn(
        "taskkill",
        ["/pid", String(child.pid), "/t", "/f"],
        { stdio: "ignore" },
      );
      killer.on("exit", resolve);
      killer.on("error", resolve);
    });
    return;
  }

  child.kill("SIGTERM");
  await new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      resolve();
    }, 2_000);
    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

function dockerExec(...args) {
  return execFileSync(
    "docker",
    ["exec", "supabase_edge_runtime_xiaozhuwork", ...args],
    {
      encoding: "utf8",
    },
  ).trim();
}

function cpuUsageUsec() {
  const output = dockerExec("sh", "-lc", "cat /sys/fs/cgroup/cpu.stat");
  const match = /^usage_usec\s+(\d+)$/m.exec(output);
  if (!match) throw new Error("Could not read edge runtime cgroup CPU usage");
  return Number(match[1]);
}

function memoryMetric(name) {
  const value = dockerExec("sh", "-lc", `cat /sys/fs/cgroup/${name}`);
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`Could not read edge runtime cgroup ${name}`);
  }
  return parsed;
}

function localSupabaseEnv() {
  const stdout = runCorepack([
    "pnpm",
    "exec",
    "supabase",
    "status",
    "-o",
    "env",
  ]);
  const values = new Map();
  for (const line of stdout.split(/\r?\n/)) {
    const match = /^([A-Z0-9_]+)="(.*)"$/.exec(line.trim());
    if (match) values.set(match[1], match[2]);
  }
  const apiUrl = values.get("API_URL");
  const anonKey = values.get("ANON_KEY");
  if (!apiUrl || !anonKey) {
    throw new Error("Local Supabase status did not expose API_URL/ANON_KEY");
  }
  return { apiUrl, anonKey };
}

const { apiUrl, anonKey } = localSupabaseEnv();
execFileSync("docker", ["restart", "supabase_edge_runtime_xiaozhuwork"], {
  stdio: "ignore",
});

const edge = startCorepack([
  "pnpm",
  "exec",
  "supabase",
  "functions",
  "serve",
  "export-project-report",
]);

let result;
try {
  const serveReadyMs = await waitForReady(edge);
  const cpuBefore = cpuUsageUsec();
  const memoryBefore = memoryMetric("memory.current");

  const requestStartedAt = performance.now();
  const response = await globalThis.fetch(
    `${apiUrl}/functions/v1/export-project-report`,
    {
      method: "POST",
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${anonKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        reportId: "f8000000-0000-4000-8000-000000000001",
        format: "pdf",
      }),
    },
  );
  const responseBody = await response.text();
  const coldRequestMs = performance.now() - requestStartedAt;

  const cpuAfter = cpuUsageUsec();
  const memoryAfter = memoryMetric("memory.current");
  const memoryPeak = memoryMetric("memory.peak");

  result = {
    serveReadyMs: Number(serveReadyMs.toFixed(3)),
    coldRequestMs: Number(coldRequestMs.toFixed(3)),
    coldRequestStatus: response.status,
    coldRequestBody: responseBody.slice(0, 200),
    requestCpuUpperBoundMs: Number(((cpuAfter - cpuBefore) / 1000).toFixed(3)),
    memoryBeforeMiB: Number((memoryBefore / 1024 / 1024).toFixed(3)),
    memoryAfterMiB: Number((memoryAfter / 1024 / 1024).toFixed(3)),
    containerPeakMiB: Number((memoryPeak / 1024 / 1024).toFixed(3)),
  };
} finally {
  await stop(edge);
}

console.log(JSON.stringify(result, null, 2));
