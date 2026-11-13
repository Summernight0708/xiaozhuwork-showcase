import { describe, expect, test } from "vitest";
import { validateEvidenceUrl } from "@/features/external-evidence/url";

describe("external evidence URL boundary", () => {
  test.each([
    "https://docs.google.com/document/d/abc/edit",
    "https://GitHub.COM/team/repo?tab=readme#section",
    "https://pan.baidu.com/s/abc?pwd=abcd",
    "https://example.org:443/a%20document",
  ])("accepts public HTTPS metadata: %s", (url) => {
    expect(validateEvidenceUrl(url)?.host).toBe(new URL(url).hostname);
    expect(validateEvidenceUrl(url)?.httpsUrl).toBe(url);
  });

  test.each([
    "http://example.org",
    "file:///etc/passwd",
    "javascript:alert(1)",
    "https://user:password@example.org",
    "https://example.org@localhost",
    "https://localhost",
    "https://api.localhost",
    "https://host.local",
    "https://host.internal",
    "https://host.lan",
    "https://host.home.arpa",
    "https://host",
    "https://127.0.0.1",
    "https://10.0.0.1",
    "https://169.254.169.254",
    "https://192.168.1.1",
    "https://100.64.0.1",
    "https://0.0.0.0",
    "https://192.0.2.1",
    "https://224.0.0.1",
    "https://8.8.8.8",
    "https://2130706433",
    "https://0x7f000001",
    "https://0177.0.0.1",
    "https://127.1",
    "https://0x7f.0.0.1",
    "https://[::1]",
    "https://[::ffff:127.0.0.1]",
    "https://[2001:4860::8888]",
    "https://%31%32%37.0.0.1",
    "https://example.org\\@localhost",
    "https://example.org.",
    "https://example..org",
    "https://-example.org",
    "https://example.org:444",
    "https://example.org:0443",
    "https://example.org\n",
    " https://example.org",
    "HTTPS://example.org",
    "https://example.org/%0aHeader",
    "https://example.org/%250d",
    "https://example.org/%5cfoo",
    "https://example.org/%zz",
    "https://ｅxample.org",
    "https://example.123",
    "https://example.test",
    "https://example.invalid",
    "https://localhost.localdomain",
    `https://example.org/${"x".repeat(2048)}`,
  ])("rejects ambiguous or non-public URL: %s", (url) => {
    expect(validateEvidenceUrl(url)).toBeNull();
  });
});
