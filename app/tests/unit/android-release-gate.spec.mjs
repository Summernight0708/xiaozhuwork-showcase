import { Buffer } from "node:buffer";
import process from "node:process";
import { afterAll, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { validateReleaseEnvironment } from "../../scripts/android-release-gate.mjs";

const scratch = mkdtempSync(join(tmpdir(), "xiaozhu-release-gate-"));
const keystore = join(scratch, "test.jks");
writeFileSync(keystore, "not a real keystore");

describe("Android release preflight", () => {
  const env = {
    VITE_SUPABASE_URL: "https://xiaozhuwork.com",
    VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test_only_valid",
    ANDROID_KEYSTORE_PATH: keystore,
    ANDROID_KEYSTORE_PASSWORD: "fake-test-password",
    ANDROID_KEY_ALIAS: "test-alias",
    ANDROID_KEY_PASSWORD: "fake-test-password",
  };

  it("rejects signing credentials or production config that are absent", () => {
    expect(validateReleaseEnvironment({}, process.cwd())).not.toEqual([]);
  });

  it("accepts configured production origin and externally stored keystore", () => {
    expect(validateReleaseEnvironment(env, process.cwd())).toEqual([]);
  });

  it("rejects staging backend and privileged public keys", () => {
    expect(
      validateReleaseEnvironment(
        { ...env, VITE_SUPABASE_URL: "https://staging.example" },
        process.cwd(),
      ),
    ).toContain(
      "VITE_SUPABASE_URL must point to the HTTPS Hong Kong production origin",
    );
    expect(
      validateReleaseEnvironment(
        { ...env, VITE_SUPABASE_PUBLISHABLE_KEY: "sb_secret_bad" },
        process.cwd(),
      ),
    ).toContain("privileged Supabase key is forbidden in the Android bundle");
  });

  it("rejects arbitrary input accidentally supplied as a public API key", () => {
    expect(
      validateReleaseEnvironment(
        { ...env, VITE_SUPABASE_PUBLISHABLE_KEY: "not-a-public-key" },
        process.cwd(),
      ),
    ).toContain(
      "Android production public key must be a publishable key or anon JWT",
    );
  });

  it("rejects malformed publishable keys and non-anon JWTs", () => {
    const fakeJwt = (role) =>
      [
        Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString(
          "base64url",
        ),
        Buffer.from(JSON.stringify({ role })).toString("base64url"),
        "testsignature",
      ].join(".");
    expect(
      validateReleaseEnvironment(
        { ...env, VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_bad" },
        process.cwd(),
      ),
    ).toContain(
      "Android production public key must be a publishable key or anon JWT",
    );
    expect(
      validateReleaseEnvironment(
        { ...env, VITE_SUPABASE_PUBLISHABLE_KEY: fakeJwt("authenticated") },
        process.cwd(),
      ),
    ).toContain(
      "Android production public key must be a publishable key or anon JWT",
    );
    expect(
      validateReleaseEnvironment(
        { ...env, VITE_SUPABASE_PUBLISHABLE_KEY: fakeJwt("service_role") },
        process.cwd(),
      ),
    ).toContain("privileged Supabase key is forbidden in the Android bundle");
  });

  it("accepts a structurally valid public anon JWT", () => {
    const jwt = [
      Buffer.from('{"alg":"HS256","typ":"JWT"}').toString("base64url"),
      Buffer.from('{"role":"anon"}').toString("base64url"),
      "testsignature",
    ].join(".");
    expect(
      validateReleaseEnvironment(
        {
          ...env,
          VITE_SUPABASE_PUBLISHABLE_KEY: "",
          VITE_SUPABASE_ANON_KEY: jwt,
        },
        process.cwd(),
      ),
    ).toEqual([]);
  });
  it("rejects keystore stored under the checkout", () => {
    expect(
      validateReleaseEnvironment(
        {
          ...env,
          ANDROID_KEYSTORE_PATH: join(process.cwd(), "app-version.json"),
        },
        process.cwd(),
      ),
    ).toContain("Android release keystore must not be inside the Git checkout");
  });
});

afterAll(() => rmSync(scratch, { recursive: true, force: true }));
