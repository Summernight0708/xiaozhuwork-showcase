import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const task = process.argv[2];
if (!task) {
  console.error("Usage: node scripts/android-gradle.mjs <task>");
  process.exit(2);
}

const executable = process.platform === "win32" ? "gradlew.bat" : "./gradlew";
const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const result = spawnSync(executable, [task], {
  cwd: resolve(scriptDirectory, "../android"),
  stdio: "inherit",
  shell: process.platform === "win32",
});

if (result.error) throw result.error;
process.exit(result.status ?? 1);
