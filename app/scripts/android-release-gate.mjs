import { Buffer } from "node:buffer";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { URL, fileURLToPath } from "node:url";
import process from "node:process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const expectedOrigin = new Set(["xiaozhuwork.com", "www.xiaozhuwork.com"]);
const signingVars = [
  "ANDROID_KEYSTORE_PATH",
  "ANDROID_KEYSTORE_PASSWORD",
  "ANDROID_KEY_ALIAS",
  "ANDROID_KEY_PASSWORD",
];

function isWithinRoot(candidate, checkoutRoot) {
  const pathFromRoot = relative(
    realpathSync(checkoutRoot),
    realpathSync(candidate),
  );
  return (
    pathFromRoot === "" ||
    (!pathFromRoot.startsWith(`..${sep}`) &&
      pathFromRoot !== ".." &&
      !isAbsolute(pathFromRoot))
  );
}

function jwtRole(value) {
  try {
    const payload = value.split(".")[1];
    if (!payload) return null;
    return (
      JSON.parse(Buffer.from(payload, "base64url").toString("utf8")).role ??
      null
    );
  } catch {
    return null;
  }
}

export function validateReleaseEnvironment(
  env = process.env,
  checkoutRoot = root,
) {
  const issues = [];
  const publicUrl = env.VITE_SUPABASE_URL?.trim();
  const publicKey =
    env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
    env.VITE_SUPABASE_ANON_KEY?.trim();

  try {
    const url = new URL(publicUrl);
    if (
      url.protocol !== "https:" ||
      !expectedOrigin.has(url.hostname) ||
      url.pathname !== "/" ||
      url.search ||
      url.hash ||
      url.username ||
      url.password
    ) {
      issues.push(
        "VITE_SUPABASE_URL must point to the HTTPS Hong Kong production origin",
      );
    }
  } catch {
    issues.push("VITE_SUPABASE_URL is missing or invalid");
  }
  if (!publicKey) {
    issues.push("a production public publishable/anon key is required");
  } else if (
    publicKey.startsWith("sb_secret_") ||
    jwtRole(publicKey) === "service_role"
  ) {
    issues.push("privileged Supabase key is forbidden in the Android bundle");
  } else if (
    !/^sb_publishable_[A-Za-z0-9_-]{10,}$/.test(publicKey) &&
    !(
      /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(publicKey) &&
      jwtRole(publicKey) === "anon"
    )
  ) {
    issues.push(
      "Android production public key must be a publishable key or anon JWT",
    );
  }
  for (const name of signingVars) {
    if (!env[name]?.trim()) issues.push(`${name} is missing`);
  }
  const keystore = env.ANDROID_KEYSTORE_PATH?.trim();
  if (keystore) {
    if (!isAbsolute(keystore) || !existsSync(keystore)) {
      issues.push(
        "ANDROID_KEYSTORE_PATH must be an existing absolute path outside Git",
      );
    } else if (isWithinRoot(keystore, checkoutRoot)) {
      issues.push(
        "Android release keystore must not be inside the Git checkout",
      );
    } else if (
      ![".jks", ".keystore"].some((ext) => keystore.toLowerCase().endsWith(ext))
    ) {
      issues.push(
        "Android release keystore must have .jks or .keystore extension",
      );
    }
  }
  return issues;
}

function findSdkTool(name) {
  const sdk =
    process.env.ANDROID_HOME ||
    process.env.ANDROID_SDK_ROOT ||
    join(process.env.LOCALAPPDATA || join(tmpdir(), ".."), "Android", "Sdk");
  const buildTools = join(sdk, "build-tools");
  if (!existsSync(buildTools))
    throw new Error("Android SDK build-tools not found");
  const versions = readdirSync(buildTools).sort((a, b) =>
    b.localeCompare(a, undefined, { numeric: true }),
  );
  const extension =
    process.platform === "win32"
      ? name === "apksigner"
        ? ".bat"
        : ".exe"
      : "";
  for (const version of versions) {
    const binary = join(buildTools, version, name + extension);
    if (existsSync(binary)) return binary;
  }
  throw new Error(`Android SDK tool missing: ${name}`);
}

function callTool(name, args) {
  const binary = findSdkTool(name);
  const result = spawnSync(binary, args, {
    encoding: "utf8",
    shell: process.platform === "win32" && binary.endsWith(".bat"),
    maxBuffer: 8 * 1024 * 1024,
  });
  if (result.status !== 0 || result.error) {
    throw new Error(
      `${name} verification failed: ${result.error?.message || result.stderr || "unknown error"}`,
    );
  }
  return result.stdout;
}

function checkBundle() {
  const assetDir = join(root, "dist", "assets");
  if (!existsSync(assetDir)) throw new Error("Vite production bundle missing");
  for (const name of readdirSync(assetDir)) {
    if (!name.endsWith(".js")) continue;
    const content = readFileSync(join(assetDir, name), "utf8");
    if (
      /sb_secret_[A-Za-z0-9_-]+/.test(content) ||
      /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(content) ||
      /postgres(?:ql)?:\/\//.test(content)
    ) {
      throw new Error("Server secret pattern detected in Android web bundle");
    }
    for (const match of content.matchAll(
      /eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,
    )) {
      if (jwtRole(match[0]) === "service_role") {
        throw new Error("Service-role JWT detected in Android web bundle");
      }
    }
  }
}

function verifySignedApk() {
  const file = join(
    root,
    "android",
    "app",
    "build",
    "outputs",
    "apk",
    "release",
    "app-release.apk",
  );
  if (!existsSync(file) || statSync(file).size === 0) {
    throw new Error("Signed release APK not found");
  }
  checkBundle();
  const certs = callTool("apksigner", [
    "verify",
    "--verbose",
    "--print-certs",
    file,
  ]);
  const badging = callTool("aapt", ["dump", "badging", file]);
  const { versionName, versionCode } = JSON.parse(
    readFileSync(join(root, "app-version.json"), "utf8"),
  );
  const packageLine = badging
    .split(/\r?\n/)
    .find((line) => line.startsWith("package:"));
  if (
    !packageLine ||
    !packageLine.includes("name='com.xiaozhuzuoye.app'") ||
    !packageLine.includes(`versionCode='${versionCode}'`) ||
    !packageLine.includes(`versionName='${versionName}'`)
  ) {
    throw new Error("APK package ID or version mismatch");
  }
  if (badging.includes("application-debuggable")) {
    throw new Error("Release APK is debuggable");
  }
  const fingerprint = certs.match(
    /Signer #1 certificate SHA-256 digest:\s*([a-f0-9]+)/i,
  )?.[1];
  if (!fingerprint)
    throw new Error("Verified certificate fingerprint not found");
  const targetDir = join(root, "artifacts", "android");
  mkdirSync(targetDir, { recursive: true });
  const target = join(targetDir, `xiaozhu-homework-v${versionName}.apk`);
  copyFileSync(file, target);
  const data = readFileSync(target);
  const digest = createHash("sha256").update(data).digest("hex");
  console.log(
    `SIGNED_RELEASE_VERIFIED package=com.xiaozhuzuoye.app version=${versionName} code=${versionCode}`,
  );
  console.log(`APK_PATH=${target}`);
  console.log(`APK_SIZE_BYTES=${data.length}`);
  console.log(`APK_SHA256=${digest}`);
  console.log(`CERT_SHA256=${fingerprint}`);
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    const mode = process.argv[2];
    if (mode !== "preflight" && mode !== "verify") {
      throw new Error(
        "Usage: node scripts/android-release-gate.mjs preflight|verify",
      );
    }
    const issues = validateReleaseEnvironment();
    if (issues.length) throw new Error(issues.join("; "));
    if (mode === "verify") verifySignedApk();
    else
      console.log(
        "Android production/signing preflight: PASS (passwords not logged)",
      );
  } catch (error) {
    console.error("Android release gate BLOCKED:", error.message);
    process.exitCode = 1;
  }
}
