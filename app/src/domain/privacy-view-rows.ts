import type { Tables } from "@/types/database.generated";

type PrivacyTable =
  | "project_members"
  | "task_collaborators"
  | "task_primary_handoffs"
  | "task_change_proposals"
  | "task_files"
  | "task_file_versions"
  | "file_upload_reservations"
  | "project_join_requests";

/**
 * PostgreSQL describes some LEFT JOIN privacy views as nullable even when
 * the selected fields are inherited from a NOT NULL base column. Verify the
 * real database contract at the boundary rather than lying in generated types.
 */
const REQUIRED: Record<PrivacyTable, readonly string[]> = {
  project_members: [
    "created_at",
    "id",
    "is_observer",
    "joined_at",
    "member_state",
    "project_id",
    "role",
    "version",
  ],
  task_collaborators: [
    "created_at",
    "id",
    "project_id",
    "state",
    "task_id",
    "updated_at",
    "version",
  ],
  task_primary_handoffs: [
    "created_at",
    "from_user_name_snapshot",
    "id",
    "project_id",
    "state",
    "task_id",
    "to_user_name_snapshot",
    "updated_at",
    "version",
  ],
  task_change_proposals: [
    "base_task_version",
    "created_at",
    "id",
    "new_deadline_at",
    "old_deadline_at",
    "project_id",
    "proposed_by",
    "required_confirmer_id",
    "state",
    "task_id",
    "updated_at",
    "version",
  ],
  task_files: [
    "created_at",
    "id",
    "logical_name",
    "project_id",
    "task_id",
    "updated_at",
    "version",
  ],
  task_file_versions: [
    "created_at",
    "file_id",
    "id",
    "mime_type",
    "object_path",
    "original_name",
    "project_id",
    "reservation_id",
    "sha256_hex",
    "size_bytes",
    "task_id",
    "version_number",
  ],
  file_upload_reservations: [
    "created_at",
    "declared_mime_type",
    "declared_size_bytes",
    "expires_at",
    "id",
    "mode",
    "object_path",
    "original_name",
    "project_id",
    "state",
    "task_id",
    "updated_at",
    "version",
  ],
  project_join_requests: [
    "created_at",
    "id",
    "invitation_id",
    "project_id",
    "state",
    "updated_at",
    "version",
  ],
};

export function checkedPrivacyRow<K extends PrivacyTable>(
  table: K,
  row: object,
): Tables<K> {
  for (const key of REQUIRED[table]) {
    if ((row as Record<string, unknown>)[key] == null) {
      throw new Error(`Invalid privacy view row: ${table}.${key}`);
    }
  }
  return row as Tables<K>;
}

export function checkedPrivacyRows<K extends PrivacyTable>(
  table: K,
  rows: object[] | null,
): Tables<K>[] {
  return (rows ?? []).map((row) => checkedPrivacyRow(table, row));
}
