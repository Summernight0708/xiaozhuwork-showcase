import { AppLauncher } from "@capacitor/app-launcher";
import { Browser } from "@capacitor/browser";

import { isNativeAndroid } from "@/platform/downloads";

export type ExternalUrlKind = "internal" | "browser" | "app" | "blocked";

export function classifyExternalUrl(
  input: string,
  origin = window.location.origin,
): ExternalUrlKind {
  let url: URL;
  try {
    url = new URL(input, origin);
  } catch {
    return "blocked";
  }

  if (url.protocol === "http:" || url.protocol === "https:") {
    return url.origin === origin ? "internal" : "browser";
  }
  if (["mailto:", "tel:", "webcal:"].includes(url.protocol)) return "app";
  return "blocked";
}

export async function openExternalUrl(input: string): Promise<boolean> {
  const kind = classifyExternalUrl(input);
  if (kind === "blocked") return false;
  if (kind === "internal") {
    window.location.assign(input);
    return true;
  }

  if (!isNativeAndroid()) {
    if (kind === "browser") window.open(input, "_blank", "noopener,noreferrer");
    else window.location.assign(input);
    return true;
  }

  if (kind === "browser") await Browser.open({ url: input });
  else await AppLauncher.openUrl({ url: input });
  return true;
}

export function installExternalLinkGuard(): () => void {
  if (!isNativeAndroid()) return () => undefined;

  const handleClick = (event: MouseEvent) => {
    if (event.defaultPrevented || event.button !== 0) return;
    const target = event.target;
    const anchor = target instanceof Element ? target.closest("a[href]") : null;
    if (
      !(anchor instanceof HTMLAnchorElement) ||
      anchor.hasAttribute("download")
    )
      return;
    const href = anchor.getAttribute("href");
    if (!href) return;
    const kind = classifyExternalUrl(href);
    if (kind === "internal") return;
    event.preventDefault();
    if (kind !== "blocked") void openExternalUrl(anchor.href);
  };

  document.addEventListener("click", handleClick, true);
  return () => document.removeEventListener("click", handleClick, true);
}
