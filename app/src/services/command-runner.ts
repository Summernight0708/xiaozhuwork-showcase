import { CommandTransportError } from "@/lib/command-adapter";
import type { CommandResult } from "@/types/commands";

export interface RunIdempotentCommandOptions<T> {
  requestId: string;
  execute: (requestId: string) => Promise<CommandResult<T>>;
  maxTransportRetries?: number;
  onStaleVersion?: (currentVersion?: number) => Promise<void> | void;
}

export async function runIdempotentCommand<T>(
  options: RunIdempotentCommandOptions<T>,
): Promise<CommandResult<T>> {
  const maxTransportRetries = options.maxTransportRetries ?? 0;
  let attempt = 0;

  while (true) {
    try {
      const result = await options.execute(options.requestId);
      if (!result.ok && result.code === "STALE_VERSION") {
        await options.onStaleVersion?.(result.currentVersion);
      }
      return result;
    } catch (error) {
      if (
        error instanceof CommandTransportError &&
        error.retryable &&
        attempt < maxTransportRetries
      ) {
        attempt += 1;
        continue;
      }
      throw error;
    }
  }
}
