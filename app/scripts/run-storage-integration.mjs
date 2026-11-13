import { spawn } from "node:child_process";
import { clearTimeout, setTimeout } from "node:timers";

const isWindows = process.platform === "win32";
const corepack = isWindows ? (process.env.ComSpec ?? "cmd.exe") : "corepack";
const spawnOptions = {
  cwd: process.cwd(),
  stdio: ["ignore", "pipe", "pipe"],
};

function startCorepack(args) {
  const commandArgs = isWindows
    ? ["/d", "/s", "/c", "corepack", ...args]
    : args;
  return spawn(corepack, commandArgs, spawnOptions);
}

function waitForReady(child, timeoutMs = 30_000) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let output = "";

    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve();
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

function runTests() {
  return new Promise((resolve, reject) => {
    const child = startCorepack([
      "pnpm",
      "exec",
      "vitest",
      "run",
      "--config",
      "vitest.storage.config.ts",
    ]);
    child.stdout.pipe(process.stdout);
    child.stderr.pipe(process.stderr);
    child.on("error", reject);
    child.on("exit", (code) => resolve(code ?? 1));
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

const edge = startCorepack(["pnpm", "exec", "supabase", "functions", "serve"]);

let exitCode = 1;
try {
  await waitForReady(edge);
  exitCode = await runTests();
} catch (error) {
  console.error(error);
} finally {
  await stop(edge);
}

process.exitCode = exitCode;
