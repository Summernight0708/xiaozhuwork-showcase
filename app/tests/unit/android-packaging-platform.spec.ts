import { describe, expect, it } from "vitest";

import { safeDownloadFileName } from "@/platform/downloads";
import { classifyExternalUrl } from "@/platform/external-links";
import {
  registerNativeBackHandler,
  runNativeBackHandlers,
} from "@/platform/native-back";
import { parseAndroidDownloadManifest } from "@/services/android-download-manifest";

describe("Android packaging platform contracts", () => {
  it("sanitizes unsafe download filenames without losing extensions", () => {
    expect(safeDownloadFileName('  report:*?"<>|.pdf  ')).toBe(
      "report_______.pdf",
    );
    expect(safeDownloadFileName("...")).toBe("download");
  });

  it("classifies in-app, browser, app-launcher and blocked URLs", () => {
    const origin = "https://xiaozhu.example";
    expect(classifyExternalUrl("/projects", origin)).toBe("internal");
    expect(classifyExternalUrl("https://example.org/help", origin)).toBe(
      "browser",
    );
    expect(classifyExternalUrl("mailto:hello@example.org", origin)).toBe("app");
    expect(classifyExternalUrl("javascript:alert(1)", origin)).toBe("blocked");
  });

  it("fails closed when the Android download manifest is absent or malformed", () => {
    expect(parseAndroidDownloadManifest({ available: false })).toEqual({
      available: false,
    });
    expect(
      parseAndroidDownloadManifest({
        available: true,
        versionName: "0.1.0",
        versionCode: 1,
        apkUrl: "javascript:alert(1)",
        sha256: "a".repeat(64),
        sizeBytes: 123,
        minAndroid: 7,
        publishedAt: "2026-10-08T00:00:00Z",
      }),
    ).toEqual({ available: false });
  });

  it("accepts a complete Android download manifest", () => {
    expect(
      parseAndroidDownloadManifest({
        available: true,
        versionName: "0.1.0",
        versionCode: 1,
        apkUrl: "/downloads/android/xiaozhu-homework-v0.1.0.apk",
        sha256: "a".repeat(64),
        sizeBytes: 12_345_678,
        minAndroid: 7,
        publishedAt: "2026-10-08T00:00:00Z",
      }),
    ).toMatchObject({
      available: true,
      versionName: "0.1.0",
      versionCode: 1,
      sha256: "a".repeat(64),
    });
  });

  it("rejects external, insecure and mismatched APK manifest links", () => {
    const valid = {
      available: true,
      versionName: "0.1.0",
      versionCode: 1,
      apkUrl: "/downloads/android/xiaozhu-homework-v0.1.0.apk",
      sha256: "a".repeat(64),
      sizeBytes: 12_345_678,
      minAndroid: 7,
      publishedAt: "2026-10-08T00:00:00Z",
    };
    for (const apkUrl of [
      "https://untrusted.example/downloads/android/xiaozhu-homework-v0.1.0.apk",
      "http://untrusted.example/downloads/android/xiaozhu-homework-v0.1.0.apk",
      "/downloads/android/different.apk",
      "/downloads/android/xiaozhu-homework-v0.1.0.apk?redirect=1",
      "/downloads/android/xiaozhu-homework-v0.1.0.apk#fragment",
      "/download",
    ]) {
      expect(parseAndroidDownloadManifest({ ...valid, apkUrl })).toEqual({
        available: false,
      });
    }
  });

  it("runs native back handlers by priority and stops at the first consumer", async () => {
    const calls: string[] = [];
    const unregisterLow = registerNativeBackHandler(() => {
      calls.push("low");
      return true;
    }, 10);
    const unregisterHigh = registerNativeBackHandler(() => {
      calls.push("high");
      return true;
    }, 100);

    await expect(runNativeBackHandlers()).resolves.toBe(true);
    expect(calls).toEqual(["high"]);
    unregisterHigh();
    unregisterLow();
  });
});
