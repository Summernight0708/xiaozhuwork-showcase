const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EXACT_EMAIL = /^[^\s@%_]+@[^\s@%_]+\.[^\s@%_]+$/i;

export function normalizeExactAccountLookup(value: string): string {
  return value.trim();
}

export function isExactAccountLookup(value: string): boolean {
  const query = normalizeExactAccountLookup(value);
  if (query.length < 3 || query.length > 320) return false;
  return UUID.test(query) || EXACT_EMAIL.test(query);
}
