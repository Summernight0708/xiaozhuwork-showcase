export interface EvidenceUrl {
  httpsUrl: string;
  host: string;
}

/** UI preflight only. SQL enforces the same narrow grammar without DNS or fetch. */
export function validateEvidenceUrl(value: string): EvidenceUrl | null {
  if (
    value.length > 2048 ||
    /[^\x21-\x7e]/.test(value) ||
    /[\\<>"`{}|^]/.test(value) ||
    /%(?![\da-f]{2})|%(?:0[\da-f]|1[\da-f]|7f|5c|25)/i.test(value)
  )
    return null;
  const match = /^https:\/\/([A-Za-z0-9.-]+)(?::443)?([/?#].*)?$/.exec(value);
  if (!match) return null;
  const host = match[1]!.toLowerCase();
  const labels = host.split(".");
  if (
    host.length > 253 ||
    labels.length < 2 ||
    labels.some(
      (label) => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label),
    ) ||
    !/^[a-z]{2,63}$/.test(labels[labels.length - 1]!) ||
    /(?:^|\.)(?:localhost|localdomain|local|internal|intranet|lan|home|corp|test|invalid|onion|arpa)$/.test(
      host,
    )
  )
    return null;
  return { httpsUrl: value, host };
}
