import { describe, expect, it } from "vitest";

import {
  createSupabaseClient,
  validateSupabaseEnvironment,
} from "@/lib/supabase";

describe("Supabase environment validation", () => {
  it("reports the URL and public key requirement when both key forms are missing", () => {
    expect(
      validateSupabaseEnvironment({
        VITE_SUPABASE_URL: "",
        VITE_SUPABASE_PUBLISHABLE_KEY: undefined,
        VITE_SUPABASE_ANON_KEY: undefined,
      }),
    ).toEqual({
      configured: false,
      missing: [
        "VITE_SUPABASE_URL",
        "VITE_SUPABASE_PUBLISHABLE_KEY / VITE_SUPABASE_ANON_KEY",
      ],
    });
  });

  it("prefers the current publishable-key configuration", () => {
    expect(
      validateSupabaseEnvironment({
        VITE_SUPABASE_URL: "https://example.supabase.co",
        VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_example",
        VITE_SUPABASE_ANON_KEY: undefined,
      }),
    ).toEqual({ configured: true, missing: [] });
  });

  it("keeps the legacy anon key as a local compatibility fallback", () => {
    expect(
      validateSupabaseEnvironment({
        VITE_SUPABASE_URL: "https://example.supabase.co",
        VITE_SUPABASE_PUBLISHABLE_KEY: undefined,
        VITE_SUPABASE_ANON_KEY: "legacy-anon-key",
      }),
    ).toEqual({ configured: true, missing: [] });
  });

  it("refuses to create a client from incomplete public configuration", () => {
    expect(() =>
      createSupabaseClient({
        VITE_SUPABASE_URL: "",
        VITE_SUPABASE_PUBLISHABLE_KEY: "",
        VITE_SUPABASE_ANON_KEY: "",
      }),
    ).toThrow(
      "VITE_SUPABASE_URL、VITE_SUPABASE_PUBLISHABLE_KEY / VITE_SUPABASE_ANON_KEY",
    );
  });
});
