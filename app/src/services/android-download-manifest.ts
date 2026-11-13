export interface AndroidDownloadAvailableManifest {
  available: true;
  versionName: string;
  versionCode: number;
  apkUrl: string;
  sha256: string;
  sizeBytes: number;
  minAndroid: number;
  publishedAt: string;
}

export interface AndroidDownloadUnavailableManifest {
  available: false;
}

export type AndroidDownloadManifest =
  AndroidDownloadAvailableManifest | AndroidDownloadUnavailableManifest;

const unavailable: AndroidDownloadUnavailableManifest = { available: false };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

export function parseAndroidDownloadManifest(
  value: unknown,
): AndroidDownloadManifest {
  if (!isRecord(value) || value.available === false) return unavailable;

  const versionName = value.versionName;
  const versionCode = value.versionCode;
  const apkUrl = value.apkUrl;
  const sha256 = value.sha256;
  const sizeBytes = value.sizeBytes;
  const minAndroid = value.minAndroid;
  const publishedAt = value.publishedAt;

  if (
    typeof versionName !== "string" ||
    !versionName.trim() ||
    typeof versionCode !== "number" ||
    !Number.isSafeInteger(versionCode) ||
    versionCode <= 0 ||
    typeof apkUrl !== "string" ||
    !apkUrl.trim() ||
    typeof sha256 !== "string" ||
    !/^[a-f0-9]{64}$/i.test(sha256) ||
    typeof sizeBytes !== "number" ||
    !Number.isSafeInteger(sizeBytes) ||
    sizeBytes <= 0 ||
    typeof minAndroid !== "number" ||
    !Number.isFinite(minAndroid) ||
    minAndroid <= 0 ||
    typeof publishedAt !== "string" ||
    Number.isNaN(Date.parse(publishedAt))
  ) {
    return unavailable;
  }

  let resolved: URL;
  try {
    resolved = new URL(apkUrl, window.location.origin);
  } catch {
    return unavailable;
  }
  const isLocalDevelopment = ["localhost", "127.0.0.1", "[::1]"].includes(
    window.location.hostname,
  );
  if (
    resolved.origin !== window.location.origin ||
    (resolved.protocol !== "https:" &&
      !(isLocalDevelopment && resolved.protocol === "http:")) ||
    resolved.pathname !==
      `/downloads/android/xiaozhu-homework-v${versionName}.apk` ||
    resolved.search ||
    resolved.hash
  )
    return unavailable;

  return {
    available: true,
    versionName: versionName.trim(),
    versionCode,
    apkUrl: resolved.toString(),
    sha256: sha256.toLowerCase(),
    sizeBytes,
    minAndroid,
    publishedAt,
  };
}

export async function fetchAndroidDownloadManifest(
  fetcher: typeof fetch = fetch,
): Promise<AndroidDownloadManifest> {
  try {
    const response = await fetcher("/downloads/android/latest.json", {
      cache: "no-store",
      headers: { accept: "application/json" },
    });
    if (!response.ok) return unavailable;
    return parseAndroidDownloadManifest(await response.json());
  } catch {
    return unavailable;
  }
}
