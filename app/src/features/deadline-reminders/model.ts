export const DEFAULT_REMINDER_OFFSETS = [86_400, 7_200] as const;
export const MAX_REMINDER_OFFSETS = 6;
export const MIN_OFFSET_SECONDS = 300;
export const MAX_OFFSET_SECONDS = 14 * 24 * 60 * 60;

export function normalizeReminderOffsets(values: readonly number[]): number[] {
  if (values.length < 1 || values.length > MAX_REMINDER_OFFSETS) {
    throw new Error("请保留 1 至 6 个提醒节点");
  }
  const offsets = [...values];
  for (const value of offsets) {
    if (
      !Number.isInteger(value) ||
      value < MIN_OFFSET_SECONDS ||
      value > MAX_OFFSET_SECONDS ||
      value % 60 !== 0
    ) {
      throw new Error("提醒节点必须是 5 分钟至 14 天之间的整分钟数");
    }
  }
  if (new Set(offsets).size !== offsets.length) {
    throw new Error("提醒节点不能重复");
  }
  return offsets.sort((a, b) => b - a);
}

export function displayReminderOffset(seconds: number): string {
  if (seconds % 86_400 === 0) return `${seconds / 86_400} 天前`;
  if (seconds % 3_600 === 0) return `${seconds / 3_600} 小时前`;
  return `${seconds / 60} 分钟前`;
}

export interface ReminderPreferences {
  project_id: string;
  task_id: string;
  recipient_id: string;
  enabled: boolean;
  offsets_seconds: number[];
  version: number;
}

export interface ReminderCommandResult {
  ok: boolean;
  code?: string;
  currentVersion?: number;
  data?: {
    preferenceVersion?: number;
    recipientCount?: number;
    exceptionKind?: string;
  };
  replayed?: boolean;
}
