export type NativeBackHandler = () => boolean | Promise<boolean>;

interface RegisteredHandler {
  id: number;
  priority: number;
  handler: NativeBackHandler;
}

const handlers: RegisteredHandler[] = [];
let nextId = 1;

export function registerNativeBackHandler(
  handler: NativeBackHandler,
  priority = 0,
): () => void {
  const entry = { id: nextId++, priority, handler };
  handlers.push(entry);
  return () => {
    const index = handlers.findIndex((candidate) => candidate.id === entry.id);
    if (index >= 0) handlers.splice(index, 1);
  };
}

export async function runNativeBackHandlers(): Promise<boolean> {
  const snapshot = [...handlers].sort(
    (left, right) => right.priority - left.priority || right.id - left.id,
  );
  for (const entry of snapshot) {
    if (await entry.handler()) return true;
  }
  return false;
}
