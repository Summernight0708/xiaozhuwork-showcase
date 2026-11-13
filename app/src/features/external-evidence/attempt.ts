import type {
  CreateEvidenceInput,
  EvidenceCommandResult,
  ExternalEvidenceRepository,
  RemoveEvidenceInput,
  UpdateEvidenceInput,
} from "./types";

type EvidenceOperation =
  | { kind: "create"; input: Omit<CreateEvidenceInput, "requestId"> }
  | { kind: "update"; input: Omit<UpdateEvidenceInput, "requestId"> }
  | { kind: "remove"; input: Omit<RemoveEvidenceInput, "requestId"> };

/**
 * Create once per explicit user action. Keep this attempt on transport failure;
 * retry execute() without changing its ID, draft or expected version. A resolved
 * STALE_VERSION ends this attempt: reload and ask the user to review their draft.
 */
export function prepareEvidenceAttempt(
  repository: ExternalEvidenceRepository,
  operation: EvidenceOperation,
  requestId: string = crypto.randomUUID(),
) {
  let send: () => Promise<EvidenceCommandResult>;
  switch (operation.kind) {
    case "create": {
      const input = Object.freeze({ ...operation.input, requestId });
      send = () => repository.create(input);
      break;
    }
    case "update": {
      const input = Object.freeze({ ...operation.input, requestId });
      send = () => repository.update(input);
      break;
    }
    case "remove": {
      const input = Object.freeze({ ...operation.input, requestId });
      send = () => repository.remove(input);
      break;
    }
  }
  let inFlight: Promise<EvidenceCommandResult> | null = null;
  let completed: EvidenceCommandResult | null = null;
  return Object.freeze({
    requestId,
    execute(): Promise<EvidenceCommandResult> {
      if (completed) return Promise.resolve(completed);
      if (!inFlight) {
        inFlight = Promise.resolve()
          .then(send)
          .then((result) => {
            completed = result;
            return result;
          })
          .finally(() => {
            inFlight = null;
          });
      }
      return inFlight;
    },
  });
}
