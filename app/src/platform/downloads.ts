import { Capacitor, registerPlugin } from "@capacitor/core";

interface XiaozhuDownloadPlugin {
  downloadUrl(options: {
    url: string;
    fileName: string;
    mimeType?: string;
  }): Promise<{ downloadId: string }>;
  beginBlobDownload(options: {
    fileName: string;
    mimeType?: string;
    sizeBytes: number;
  }): Promise<{ transferId: string }>;
  appendBlobChunk(options: {
    transferId: string;
    base64: string;
  }): Promise<void>;
  finishBlobDownload(options: { transferId: string }): Promise<{ uri: string }>;
  cancelBlobDownload(options: { transferId: string }): Promise<void>;
}

const NativeDownload = registerPlugin<XiaozhuDownloadPlugin>("XiaozhuDownload");
const BLOB_CHUNK_BYTES = 256 * 1024;

export interface DownloadResult {
  native: boolean;
  destination: "browser" | "downloads";
}

export function isNativeAndroid(): boolean {
  return Capacitor.isNativePlatform() && Capacitor.getPlatform() === "android";
}

export function safeDownloadFileName(input: string): string {
  const cleaned = Array.from(input, (character) => {
    const code = character.charCodeAt(0);
    if (code <= 31 || `\\/:*?"<>|`.includes(character)) return "_";
    return character;
  })
    .join("")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\.+/, "")
    .slice(0, 180);
  return cleaned || "download";
}

function assertNetworkUrl(input: string): URL {
  const url = new URL(input, window.location.href);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error("Only HTTP(S) download URLs are allowed");
  }
  return url;
}

function clickWebDownload(url: string, fileName?: string): void {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.rel = "noopener";
  if (fileName) anchor.download = safeDownloadFileName(fileName);
  else anchor.target = "_blank";
  anchor.click();
}

export async function downloadUrl(options: {
  url: string;
  fileName?: string;
  mimeType?: string;
}): Promise<DownloadResult> {
  if (isNativeAndroid()) {
    const url = assertNetworkUrl(options.url);
    await NativeDownload.downloadUrl({
      url: url.toString(),
      fileName: safeDownloadFileName(options.fileName ?? "download"),
      mimeType: options.mimeType,
    });
    return { native: true, destination: "downloads" };
  }

  clickWebDownload(options.url, options.fileName);
  return { native: false, destination: "browser" };
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const stride = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += stride) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + stride));
  }
  return btoa(binary);
}

export async function downloadBlob(options: {
  blob: Blob;
  fileName: string;
  mimeType?: string;
}): Promise<DownloadResult> {
  const fileName = safeDownloadFileName(options.fileName);
  if (!isNativeAndroid()) {
    const objectUrl = URL.createObjectURL(options.blob);
    clickWebDownload(objectUrl, fileName);
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 30_000);
    return { native: false, destination: "browser" };
  }

  const { transferId } = await NativeDownload.beginBlobDownload({
    fileName,
    mimeType: (options.mimeType ?? options.blob.type) || undefined,
    sizeBytes: options.blob.size,
  });

  try {
    for (
      let offset = 0;
      offset < options.blob.size;
      offset += BLOB_CHUNK_BYTES
    ) {
      const chunk = new Uint8Array(
        await options.blob
          .slice(offset, offset + BLOB_CHUNK_BYTES)
          .arrayBuffer(),
      );
      await NativeDownload.appendBlobChunk({
        transferId,
        base64: bytesToBase64(chunk),
      });
    }
    await NativeDownload.finishBlobDownload({ transferId });
  } catch (error) {
    await NativeDownload.cancelBlobDownload({ transferId }).catch(
      () => undefined,
    );
    throw error;
  }

  return { native: true, destination: "downloads" };
}
