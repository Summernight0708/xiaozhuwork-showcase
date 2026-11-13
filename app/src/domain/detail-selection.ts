export function selectDetailRecord<T extends { id: string }>(
  records: readonly T[],
  requestedId: string | null,
) {
  if (requestedId) {
    return records.find((record) => record.id === requestedId) ?? null;
  }
  return records[0] ?? null;
}
