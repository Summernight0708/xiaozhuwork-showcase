export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      account_entitlement_audit: {
        Row: {
          action: string;
          created_at: string;
          entitlement_version: number;
          expires_at: string;
          grant_source: string;
          granted_at: string;
          granted_by: string | null;
          id: number;
          note: string | null;
          plan: string;
          request_id: string | null;
          starts_at: string;
          status: string;
          user_id: string;
        };
        Insert: {
          action: string;
          created_at?: string;
          entitlement_version: number;
          expires_at: string;
          grant_source: string;
          granted_at: string;
          granted_by?: string | null;
          id?: number;
          note?: string | null;
          plan: string;
          request_id?: string | null;
          starts_at: string;
          status: string;
          user_id: string;
        };
        Update: {
          action?: string;
          created_at?: string;
          entitlement_version?: number;
          expires_at?: string;
          grant_source?: string;
          granted_at?: string;
          granted_by?: string | null;
          id?: number;
          note?: string | null;
          plan?: string;
          request_id?: string | null;
          starts_at?: string;
          status?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      account_entitlements: {
        Row: {
          created_at: string;
          expires_at: string;
          grant_source: string;
          granted_at: string;
          granted_by: string | null;
          note: string | null;
          plan: string;
          starts_at: string;
          status: string;
          updated_at: string;
          user_id: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          expires_at: string;
          grant_source: string;
          granted_at?: string;
          granted_by?: string | null;
          note?: string | null;
          plan: string;
          starts_at: string;
          status: string;
          updated_at?: string;
          user_id: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          expires_at?: string;
          grant_source?: string;
          granted_at?: string;
          granted_by?: string | null;
          note?: string | null;
          plan?: string;
          starts_at?: string;
          status?: string;
          updated_at?: string;
          user_id?: string;
          version?: number;
        };
        Relationships: [];
      };
      account_lifecycle_requests: {
        Row: {
          auth_revoked_at: string | null;
          auth_soft_deleted_at: string | null;
          cancel_until: string;
          canceled_at: string | null;
          generation: number;
          redacted_at: string | null;
          requested_at: string;
          state: string;
          updated_at: string;
          user_id: string;
          version: number;
        };
        Insert: {
          auth_revoked_at?: string | null;
          auth_soft_deleted_at?: string | null;
          cancel_until: string;
          canceled_at?: string | null;
          generation: number;
          redacted_at?: string | null;
          requested_at: string;
          state: string;
          updated_at?: string;
          user_id: string;
          version: number;
        };
        Update: {
          auth_revoked_at?: string | null;
          auth_soft_deleted_at?: string | null;
          cancel_until?: string;
          canceled_at?: string | null;
          generation?: number;
          redacted_at?: string | null;
          requested_at?: string;
          state?: string;
          updated_at?: string;
          user_id?: string;
          version?: number;
        };
        Relationships: [];
      };
      business_events: {
        Row: {
          actor_id: string | null;
          command_request_id: string | null;
          created_at: string;
          entity_id: string | null;
          entity_type: string;
          event_data: NonNullable<Json>;
          event_seq: number | null;
          event_type: string;
          id: number;
          project_id: string;
          request_id: string | null;
        };
        Insert: {
          actor_id?: string | null;
          command_request_id?: string | null;
          created_at?: string;
          entity_id?: string | null;
          entity_type: string;
          event_data?: NonNullable<Json>;
          event_seq?: number | null;
          event_type: string;
          id?: never;
          project_id: string;
          request_id?: string | null;
        };
        Update: {
          actor_id?: string | null;
          command_request_id?: string | null;
          created_at?: string;
          entity_id?: string | null;
          entity_type?: string;
          event_data?: NonNullable<Json>;
          event_seq?: number | null;
          event_type?: string;
          id?: never;
          project_id?: string;
          request_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "business_events_command_request_id_fkey";
            columns: ["command_request_id"];
            isOneToOne: false;
            referencedRelation: "command_requests";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "business_events_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      command_requests: {
        Row: {
          account_id: string | null;
          actor_id: string | null;
          command_name: string;
          completed_at: string | null;
          created_at: string;
          id: string;
          payload_hash: string;
          project_id: string | null;
          request_id: string;
          result: Json | null;
          resulting_entity_id: string | null;
          resulting_entity_type: string | null;
          resulting_entity_version: number | null;
          state: string;
          updated_at: string;
        };
        Insert: {
          account_id?: string | null;
          actor_id?: string | null;
          command_name: string;
          completed_at?: string | null;
          created_at?: string;
          id?: string;
          payload_hash: string;
          project_id?: string | null;
          request_id: string;
          result?: Json | null;
          resulting_entity_id?: string | null;
          resulting_entity_type?: string | null;
          resulting_entity_version?: number | null;
          state?: string;
          updated_at?: string;
        };
        Update: {
          account_id?: string | null;
          actor_id?: string | null;
          command_name?: string;
          completed_at?: string | null;
          created_at?: string;
          id?: string;
          payload_hash?: string;
          project_id?: string | null;
          request_id?: string;
          result?: Json | null;
          resulting_entity_id?: string | null;
          resulting_entity_type?: string | null;
          resulting_entity_version?: number | null;
          state?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "command_requests_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      contribution_appeal_votes: {
        Row: {
          appeal_id: string;
          created_at: string;
          id: string;
          project_id: string;
          resolution: NonNullable<Json>;
          voter_id: string | null;
        };
        Insert: {
          appeal_id: string;
          created_at?: string;
          id?: string;
          project_id: string;
          resolution: NonNullable<Json>;
          voter_id?: string | null;
        };
        Update: {
          appeal_id?: string;
          created_at?: string;
          id?: string;
          project_id?: string;
          resolution?: NonNullable<Json>;
          voter_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_appeal_votes_appeal_id_fkey";
            columns: ["appeal_id"];
            isOneToOne: false;
            referencedRelation: "contribution_penalty_appeals";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_appeal_votes_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      contribution_confirmations: {
        Row: {
          confirmed_at: string;
          id: string;
          project_id: string;
          report_id: string;
          user_id: string | null;
        };
        Insert: {
          confirmed_at?: string;
          id?: string;
          project_id: string;
          report_id: string;
          user_id?: string | null;
        };
        Update: {
          confirmed_at?: string;
          id?: string;
          project_id?: string;
          report_id?: string;
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_confirmations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_confirmations_project_report_fkey";
            columns: ["project_id", "report_id"];
            isOneToOne: false;
            referencedRelation: "contribution_reports";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      contribution_items: {
        Row: {
          completed_at_snapshot: string;
          contribution_value: number | null;
          created_at: string;
          id: string;
          member_display_name_snapshot: string;
          member_user_id: string | null;
          project_id: string;
          report_id: string;
          share: number;
          task_id: string;
          task_title_snapshot: string;
          task_weight: number | null;
        };
        Insert: {
          completed_at_snapshot: string;
          contribution_value?: number | null;
          created_at?: string;
          id?: string;
          member_display_name_snapshot: string;
          member_user_id?: string | null;
          project_id: string;
          report_id: string;
          share: number;
          task_id: string;
          task_title_snapshot: string;
          task_weight?: number | null;
        };
        Update: {
          completed_at_snapshot?: string;
          contribution_value?: number | null;
          created_at?: string;
          id?: string;
          member_display_name_snapshot?: string;
          member_user_id?: string | null;
          project_id?: string;
          report_id?: string;
          share?: number;
          task_id?: string;
          task_title_snapshot?: string;
          task_weight?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_items_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_items_project_report_fkey";
            columns: ["project_id", "report_id"];
            isOneToOne: false;
            referencedRelation: "contribution_reports";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "contribution_items_project_task_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "contribution_items_project_task_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      contribution_penalties: {
        Row: {
          amount: number;
          assessed_at: string;
          base_amount: number;
          delay_seconds: number;
          duration_seconds: number;
          event_snapshot: NonNullable<Json>;
          id: string;
          kind: string;
          member_key: string;
          member_user_id: string | null;
          policy_version: number;
          project_id: string;
          rate: number;
          responsibility_epoch_id: string;
          source_event_id: number;
          source_occurrence_key: string;
          task_id: string;
        };
        Insert: {
          amount: number;
          assessed_at?: string;
          base_amount: number;
          delay_seconds: number;
          duration_seconds: number;
          event_snapshot: NonNullable<Json>;
          id?: string;
          kind: string;
          member_key: string;
          member_user_id?: string | null;
          policy_version: number;
          project_id: string;
          rate: number;
          responsibility_epoch_id: string;
          source_event_id: number;
          source_occurrence_key: string;
          task_id: string;
        };
        Update: {
          amount?: number;
          assessed_at?: string;
          base_amount?: number;
          delay_seconds?: number;
          duration_seconds?: number;
          event_snapshot?: NonNullable<Json>;
          id?: string;
          kind?: string;
          member_key?: string;
          member_user_id?: string | null;
          policy_version?: number;
          project_id?: string;
          rate?: number;
          responsibility_epoch_id?: string;
          source_event_id?: number;
          source_occurrence_key?: string;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_penalties_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_penalties_source_event_id_fkey";
            columns: ["source_event_id"];
            isOneToOne: false;
            referencedRelation: "business_events";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_penalties_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["task_id"];
          },
          {
            foreignKeyName: "contribution_penalties_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      contribution_penalty_adjustments: {
        Row: {
          appeal_id: string;
          created_at: string;
          id: string;
          member_user_id: string | null;
          penalty_id: string;
          previous_amount: number;
          project_id: string;
          resulting_amount: number;
          signed_delta: number;
        };
        Insert: {
          appeal_id: string;
          created_at?: string;
          id?: string;
          member_user_id?: string | null;
          penalty_id: string;
          previous_amount: number;
          project_id: string;
          resulting_amount: number;
          signed_delta: number;
        };
        Update: {
          appeal_id?: string;
          created_at?: string;
          id?: string;
          member_user_id?: string | null;
          penalty_id?: string;
          previous_amount?: number;
          project_id?: string;
          resulting_amount?: number;
          signed_delta?: number;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_penalty_adjustments_appeal_id_fkey";
            columns: ["appeal_id"];
            isOneToOne: true;
            referencedRelation: "contribution_penalty_appeals";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_penalty_adjustments_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_penalty_adjustments_project_id_penalty_id_fkey";
            columns: ["project_id", "penalty_id"];
            isOneToOne: false;
            referencedRelation: "contribution_penalties";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      contribution_penalty_appeals: {
        Row: {
          appellant_user_id: string | null;
          id: string;
          opened_at: string;
          penalty_id: string;
          project_id: string;
          reason: string;
          resolution: Json | null;
          resolved_at: string | null;
          round: number;
          status: string;
          version: number;
        };
        Insert: {
          appellant_user_id?: string | null;
          id?: string;
          opened_at?: string;
          penalty_id: string;
          project_id: string;
          reason: string;
          resolution?: Json | null;
          resolved_at?: string | null;
          round: number;
          status?: string;
          version?: number;
        };
        Update: {
          appellant_user_id?: string | null;
          id?: string;
          opened_at?: string;
          penalty_id?: string;
          project_id?: string;
          reason?: string;
          resolution?: Json | null;
          resolved_at?: string | null;
          round?: number;
          status?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_penalty_appeals_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_penalty_appeals_project_id_penalty_id_fkey";
            columns: ["project_id", "penalty_id"];
            isOneToOne: false;
            referencedRelation: "contribution_penalties";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      contribution_report_member_ledger_entries: {
        Row: {
          captured_at: string;
          completed_at_snapshot: string;
          entry_id: string;
          entry_type: string;
          id: string;
          member_name_snapshot: string;
          member_user_id: string | null;
          project_id: string;
          report_id: string;
          share: number;
          signed_amount: number;
          task_id: string;
          task_title_snapshot: string;
          task_weight: number | null;
        };
        Insert: {
          captured_at?: string;
          completed_at_snapshot: string;
          entry_id: string;
          entry_type: string;
          id?: string;
          member_name_snapshot: string;
          member_user_id?: string | null;
          project_id: string;
          report_id: string;
          share: number;
          signed_amount: number;
          task_id: string;
          task_title_snapshot: string;
          task_weight?: number | null;
        };
        Update: {
          captured_at?: string;
          completed_at_snapshot?: string;
          entry_id?: string;
          entry_type?: string;
          id?: string;
          member_name_snapshot?: string;
          member_user_id?: string | null;
          project_id?: string;
          report_id?: string;
          share?: number;
          signed_amount?: number;
          task_id?: string;
          task_title_snapshot?: string;
          task_weight?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_report_member_ledger_entries_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_report_member_ledger_entries_report_id_fkey";
            columns: ["report_id"];
            isOneToOne: false;
            referencedRelation: "contribution_reports";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contribution_report_member_ledger_entries_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["task_id"];
          },
          {
            foreignKeyName: "contribution_report_member_ledger_entries_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      contribution_reports: {
        Row: {
          contribution_mode: string;
          created_at: string;
          created_by: string | null;
          eligible_member_count: number;
          formalized_at: string | null;
          id: string;
          project_id: string;
          required_confirmation_count: number;
          snapshot_basis: string;
          source_project_version: number;
          state: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          contribution_mode: string;
          created_at?: string;
          created_by?: string | null;
          eligible_member_count: number;
          formalized_at?: string | null;
          id?: string;
          project_id: string;
          required_confirmation_count: number;
          snapshot_basis?: string;
          source_project_version: number;
          state?: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          contribution_mode?: string;
          created_at?: string;
          created_by?: string | null;
          eligible_member_count?: number;
          formalized_at?: string | null;
          id?: string;
          project_id?: string;
          required_confirmation_count?: number;
          snapshot_basis?: string;
          source_project_version?: number;
          state?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "contribution_reports_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: true;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      file_upload_reservations: {
        Row: {
          actor_id: string | null;
          created_at: string;
          declared_mime_type: string;
          declared_size_bytes: number;
          expires_at: string;
          id: string;
          mode: string;
          object_path: string;
          original_name: string;
          project_id: string;
          rejection_code: string | null;
          reserved_envelope_bytes: number | null;
          state: string;
          target_file_id: string | null;
          target_file_version: number | null;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          actor_id?: string | null;
          created_at?: string;
          declared_mime_type: string;
          declared_size_bytes: number;
          expires_at: string;
          id?: string;
          mode: string;
          object_path: string;
          original_name: string;
          project_id: string;
          rejection_code?: string | null;
          reserved_envelope_bytes?: number | null;
          state?: string;
          target_file_id?: string | null;
          target_file_version?: number | null;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          actor_id?: string | null;
          created_at?: string;
          declared_mime_type?: string;
          declared_size_bytes?: number;
          expires_at?: string;
          id?: string;
          mode?: string;
          object_path?: string;
          original_name?: string;
          project_id?: string;
          rejection_code?: string | null;
          reserved_envelope_bytes?: number | null;
          state?: string;
          target_file_id?: string | null;
          target_file_version?: number | null;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "file_upload_reservations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "file_upload_reservations_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "file_upload_reservations_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "file_upload_reservations_target_file_fkey";
            columns: ["project_id", "task_id", "target_file_id"];
            isOneToOne: false;
            referencedRelation: "task_files";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "file_upload_reservations_target_file_fkey";
            columns: ["project_id", "task_id", "target_file_id"];
            isOneToOne: false;
            referencedRelation: "task_files_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
        ];
      };
      file_version_withdrawals: {
        Row: {
          file_id: string;
          file_version_id: string;
          id: string;
          original_path: string;
          original_path_sha256: string;
          project_id: string;
          quarantine_path: string;
          reason: string;
          request_command_id: string;
          request_id: string;
          requested_at: string;
          requested_by: string | null;
          revoked_at: string | null;
          state: string;
          task_id: string;
          version: number;
        };
        Insert: {
          file_id: string;
          file_version_id: string;
          id?: string;
          original_path: string;
          original_path_sha256: string;
          project_id: string;
          quarantine_path: string;
          reason: string;
          request_command_id: string;
          request_id: string;
          requested_at?: string;
          requested_by?: string | null;
          revoked_at?: string | null;
          state?: string;
          task_id: string;
          version?: number;
        };
        Update: {
          file_id?: string;
          file_version_id?: string;
          id?: string;
          original_path?: string;
          original_path_sha256?: string;
          project_id?: string;
          quarantine_path?: string;
          reason?: string;
          request_command_id?: string;
          request_id?: string;
          requested_at?: string;
          requested_by?: string | null;
          revoked_at?: string | null;
          state?: string;
          task_id?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "file_version_withdrawals_project_id_task_id_file_version_i_fkey";
            columns: ["project_id", "task_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "file_version_withdrawals_project_id_task_id_file_version_i_fkey";
            columns: ["project_id", "task_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "file_version_withdrawals_request_command_id_fkey";
            columns: ["request_command_id"];
            isOneToOne: false;
            referencedRelation: "command_requests";
            referencedColumns: ["id"];
          },
        ];
      };
      notifications: {
        Row: {
          created_at: string;
          entity_id: string | null;
          entity_type: string | null;
          hidden_at: string | null;
          id: string;
          message: string;
          notification_type: string;
          project_id: string | null;
          read_at: string | null;
          recipient_id: string;
          source_event_id: number | null;
          title: string;
        };
        Insert: {
          created_at?: string;
          entity_id?: string | null;
          entity_type?: string | null;
          hidden_at?: string | null;
          id?: string;
          message: string;
          notification_type: string;
          project_id?: string | null;
          read_at?: string | null;
          recipient_id: string;
          source_event_id?: number | null;
          title: string;
        };
        Update: {
          created_at?: string;
          entity_id?: string | null;
          entity_type?: string | null;
          hidden_at?: string | null;
          id?: string;
          message?: string;
          notification_type?: string;
          project_id?: string | null;
          read_at?: string | null;
          recipient_id?: string;
          source_event_id?: number | null;
          title?: string;
        };
        Relationships: [
          {
            foreignKeyName: "notifications_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_source_event_id_fkey";
            columns: ["source_event_id"];
            isOneToOne: false;
            referencedRelation: "business_events";
            referencedColumns: ["id"];
          },
        ];
      };
      penalty_event_consumptions: {
        Row: {
          created_at: string;
          disposition: string;
          id: string;
          kind: string;
          member_key: string;
          project_id: string;
          reason: string | null;
          source_event_id: number;
        };
        Insert: {
          created_at?: string;
          disposition: string;
          id?: string;
          kind: string;
          member_key: string;
          project_id: string;
          reason?: string | null;
          source_event_id: number;
        };
        Update: {
          created_at?: string;
          disposition?: string;
          id?: string;
          kind?: string;
          member_key?: string;
          project_id?: string;
          reason?: string | null;
          source_event_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: "penalty_event_consumptions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "penalty_event_consumptions_source_event_id_fkey";
            columns: ["source_event_id"];
            isOneToOne: false;
            referencedRelation: "business_events";
            referencedColumns: ["id"];
          },
        ];
      };
      profiles: {
        Row: {
          created_at: string;
          display_name: string | null;
          id: string;
          real_name: string | null;
          student_number: string | null;
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          display_name?: string | null;
          id: string;
          real_name?: string | null;
          student_number?: string | null;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          display_name?: string | null;
          id?: string;
          real_name?: string | null;
          student_number?: string | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      project_archive_cycles: {
        Row: {
          archive_reason: string;
          archived_at: string;
          archived_by: string | null;
          archived_project_version: number;
          created_at: string;
          generation: number;
          id: string;
          project_id: string;
          recovery_until: string;
          restored_at: string | null;
          restored_by: string | null;
          restored_project_version: number | null;
          retain_until: string;
          version: number;
        };
        Insert: {
          archive_reason: string;
          archived_at: string;
          archived_by?: string | null;
          archived_project_version: number;
          created_at?: string;
          generation: number;
          id?: string;
          project_id: string;
          recovery_until: string;
          restored_at?: string | null;
          restored_by?: string | null;
          restored_project_version?: number | null;
          retain_until: string;
          version?: number;
        };
        Update: {
          archive_reason?: string;
          archived_at?: string;
          archived_by?: string | null;
          archived_project_version?: number;
          created_at?: string;
          generation?: number;
          id?: string;
          project_id?: string;
          recovery_until?: string;
          restored_at?: string | null;
          restored_by?: string | null;
          restored_project_version?: number | null;
          retain_until?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_archive_cycles_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_archive_retention_extensions: {
        Row: {
          actor_id: string | null;
          additional_days: number;
          created_at: string;
          cycle_id: string;
          id: string;
          new_retain_until: string;
          previous_retain_until: string;
          project_id: string;
          project_version: number;
          request_id: string;
        };
        Insert: {
          actor_id?: string | null;
          additional_days: number;
          created_at?: string;
          cycle_id: string;
          id?: string;
          new_retain_until: string;
          previous_retain_until: string;
          project_id: string;
          project_version: number;
          request_id: string;
        };
        Update: {
          actor_id?: string | null;
          additional_days?: number;
          created_at?: string;
          cycle_id?: string;
          id?: string;
          new_retain_until?: string;
          previous_retain_until?: string;
          project_id?: string;
          project_version?: number;
          request_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_archive_retention_extensions_cycle_id_fkey";
            columns: ["cycle_id"];
            isOneToOne: false;
            referencedRelation: "project_archive_cycles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_archive_retention_extensions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_calendar_subscriptions: {
        Row: {
          created_at: string;
          expires_at: string;
          id: string;
          issuer_membership_id: string;
          issuer_user_id: string;
          project_id: string;
          request_id: string;
          revoked_at: string | null;
          show_titles: boolean;
          token_hash: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          expires_at: string;
          id?: string;
          issuer_membership_id: string;
          issuer_user_id: string;
          project_id: string;
          request_id: string;
          revoked_at?: string | null;
          show_titles?: boolean;
          token_hash: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          expires_at?: string;
          id?: string;
          issuer_membership_id?: string;
          issuer_user_id?: string;
          project_id?: string;
          request_id?: string;
          revoked_at?: string | null;
          show_titles?: boolean;
          token_hash?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_calendar_subscriptions_issuer_membership_id_fkey";
            columns: ["issuer_membership_id"];
            isOneToOne: false;
            referencedRelation: "project_members";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_calendar_subscriptions_issuer_membership_id_fkey";
            columns: ["issuer_membership_id"];
            isOneToOne: false;
            referencedRelation: "project_members_visible";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_calendar_subscriptions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_entitlement_audit: {
        Row: {
          action: string;
          created_at: string;
          entitlement_version: number;
          expires_at: string | null;
          grant_source: string;
          granted_at: string;
          granted_by: string | null;
          id: number;
          note: string | null;
          plan: string;
          project_id: string;
          request_id: string | null;
          starts_at: string;
          status: string;
        };
        Insert: {
          action: string;
          created_at?: string;
          entitlement_version: number;
          expires_at?: string | null;
          grant_source: string;
          granted_at: string;
          granted_by?: string | null;
          id?: number;
          note?: string | null;
          plan: string;
          project_id: string;
          request_id?: string | null;
          starts_at: string;
          status: string;
        };
        Update: {
          action?: string;
          created_at?: string;
          entitlement_version?: number;
          expires_at?: string | null;
          grant_source?: string;
          granted_at?: string;
          granted_by?: string | null;
          id?: number;
          note?: string | null;
          plan?: string;
          project_id?: string;
          request_id?: string | null;
          starts_at?: string;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_entitlement_audit_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_entitlements: {
        Row: {
          created_at: string;
          expires_at: string | null;
          grant_source: string;
          granted_at: string;
          granted_by: string | null;
          note: string | null;
          plan: string;
          project_id: string;
          starts_at: string;
          status: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          expires_at?: string | null;
          grant_source?: string;
          granted_at?: string;
          granted_by?: string | null;
          note?: string | null;
          plan?: string;
          project_id: string;
          starts_at?: string;
          status?: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          expires_at?: string | null;
          grant_source?: string;
          granted_at?: string;
          granted_by?: string | null;
          note?: string | null;
          plan?: string;
          project_id?: string;
          starts_at?: string;
          status?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_entitlements_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: true;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_invitations: {
        Row: {
          created_at: string;
          created_by: string | null;
          expires_at: string;
          id: string;
          max_uses: number | null;
          mode: string;
          project_id: string;
          revoked_at: string | null;
          token_hash: string;
          updated_at: string;
          uses_count: number;
          version: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          expires_at: string;
          id?: string;
          max_uses?: number | null;
          mode: string;
          project_id: string;
          revoked_at?: string | null;
          token_hash: string;
          updated_at?: string;
          uses_count?: number;
          version?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          expires_at?: string;
          id?: string;
          max_uses?: number | null;
          mode?: string;
          project_id?: string;
          revoked_at?: string | null;
          token_hash?: string;
          updated_at?: string;
          uses_count?: number;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_invitations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_join_requests: {
        Row: {
          created_at: string;
          display_name_snapshot: string | null;
          id: string;
          invitation_id: string;
          project_id: string;
          reviewed_at: string | null;
          reviewed_by: string | null;
          state: string;
          updated_at: string;
          user_id: string | null;
          version: number;
        };
        Insert: {
          created_at?: string;
          display_name_snapshot?: string | null;
          id?: string;
          invitation_id: string;
          project_id: string;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          state?: string;
          updated_at?: string;
          user_id?: string | null;
          version?: number;
        };
        Update: {
          created_at?: string;
          display_name_snapshot?: string | null;
          id?: string;
          invitation_id?: string;
          project_id?: string;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          state?: string;
          updated_at?: string;
          user_id?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_join_requests_invitation_id_fkey";
            columns: ["invitation_id"];
            isOneToOne: false;
            referencedRelation: "project_invitations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_join_requests_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_members: {
        Row: {
          created_at: string;
          departed_at: string | null;
          display_name_snapshot: string | null;
          id: string;
          is_observer: boolean;
          joined_at: string;
          member_state: string;
          project_id: string;
          role: string;
          user_id: string | null;
          version: number;
        };
        Insert: {
          created_at?: string;
          departed_at?: string | null;
          display_name_snapshot?: string | null;
          id?: string;
          is_observer?: boolean;
          joined_at?: string;
          member_state?: string;
          project_id: string;
          role?: string;
          user_id?: string | null;
          version?: number;
        };
        Update: {
          created_at?: string;
          departed_at?: string | null;
          display_name_snapshot?: string | null;
          id?: string;
          is_observer?: boolean;
          joined_at?: string;
          member_state?: string;
          project_id?: string;
          role?: string;
          user_id?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_members_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_penalty_policy_consents: {
        Row: {
          consented_at: string;
          member_user_id: string;
          policy_version: number;
          project_id: string;
          request_id: string;
        };
        Insert: {
          consented_at?: string;
          member_user_id: string;
          policy_version?: number;
          project_id: string;
          request_id: string;
        };
        Update: {
          consented_at?: string;
          member_user_id?: string;
          policy_version?: number;
          project_id?: string;
          request_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_penalty_policy_consents_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_permission_delegations: {
        Row: {
          granted_at: string;
          granted_by: string | null;
          id: string;
          membership_id: string;
          project_id: string;
          revoked_at: string | null;
          template_code: string;
          version: number;
        };
        Insert: {
          granted_at?: string;
          granted_by?: string | null;
          id?: string;
          membership_id: string;
          project_id: string;
          revoked_at?: string | null;
          template_code: string;
          version?: number;
        };
        Update: {
          granted_at?: string;
          granted_by?: string | null;
          id?: string;
          membership_id?: string;
          project_id?: string;
          revoked_at?: string | null;
          template_code?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_permission_delegations_membership_id_fkey";
            columns: ["membership_id"];
            isOneToOne: false;
            referencedRelation: "project_members";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_permission_delegations_membership_id_fkey";
            columns: ["membership_id"];
            isOneToOne: false;
            referencedRelation: "project_members_visible";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_permission_delegations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_pro_grace: {
        Row: {
          expires_at: string;
          project_id: string;
          reason: string;
          started_at: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          expires_at: string;
          project_id: string;
          reason: string;
          started_at: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          expires_at?: string;
          project_id?: string;
          reason?: string;
          started_at?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_pro_grace_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: true;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_recovery_point_file_items: {
        Row: {
          captured_at: string;
          captured_file_row_version: number;
          captured_file_version_created_at: string;
          captured_file_version_id: string;
          captured_file_version_number: number;
          captured_final_designation_version: number | null;
          captured_is_final: boolean;
          captured_mime_type: string;
          captured_object_path: string;
          captured_original_name: string;
          captured_sha256_hex: string;
          captured_size_bytes: number;
          captured_uploaded_by: string | null;
          file_id: string;
          id: string;
          project_id: string;
          recovery_point_id: string;
          task_id: string;
        };
        Insert: {
          captured_at?: string;
          captured_file_row_version: number;
          captured_file_version_created_at: string;
          captured_file_version_id: string;
          captured_file_version_number: number;
          captured_final_designation_version?: number | null;
          captured_is_final?: boolean;
          captured_mime_type: string;
          captured_object_path: string;
          captured_original_name: string;
          captured_sha256_hex: string;
          captured_size_bytes: number;
          captured_uploaded_by?: string | null;
          file_id: string;
          id?: string;
          project_id: string;
          recovery_point_id: string;
          task_id: string;
        };
        Update: {
          captured_at?: string;
          captured_file_row_version?: number;
          captured_file_version_created_at?: string;
          captured_file_version_id?: string;
          captured_file_version_number?: number;
          captured_final_designation_version?: number | null;
          captured_is_final?: boolean;
          captured_mime_type?: string;
          captured_object_path?: string;
          captured_original_name?: string;
          captured_sha256_hex?: string;
          captured_size_bytes?: number;
          captured_uploaded_by?: string | null;
          file_id?: string;
          id?: string;
          project_id?: string;
          recovery_point_id?: string;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_recovery_point_file_i_file_id_captured_file_versio_fkey";
            columns: ["file_id", "captured_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_file_i_file_id_captured_file_versio_fkey";
            columns: ["file_id", "captured_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_file_ite_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_file_ite_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_file_items_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_recovery_point_file_items_recovery_point_id_fkey";
            columns: ["recovery_point_id"];
            isOneToOne: false;
            referencedRelation: "project_recovery_points";
            referencedColumns: ["id"];
          },
        ];
      };
      project_recovery_point_restore_items: {
        Row: {
          created_at: string;
          created_by: string | null;
          file_id: string;
          id: string;
          project_id: string;
          recovery_point_id: string;
          restore_request_id: string;
          restored_file_version_id: string;
          restored_final_file_version_id: string | null;
          restored_from_version_id: string;
          restored_version_number: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          file_id: string;
          id?: string;
          project_id: string;
          recovery_point_id: string;
          restore_request_id: string;
          restored_file_version_id: string;
          restored_final_file_version_id?: string | null;
          restored_from_version_id: string;
          restored_version_number: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          file_id?: string;
          id?: string;
          project_id?: string;
          recovery_point_id?: string;
          restore_request_id?: string;
          restored_file_version_id?: string;
          restored_final_file_version_id?: string | null;
          restored_from_version_id?: string;
          restored_version_number?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_recovery_point_restor_file_id_restored_file_versio_fkey";
            columns: ["file_id", "restored_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_restor_file_id_restored_file_versio_fkey";
            columns: ["file_id", "restored_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_restor_file_id_restored_from_versio_fkey";
            columns: ["file_id", "restored_from_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_restor_file_id_restored_from_versio_fkey";
            columns: ["file_id", "restored_from_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "project_recovery_point_restore_items_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_recovery_point_restore_items_recovery_point_id_fkey";
            columns: ["recovery_point_id"];
            isOneToOne: false;
            referencedRelation: "project_recovery_points";
            referencedColumns: ["id"];
          },
        ];
      };
      project_recovery_points: {
        Row: {
          created_at: string;
          created_by: string | null;
          id: string;
          item_count: number;
          label: string | null;
          project_id: string;
          project_version: number;
          restored_at: string | null;
          restored_by: string | null;
          scope: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          item_count?: number;
          label?: string | null;
          project_id: string;
          project_version: number;
          restored_at?: string | null;
          restored_by?: string | null;
          scope?: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          item_count?: number;
          label?: string | null;
          project_id?: string;
          project_version?: number;
          restored_at?: string | null;
          restored_by?: string | null;
          scope?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "project_recovery_points_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_retention_notices: {
        Row: {
          created_at: string;
          generation: number;
          node: string;
          project_id: string;
        };
        Insert: {
          created_at?: string;
          generation: number;
          node: string;
          project_id: string;
        };
        Update: {
          created_at?: string;
          generation?: number;
          node?: string;
          project_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_retention_notices_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      projects: {
        Row: {
          allow_member_task_creation: boolean;
          archived_at: string | null;
          auto_penalty_enabled: boolean;
          completed_at: string | null;
          contribution_mode: string;
          course_name: string | null;
          created_at: string;
          created_by: string | null;
          deadline_at: string;
          description: string | null;
          id: string;
          leader_id: string | null;
          lifecycle_state: string;
          name: string;
          require_real_name: boolean;
          require_student_number: boolean;
          start_at: string | null;
          timezone: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          allow_member_task_creation?: boolean;
          archived_at?: string | null;
          auto_penalty_enabled?: boolean;
          completed_at?: string | null;
          contribution_mode?: string;
          course_name?: string | null;
          created_at?: string;
          created_by?: string | null;
          deadline_at: string;
          description?: string | null;
          id?: string;
          leader_id?: string | null;
          lifecycle_state?: string;
          name: string;
          require_real_name?: boolean;
          require_student_number?: boolean;
          start_at?: string | null;
          timezone?: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          allow_member_task_creation?: boolean;
          archived_at?: string | null;
          auto_penalty_enabled?: boolean;
          completed_at?: string | null;
          contribution_mode?: string;
          course_name?: string | null;
          created_at?: string;
          created_by?: string | null;
          deadline_at?: string;
          description?: string | null;
          id?: string;
          leader_id?: string | null;
          lifecycle_state?: string;
          name?: string;
          require_real_name?: boolean;
          require_student_number?: boolean;
          start_at?: string | null;
          timezone?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [];
      };
      task_artifact_binding_history: {
        Row: {
          actor_id: string | null;
          binding_id: string;
          change_kind: string;
          created_at: string;
          downstream_task_id: string;
          id: number;
          logical_file_id: string;
          new_file_version_id: string | null;
          new_strength: string;
          previous_file_version_id: string | null;
          previous_strength: string | null;
          project_id: string;
          request_id: string | null;
          upstream_task_id: string;
        };
        Insert: {
          actor_id?: string | null;
          binding_id: string;
          change_kind: string;
          created_at?: string;
          downstream_task_id: string;
          id?: never;
          logical_file_id: string;
          new_file_version_id?: string | null;
          new_strength: string;
          previous_file_version_id?: string | null;
          previous_strength?: string | null;
          project_id: string;
          request_id?: string | null;
          upstream_task_id: string;
        };
        Update: {
          actor_id?: string | null;
          binding_id?: string;
          change_kind?: string;
          created_at?: string;
          downstream_task_id?: string;
          id?: never;
          logical_file_id?: string;
          new_file_version_id?: string | null;
          new_strength?: string;
          previous_file_version_id?: string | null;
          previous_strength?: string | null;
          project_id?: string;
          request_id?: string | null;
          upstream_task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_artifact_binding_history_binding_id_fkey";
            columns: ["binding_id"];
            isOneToOne: false;
            referencedRelation: "task_artifact_bindings";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_new_file_version_id_fkey";
            columns: ["new_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_new_file_version_id_fkey";
            columns: ["new_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_previous_file_version_id_fkey";
            columns: ["previous_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_previous_file_version_id_fkey";
            columns: ["previous_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_project_id_downstream_task_i_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_project_id_downstream_task_i_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_artifact_binding_history_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_artifact_bindings: {
        Row: {
          created_at: string;
          created_by: string | null;
          downstream_task_id: string;
          file_version_id: string;
          id: string;
          logical_file_id: string;
          project_id: string;
          strength: string;
          updated_at: string;
          updated_by: string | null;
          upstream_task_id: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          downstream_task_id: string;
          file_version_id: string;
          id?: string;
          logical_file_id: string;
          project_id: string;
          strength?: string;
          updated_at?: string;
          updated_by?: string | null;
          upstream_task_id: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          downstream_task_id?: string;
          file_version_id?: string;
          id?: string;
          logical_file_id?: string;
          project_id?: string;
          strength?: string;
          updated_at?: string;
          updated_by?: string | null;
          upstream_task_id?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_artifact_bindings_logical_file_id_file_version_id_fkey";
            columns: ["logical_file_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_logical_file_id_file_version_id_fkey";
            columns: ["logical_file_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_project_id_downstream_task_id_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_project_id_downstream_task_id_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_project_id_upstream_task_id_logical_fkey";
            columns: ["project_id", "upstream_task_id", "logical_file_id"];
            isOneToOne: false;
            referencedRelation: "task_files";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_artifact_bindings_project_id_upstream_task_id_logical_fkey";
            columns: ["project_id", "upstream_task_id", "logical_file_id"];
            isOneToOne: false;
            referencedRelation: "task_files_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
        ];
      };
      task_assignment_offers: {
        Row: {
          created_at: string;
          created_by: string | null;
          id: string;
          project_id: string;
          responded_at: string | null;
          state: string;
          target_user_id: string | null;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          project_id: string;
          responded_at?: string | null;
          state?: string;
          target_user_id?: string | null;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          project_id?: string;
          responded_at?: string | null;
          state?: string;
          target_user_id?: string | null;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_assignment_offers_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_assignment_offers_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_assignment_offers_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_change_proposals: {
        Row: {
          base_task_version: number;
          created_at: string;
          decided_at: string | null;
          decided_by: string | null;
          decision_reason: string | null;
          id: string;
          new_deadline_at: string;
          new_required_submission_file_type: string | null;
          new_required_submission_file_types: string[];
          new_weight: number | null;
          old_deadline_at: string;
          old_required_submission_file_type: string | null;
          old_required_submission_file_types: string[];
          old_weight: number | null;
          project_id: string;
          proposed_by: string;
          proposer_name_snapshot: string | null;
          required_confirmer_id: string;
          required_confirmer_name_snapshot: string | null;
          state: string;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          base_task_version: number;
          created_at?: string;
          decided_at?: string | null;
          decided_by?: string | null;
          decision_reason?: string | null;
          id?: string;
          new_deadline_at: string;
          new_required_submission_file_type?: string | null;
          new_required_submission_file_types?: string[];
          new_weight?: number | null;
          old_deadline_at: string;
          old_required_submission_file_type?: string | null;
          old_required_submission_file_types?: string[];
          old_weight?: number | null;
          project_id: string;
          proposed_by: string;
          proposer_name_snapshot?: string | null;
          required_confirmer_id: string;
          required_confirmer_name_snapshot?: string | null;
          state?: string;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          base_task_version?: number;
          created_at?: string;
          decided_at?: string | null;
          decided_by?: string | null;
          decision_reason?: string | null;
          id?: string;
          new_deadline_at?: string;
          new_required_submission_file_type?: string | null;
          new_required_submission_file_types?: string[];
          new_weight?: number | null;
          old_deadline_at?: string;
          old_required_submission_file_type?: string | null;
          old_required_submission_file_types?: string[];
          old_weight?: number | null;
          project_id?: string;
          proposed_by?: string;
          proposer_name_snapshot?: string | null;
          required_confirmer_id?: string;
          required_confirmer_name_snapshot?: string | null;
          state?: string;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_change_proposals_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_change_proposals_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_change_proposals_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_collaborators: {
        Row: {
          created_at: string;
          id: string;
          invited_by: string | null;
          invited_by_name_snapshot: string | null;
          project_id: string;
          removed_at: string | null;
          responded_at: string | null;
          state: string;
          task_id: string;
          updated_at: string;
          user_id: string | null;
          user_name_snapshot: string | null;
          version: number;
        };
        Insert: {
          created_at?: string;
          id?: string;
          invited_by?: string | null;
          invited_by_name_snapshot?: string | null;
          project_id: string;
          removed_at?: string | null;
          responded_at?: string | null;
          state?: string;
          task_id: string;
          updated_at?: string;
          user_id?: string | null;
          user_name_snapshot?: string | null;
          version?: number;
        };
        Update: {
          created_at?: string;
          id?: string;
          invited_by?: string | null;
          invited_by_name_snapshot?: string | null;
          project_id?: string;
          removed_at?: string | null;
          responded_at?: string | null;
          state?: string;
          task_id?: string;
          updated_at?: string;
          user_id?: string | null;
          user_name_snapshot?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_collaborators_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_collaborators_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_collaborators_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_contribution_ledger: {
        Row: {
          amount: number | null;
          created_at: string;
          id: string;
          member_user_id: string | null;
          project_id: string;
          proposal_id: string;
          share_bps: number;
          task_id: string;
          weight_snapshot: number | null;
        };
        Insert: {
          amount?: number | null;
          created_at?: string;
          id?: string;
          member_user_id?: string | null;
          project_id: string;
          proposal_id: string;
          share_bps: number;
          task_id: string;
          weight_snapshot?: number | null;
        };
        Update: {
          amount?: number | null;
          created_at?: string;
          id?: string;
          member_user_id?: string | null;
          project_id?: string;
          proposal_id?: string;
          share_bps?: number;
          task_id?: string;
          weight_snapshot?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_contribution_ledger_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_contribution_ledger_proposal_id_fkey";
            columns: ["proposal_id"];
            isOneToOne: false;
            referencedRelation: "task_share_proposals";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_contribution_ledger_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["task_id"];
          },
          {
            foreignKeyName: "task_contribution_ledger_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      task_dependencies: {
        Row: {
          created_at: string;
          created_by: string | null;
          downstream_task_id: string;
          project_id: string;
          upstream_task_id: string;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          downstream_task_id: string;
          project_id: string;
          upstream_task_id: string;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          downstream_task_id?: string;
          project_id?: string;
          upstream_task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_dependencies_project_id_downstream_task_id_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_dependencies_project_id_downstream_task_id_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_dependencies_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_dependencies_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_dependencies_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_expected_share_consents: {
        Row: {
          consented_at: string;
          deadline_snapshot: string;
          expected_share_bps: number;
          id: string;
          member_user_id: string;
          project_id: string;
          request_id: string;
          task_id: string;
          task_version: number;
          weight_snapshot: number;
        };
        Insert: {
          consented_at?: string;
          deadline_snapshot: string;
          expected_share_bps: number;
          id?: string;
          member_user_id: string;
          project_id: string;
          request_id: string;
          task_id: string;
          task_version: number;
          weight_snapshot: number;
        };
        Update: {
          consented_at?: string;
          deadline_snapshot?: string;
          expected_share_bps?: number;
          id?: string;
          member_user_id?: string;
          project_id?: string;
          request_id?: string;
          task_id?: string;
          task_version?: number;
          weight_snapshot?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_expected_share_consents_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_expected_share_consents_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_expected_share_consents_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_external_evidence: {
        Row: {
          created_at: string;
          description: string;
          host: string;
          https_url: string;
          id: string;
          project_id: string;
          revoked_at: string | null;
          revoked_by: string | null;
          submitted_by: string | null;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          description: string;
          host: string;
          https_url: string;
          id?: string;
          project_id: string;
          revoked_at?: string | null;
          revoked_by?: string | null;
          submitted_by?: string | null;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          description?: string;
          host?: string;
          https_url?: string;
          id?: string;
          project_id?: string;
          revoked_at?: string | null;
          revoked_by?: string | null;
          submitted_by?: string | null;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_external_evidence_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_external_evidence_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_external_evidence_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_external_evidence_revisions: {
        Row: {
          action: string;
          changed_at: string;
          changed_by: string | null;
          command_request_id: string;
          description: string;
          evidence_created_at: string;
          evidence_id: string;
          evidence_updated_at: string;
          host: string;
          https_url: string;
          id: string;
          occurrence_key: string;
          project_id: string;
          request_id: string;
          submitted_by: string | null;
          task_id: string;
          version: number;
        };
        Insert: {
          action: string;
          changed_at?: string;
          changed_by?: string | null;
          command_request_id: string;
          description: string;
          evidence_created_at: string;
          evidence_id: string;
          evidence_updated_at: string;
          host: string;
          https_url: string;
          id?: string;
          occurrence_key: string;
          project_id: string;
          request_id: string;
          submitted_by?: string | null;
          task_id: string;
          version: number;
        };
        Update: {
          action?: string;
          changed_at?: string;
          changed_by?: string | null;
          command_request_id?: string;
          description?: string;
          evidence_created_at?: string;
          evidence_id?: string;
          evidence_updated_at?: string;
          host?: string;
          https_url?: string;
          id?: string;
          occurrence_key?: string;
          project_id?: string;
          request_id?: string;
          submitted_by?: string | null;
          task_id?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_external_evidence_revisi_project_id_task_id_evidence__fkey";
            columns: ["project_id", "task_id", "evidence_id"];
            isOneToOne: false;
            referencedRelation: "task_external_evidence";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_external_evidence_revisions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      task_file_final_designations: {
        Row: {
          file_id: string;
          file_version_id: string;
          is_final: boolean;
          marked_at: string | null;
          marked_by: string | null;
          project_id: string;
          task_id: string;
          updated_at: string;
          updated_by: string | null;
          version: number;
        };
        Insert: {
          file_id: string;
          file_version_id: string;
          is_final?: boolean;
          marked_at?: string | null;
          marked_by?: string | null;
          project_id: string;
          task_id: string;
          updated_at?: string;
          updated_by?: string | null;
          version?: number;
        };
        Update: {
          file_id?: string;
          file_version_id?: string;
          is_final?: boolean;
          marked_at?: string | null;
          marked_by?: string | null;
          project_id?: string;
          task_id?: string;
          updated_at?: string;
          updated_by?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_file_final_designations_file_id_file_version_id_fkey";
            columns: ["file_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_file_final_designations_file_id_file_version_id_fkey";
            columns: ["file_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_file_final_designations_file_version_id_fkey";
            columns: ["file_version_id"];
            isOneToOne: true;
            referencedRelation: "task_file_versions";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_file_final_designations_file_version_id_fkey";
            columns: ["file_version_id"];
            isOneToOne: true;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_file_final_designations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_file_final_designations_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_file_final_designations_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
        ];
      };
      task_file_versions: {
        Row: {
          created_at: string;
          file_id: string;
          id: string;
          mime_type: string;
          object_path: string;
          original_name: string;
          project_id: string;
          reservation_id: string;
          restored_from_version_id: string | null;
          sha256_hex: string;
          size_bytes: number;
          task_id: string;
          uploaded_by: string | null;
          version_number: number;
        };
        Insert: {
          created_at?: string;
          file_id: string;
          id?: string;
          mime_type: string;
          object_path: string;
          original_name: string;
          project_id: string;
          reservation_id: string;
          restored_from_version_id?: string | null;
          sha256_hex: string;
          size_bytes: number;
          task_id: string;
          uploaded_by?: string | null;
          version_number: number;
        };
        Update: {
          created_at?: string;
          file_id?: string;
          id?: string;
          mime_type?: string;
          object_path?: string;
          original_name?: string;
          project_id?: string;
          reservation_id?: string;
          restored_from_version_id?: string | null;
          sha256_hex?: string;
          size_bytes?: number;
          task_id?: string;
          uploaded_by?: string | null;
          version_number?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_file_versions_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_file_versions_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_file_versions_reservation_id_fkey";
            columns: ["project_id", "task_id", "reservation_id", "object_path"];
            isOneToOne: false;
            referencedRelation: "file_upload_reservations";
            referencedColumns: ["project_id", "task_id", "id", "object_path"];
          },
          {
            foreignKeyName: "task_file_versions_reservation_id_fkey";
            columns: ["project_id", "task_id", "reservation_id", "object_path"];
            isOneToOne: false;
            referencedRelation: "file_upload_reservations_visible";
            referencedColumns: ["project_id", "task_id", "id", "object_path"];
          },
          {
            foreignKeyName: "task_file_versions_restored_same_file_fkey";
            columns: ["file_id", "restored_from_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_file_versions_restored_same_file_fkey";
            columns: ["file_id", "restored_from_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
        ];
      };
      task_files: {
        Row: {
          created_at: string;
          created_by: string | null;
          current_version_id: string | null;
          id: string;
          logical_name: string;
          project_id: string;
          purpose: string;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          current_version_id?: string | null;
          id?: string;
          logical_name: string;
          project_id: string;
          purpose?: string;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          current_version_id?: string | null;
          id?: string;
          logical_name?: string;
          project_id?: string;
          purpose?: string;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_files_current_version_same_file_fkey";
            columns: ["id", "current_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_files_current_version_same_file_fkey";
            columns: ["id", "current_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_files_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_files_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_files_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_first_submission_facts: {
        Row: {
          blocked_exempt: boolean;
          deadline_snapshot: string;
          effective_start_snapshot: string | null;
          eligible_late: boolean;
          first_submitted_at: string;
          project_id: string;
          responsibility_epoch_id: string | null;
          responsible_user_id: string | null;
          task_id: string;
        };
        Insert: {
          blocked_exempt: boolean;
          deadline_snapshot: string;
          effective_start_snapshot?: string | null;
          eligible_late: boolean;
          first_submitted_at: string;
          project_id: string;
          responsibility_epoch_id?: string | null;
          responsible_user_id?: string | null;
          task_id: string;
        };
        Update: {
          blocked_exempt?: boolean;
          deadline_snapshot?: string;
          effective_start_snapshot?: string | null;
          eligible_late?: boolean;
          first_submitted_at?: string;
          project_id?: string;
          responsibility_epoch_id?: string | null;
          responsible_user_id?: string | null;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_first_submission_facts_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_first_submission_facts_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_first_submission_facts_responsibility_epoch_id_fkey";
            columns: ["responsibility_epoch_id"];
            isOneToOne: false;
            referencedRelation: "task_responsibility_epochs";
            referencedColumns: ["id"];
          },
        ];
      };
      task_help_requests: {
        Row: {
          blocked_task_version: number | null;
          created_at: string;
          id: string;
          marks_task_blocked: boolean;
          message: string;
          project_id: string;
          requested_by: string;
          resolved_at: string | null;
          resolved_by: string | null;
          state: string;
          target_user_id: string;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          blocked_task_version?: number | null;
          created_at?: string;
          id?: string;
          marks_task_blocked?: boolean;
          message: string;
          project_id: string;
          requested_by: string;
          resolved_at?: string | null;
          resolved_by?: string | null;
          state?: string;
          target_user_id: string;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          blocked_task_version?: number | null;
          created_at?: string;
          id?: string;
          marks_task_blocked?: boolean;
          message?: string;
          project_id?: string;
          requested_by?: string;
          resolved_at?: string | null;
          resolved_by?: string | null;
          state?: string;
          target_user_id?: string;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_help_requests_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_help_requests_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_help_requests_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_nudge_logs: {
        Row: {
          exception_kind: string;
          id: string;
          project_id: string;
          recipient_count: number;
          sender_id: string;
          sent_at: string;
          source_event_id: number | null;
          task_id: string;
        };
        Insert: {
          exception_kind: string;
          id?: string;
          project_id: string;
          recipient_count: number;
          sender_id: string;
          sent_at?: string;
          source_event_id?: number | null;
          task_id: string;
        };
        Update: {
          exception_kind?: string;
          id?: string;
          project_id?: string;
          recipient_count?: number;
          sender_id?: string;
          sent_at?: string;
          source_event_id?: number | null;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_nudge_logs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_nudge_logs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_nudge_logs_source_event_id_fkey";
            columns: ["source_event_id"];
            isOneToOne: false;
            referencedRelation: "business_events";
            referencedColumns: ["id"];
          },
        ];
      };
      task_primary_handoffs: {
        Row: {
          canceled_at: string | null;
          created_at: string;
          created_by: string | null;
          from_user_id: string | null;
          from_user_name_snapshot: string;
          id: string;
          project_id: string;
          responded_at: string | null;
          state: string;
          task_id: string;
          to_user_id: string | null;
          to_user_name_snapshot: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          canceled_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          from_user_id?: string | null;
          from_user_name_snapshot: string;
          id?: string;
          project_id: string;
          responded_at?: string | null;
          state?: string;
          task_id: string;
          to_user_id?: string | null;
          to_user_name_snapshot: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          canceled_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          from_user_id?: string | null;
          from_user_name_snapshot?: string;
          id?: string;
          project_id?: string;
          responded_at?: string | null;
          state?: string;
          task_id?: string;
          to_user_id?: string | null;
          to_user_name_snapshot?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_primary_handoffs_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_primary_handoffs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_primary_handoffs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_reminder_deadlines: {
        Row: {
          deadline_at: string;
          deadline_revision: number;
          project_id: string;
          task_id: string;
        };
        Insert: {
          deadline_at: string;
          deadline_revision?: number;
          project_id: string;
          task_id: string;
        };
        Update: {
          deadline_at?: string;
          deadline_revision?: number;
          project_id?: string;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_reminder_deadlines_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_reminder_deadlines_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: true;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["task_id"];
          },
          {
            foreignKeyName: "task_reminder_deadlines_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: true;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      task_reminder_jobs: {
        Row: {
          deadline_at: string;
          deadline_revision: number;
          delivered_at: string | null;
          invalidated_at: string | null;
          offset_seconds: number;
          project_id: string;
          recipient_id: string;
          scheduled_for: string;
          source_event_id: number | null;
          task_id: string;
        };
        Insert: {
          deadline_at: string;
          deadline_revision: number;
          delivered_at?: string | null;
          invalidated_at?: string | null;
          offset_seconds: number;
          project_id: string;
          recipient_id: string;
          scheduled_for: string;
          source_event_id?: number | null;
          task_id: string;
        };
        Update: {
          deadline_at?: string;
          deadline_revision?: number;
          delivered_at?: string | null;
          invalidated_at?: string | null;
          offset_seconds?: number;
          project_id?: string;
          recipient_id?: string;
          scheduled_for?: string;
          source_event_id?: number | null;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_reminder_jobs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_reminder_jobs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_reminder_jobs_source_event_id_fkey";
            columns: ["source_event_id"];
            isOneToOne: false;
            referencedRelation: "business_events";
            referencedColumns: ["id"];
          },
        ];
      };
      task_reminder_preferences: {
        Row: {
          enabled: boolean;
          offsets_seconds: number[];
          project_id: string;
          recipient_id: string;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          enabled?: boolean;
          offsets_seconds?: number[];
          project_id: string;
          recipient_id: string;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          enabled?: boolean;
          offsets_seconds?: number[];
          project_id?: string;
          recipient_id?: string;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_reminder_preferences_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_reminder_preferences_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_reminder_preferences_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_responsibility_epochs: {
        Row: {
          accepted_at: string;
          accepted_expected_contribution: number | null;
          auto_penalty_enabled_snapshot: boolean;
          blocked_exempt: boolean;
          closed_at: string | null;
          closure_reason: string | null;
          created_at: string;
          deadline_revision: number;
          effective_deadline_at: string;
          effective_start_at: string | null;
          exemption_reason: string | null;
          expected_share_bps_snapshot: number | null;
          free_abandon_until: string | null;
          id: string;
          project_contribution_mode: string;
          project_id: string;
          responsible_user_id: string | null;
          shares_confirmed: boolean;
          task_id: string;
          trigger_source: string;
          weight_snapshot: number | null;
        };
        Insert: {
          accepted_at: string;
          accepted_expected_contribution?: number | null;
          auto_penalty_enabled_snapshot: boolean;
          blocked_exempt: boolean;
          closed_at?: string | null;
          closure_reason?: string | null;
          created_at?: string;
          deadline_revision: number;
          effective_deadline_at: string;
          effective_start_at?: string | null;
          exemption_reason?: string | null;
          expected_share_bps_snapshot?: number | null;
          free_abandon_until?: string | null;
          id?: string;
          project_contribution_mode: string;
          project_id: string;
          responsible_user_id?: string | null;
          shares_confirmed?: boolean;
          task_id: string;
          trigger_source: string;
          weight_snapshot?: number | null;
        };
        Update: {
          accepted_at?: string;
          accepted_expected_contribution?: number | null;
          auto_penalty_enabled_snapshot?: boolean;
          blocked_exempt?: boolean;
          closed_at?: string | null;
          closure_reason?: string | null;
          created_at?: string;
          deadline_revision?: number;
          effective_deadline_at?: string;
          effective_start_at?: string | null;
          exemption_reason?: string | null;
          expected_share_bps_snapshot?: number | null;
          free_abandon_until?: string | null;
          id?: string;
          project_contribution_mode?: string;
          project_id?: string;
          responsible_user_id?: string | null;
          shares_confirmed?: boolean;
          task_id?: string;
          trigger_source?: string;
          weight_snapshot?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_responsibility_epochs_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_responsibility_epochs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_responsibility_epochs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_review_round_files: {
        Row: {
          created_at: string;
          file_version_id: string;
          position: number;
          project_id: string;
          review_round_id: string;
          task_id: string;
        };
        Insert: {
          created_at?: string;
          file_version_id: string;
          position: number;
          project_id: string;
          review_round_id: string;
          task_id: string;
        };
        Update: {
          created_at?: string;
          file_version_id?: string;
          position?: number;
          project_id?: string;
          review_round_id?: string;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_review_round_files_project_id_task_id_file_version_id_fkey";
            columns: ["project_id", "task_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_review_round_files_project_id_task_id_file_version_id_fkey";
            columns: ["project_id", "task_id", "file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_review_round_files_project_id_task_id_review_round_id_fkey";
            columns: ["project_id", "task_id", "review_round_id"];
            isOneToOne: false;
            referencedRelation: "task_review_rounds";
            referencedColumns: ["project_id", "task_id", "id"];
          },
        ];
      };
      task_review_rounds: {
        Row: {
          correction_of_review_round_id: string | null;
          created_at: string;
          decision: string | null;
          delegated_reviewer_id: string | null;
          delegation_required: boolean;
          id: string;
          project_id: string;
          rejection_reason: string | null;
          required_submission_file_type_snapshot: string | null;
          required_submission_file_types_snapshot: string[];
          reviewed_at: string | null;
          reviewed_by: string | null;
          round_number: number;
          state: string;
          submission_text_snapshot: string | null;
          submitted_at: string;
          submitted_by: string | null;
          submitted_file_version_id: string | null;
          task_id: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          correction_of_review_round_id?: string | null;
          created_at?: string;
          decision?: string | null;
          delegated_reviewer_id?: string | null;
          delegation_required?: boolean;
          id?: string;
          project_id: string;
          rejection_reason?: string | null;
          required_submission_file_type_snapshot?: string | null;
          required_submission_file_types_snapshot?: string[];
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          round_number: number;
          state?: string;
          submission_text_snapshot?: string | null;
          submitted_at?: string;
          submitted_by?: string | null;
          submitted_file_version_id?: string | null;
          task_id: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          correction_of_review_round_id?: string | null;
          created_at?: string;
          decision?: string | null;
          delegated_reviewer_id?: string | null;
          delegation_required?: boolean;
          id?: string;
          project_id?: string;
          rejection_reason?: string | null;
          required_submission_file_type_snapshot?: string | null;
          required_submission_file_types_snapshot?: string[];
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          round_number?: number;
          state?: string;
          submission_text_snapshot?: string | null;
          submitted_at?: string;
          submitted_by?: string | null;
          submitted_file_version_id?: string | null;
          task_id?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_review_rounds_correction_source_fk";
            columns: ["correction_of_review_round_id"];
            isOneToOne: false;
            referencedRelation: "task_review_rounds";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_review_rounds_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_review_rounds_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_review_rounds_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "task_review_rounds_project_id_task_id_submitted_file_versi_fkey";
            columns: ["project_id", "task_id", "submitted_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_review_rounds_project_id_task_id_submitted_file_versi_fkey";
            columns: ["project_id", "task_id", "submitted_file_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
        ];
      };
      task_share_allocations: {
        Row: {
          amount: number | null;
          id: string;
          member_user_id: string | null;
          project_id: string;
          proposal_id: string;
          share_bps: number;
        };
        Insert: {
          amount?: number | null;
          id?: string;
          member_user_id?: string | null;
          project_id: string;
          proposal_id: string;
          share_bps: number;
        };
        Update: {
          amount?: number | null;
          id?: string;
          member_user_id?: string | null;
          project_id?: string;
          proposal_id?: string;
          share_bps?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_share_allocations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_share_allocations_proposal_id_fkey";
            columns: ["proposal_id"];
            isOneToOne: false;
            referencedRelation: "task_share_proposals";
            referencedColumns: ["id"];
          },
        ];
      };
      task_share_confirmations: {
        Row: {
          confirmed_at: string;
          id: string;
          member_user_id: string | null;
          proposal_id: string;
        };
        Insert: {
          confirmed_at?: string;
          id?: string;
          member_user_id?: string | null;
          proposal_id: string;
        };
        Update: {
          confirmed_at?: string;
          id?: string;
          member_user_id?: string | null;
          proposal_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_share_confirmations_proposal_id_fkey";
            columns: ["proposal_id"];
            isOneToOne: false;
            referencedRelation: "task_share_proposals";
            referencedColumns: ["id"];
          },
        ];
      };
      task_share_proposals: {
        Row: {
          confirmed_at: string | null;
          contribution_mode_snapshot: string;
          created_at: string;
          id: string;
          project_id: string;
          proposed_by: string | null;
          revision: number;
          status: string;
          task_id: string;
          version: number;
          weight_snapshot: number | null;
        };
        Insert: {
          confirmed_at?: string | null;
          contribution_mode_snapshot: string;
          created_at?: string;
          id?: string;
          project_id: string;
          proposed_by?: string | null;
          revision: number;
          status?: string;
          task_id: string;
          version?: number;
          weight_snapshot?: number | null;
        };
        Update: {
          confirmed_at?: string | null;
          contribution_mode_snapshot?: string;
          created_at?: string;
          id?: string;
          project_id?: string;
          proposed_by?: string | null;
          revision?: number;
          status?: string;
          task_id?: string;
          version?: number;
          weight_snapshot?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_share_proposals_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_share_proposals_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["task_id"];
          },
          {
            foreignKeyName: "task_share_proposals_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      task_share_rejections: {
        Row: {
          id: string;
          member_user_id: string | null;
          proposal_id: string;
          reason: string;
          rejected_at: string;
        };
        Insert: {
          id?: string;
          member_user_id?: string | null;
          proposal_id: string;
          reason: string;
          rejected_at?: string;
        };
        Update: {
          id?: string;
          member_user_id?: string | null;
          proposal_id?: string;
          reason?: string;
          rejected_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_share_rejections_proposal_id_fkey";
            columns: ["proposal_id"];
            isOneToOne: false;
            referencedRelation: "task_share_proposals";
            referencedColumns: ["id"];
          },
        ];
      };
      tasks: {
        Row: {
          accepted_at: string | null;
          assignee_id: string | null;
          assignment_state: string;
          blocked_reason: string | null;
          cancel_reason: string | null;
          canceled_at: string | null;
          completed_at: string | null;
          created_at: string;
          created_by: string | null;
          deadline_at: string;
          description: string | null;
          first_submitted_at: string | null;
          id: string;
          is_direct_assignment: boolean;
          progress_text: string | null;
          project_id: string;
          required_submission_file_type: string | null;
          required_submission_file_types: string[];
          requires_review: boolean;
          status: string;
          title: string;
          updated_at: string;
          version: number;
          weight: number | null;
        };
        Insert: {
          accepted_at?: string | null;
          assignee_id?: string | null;
          assignment_state?: string;
          blocked_reason?: string | null;
          cancel_reason?: string | null;
          canceled_at?: string | null;
          completed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          deadline_at: string;
          description?: string | null;
          first_submitted_at?: string | null;
          id?: string;
          is_direct_assignment?: boolean;
          progress_text?: string | null;
          project_id: string;
          required_submission_file_type?: string | null;
          required_submission_file_types?: string[];
          requires_review?: boolean;
          status?: string;
          title: string;
          updated_at?: string;
          version?: number;
          weight?: number | null;
        };
        Update: {
          accepted_at?: string | null;
          assignee_id?: string | null;
          assignment_state?: string;
          blocked_reason?: string | null;
          cancel_reason?: string | null;
          canceled_at?: string | null;
          completed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          deadline_at?: string;
          description?: string | null;
          first_submitted_at?: string | null;
          id?: string;
          is_direct_assignment?: boolean;
          progress_text?: string | null;
          project_id?: string;
          required_submission_file_type?: string | null;
          required_submission_file_types?: string[];
          requires_review?: boolean;
          status?: string;
          title?: string;
          updated_at?: string;
          version?: number;
          weight?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "tasks_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      upstream_rework_requests: {
        Row: {
          created_at: string;
          downstream_task_id: string;
          id: string;
          project_id: string;
          requested_by: string;
          requirement: string;
          reviewed_at: string | null;
          reviewed_by: string | null;
          state: string;
          updated_at: string;
          upstream_completed_version: number;
          upstream_task_id: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          downstream_task_id: string;
          id?: string;
          project_id: string;
          requested_by: string;
          requirement: string;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          state?: string;
          updated_at?: string;
          upstream_completed_version: number;
          upstream_task_id: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          downstream_task_id?: string;
          id?: string;
          project_id?: string;
          requested_by?: string;
          requirement?: string;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          state?: string;
          updated_at?: string;
          upstream_completed_version?: number;
          upstream_task_id?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "upstream_rework_requests_project_id_downstream_task_id_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "upstream_rework_requests_project_id_downstream_task_id_fkey";
            columns: ["project_id", "downstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "upstream_rework_requests_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "upstream_rework_requests_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "upstream_rework_requests_project_id_upstream_task_id_fkey";
            columns: ["project_id", "upstream_task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      user_help_dismissals: {
        Row: {
          dismissed_at: string;
          hint_key: string;
          user_id: string;
        };
        Insert: {
          dismissed_at?: string;
          hint_key: string;
          user_id: string;
        };
        Update: {
          dismissed_at?: string;
          hint_key?: string;
          user_id?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      file_upload_reservations_visible: {
        Row: {
          actor_id: string | null;
          created_at: string | null;
          declared_mime_type: string | null;
          declared_size_bytes: number | null;
          expires_at: string | null;
          id: string | null;
          mode: string | null;
          object_path: string | null;
          original_name: string | null;
          project_id: string | null;
          rejection_code: string | null;
          reserved_envelope_bytes: number | null;
          state: string | null;
          target_file_id: string | null;
          target_file_version: number | null;
          task_id: string | null;
          updated_at: string | null;
          version: number | null;
        };
        Insert: {
          actor_id?: never;
          created_at?: string | null;
          declared_mime_type?: string | null;
          declared_size_bytes?: number | null;
          expires_at?: string | null;
          id?: string | null;
          mode?: string | null;
          object_path?: string | null;
          original_name?: never;
          project_id?: string | null;
          rejection_code?: string | null;
          reserved_envelope_bytes?: number | null;
          state?: string | null;
          target_file_id?: string | null;
          target_file_version?: number | null;
          task_id?: string | null;
          updated_at?: string | null;
          version?: number | null;
        };
        Update: {
          actor_id?: never;
          created_at?: string | null;
          declared_mime_type?: string | null;
          declared_size_bytes?: number | null;
          expires_at?: string | null;
          id?: string | null;
          mode?: string | null;
          object_path?: string | null;
          original_name?: never;
          project_id?: string | null;
          rejection_code?: string | null;
          reserved_envelope_bytes?: number | null;
          state?: string | null;
          target_file_id?: string | null;
          target_file_version?: number | null;
          task_id?: string | null;
          updated_at?: string | null;
          version?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "file_upload_reservations_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "file_upload_reservations_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "file_upload_reservations_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "file_upload_reservations_target_file_fkey";
            columns: ["project_id", "task_id", "target_file_id"];
            isOneToOne: false;
            referencedRelation: "task_files";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "file_upload_reservations_target_file_fkey";
            columns: ["project_id", "task_id", "target_file_id"];
            isOneToOne: false;
            referencedRelation: "task_files_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
        ];
      };
      project_contribution_balances: {
        Row: {
          amount: number | null;
          member_user_id: string | null;
          project_id: string | null;
        };
        Relationships: [];
      };
      project_contribution_ledger_entries: {
        Row: {
          entry_id: string | null;
          entry_type: string | null;
          member_user_id: string | null;
          project_id: string | null;
          signed_amount: number | null;
          task_id: string | null;
        };
        Relationships: [];
      };
      project_contribution_share_readiness: {
        Row: {
          project_id: string | null;
          shares_ready: boolean | null;
          task_id: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "tasks_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_join_requests_visible: {
        Row: {
          created_at: string | null;
          display_name_snapshot: string | null;
          id: string | null;
          invitation_id: string | null;
          project_id: string | null;
          reviewed_at: string | null;
          reviewed_by: string | null;
          state: string | null;
          updated_at: string | null;
          user_id: string | null;
          version: number | null;
        };
        Insert: {
          created_at?: string | null;
          display_name_snapshot?: never;
          id?: string | null;
          invitation_id?: string | null;
          project_id?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          state?: string | null;
          updated_at?: string | null;
          user_id?: string | null;
          version?: number | null;
        };
        Update: {
          created_at?: string | null;
          display_name_snapshot?: never;
          id?: string | null;
          invitation_id?: string | null;
          project_id?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          state?: string | null;
          updated_at?: string | null;
          user_id?: string | null;
          version?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "project_join_requests_invitation_id_fkey";
            columns: ["invitation_id"];
            isOneToOne: false;
            referencedRelation: "project_invitations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_join_requests_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      project_members_visible: {
        Row: {
          created_at: string | null;
          departed_at: string | null;
          display_name_snapshot: string | null;
          id: string | null;
          is_observer: boolean | null;
          joined_at: string | null;
          member_state: string | null;
          project_id: string | null;
          role: string | null;
          user_id: string | null;
          version: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "project_members_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      task_authoritative_contributions: {
        Row: {
          amount: number | null;
          created_at: string | null;
          id: string | null;
          member_user_id: string | null;
          project_id: string | null;
          proposal_id: string | null;
          share_bps: number | null;
          task_id: string | null;
          weight_snapshot: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_contribution_ledger_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_contribution_ledger_proposal_id_fkey";
            columns: ["proposal_id"];
            isOneToOne: false;
            referencedRelation: "task_share_proposals";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_contribution_ledger_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["task_id"];
          },
          {
            foreignKeyName: "task_contribution_ledger_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      task_change_proposals_visible: {
        Row: {
          base_task_version: number | null;
          created_at: string | null;
          decided_at: string | null;
          decided_by: string | null;
          decision_reason: string | null;
          id: string | null;
          new_deadline_at: string | null;
          new_required_submission_file_type: string | null;
          new_required_submission_file_types: string[] | null;
          new_weight: number | null;
          old_deadline_at: string | null;
          old_required_submission_file_type: string | null;
          old_required_submission_file_types: string[] | null;
          old_weight: number | null;
          project_id: string | null;
          proposed_by: string | null;
          proposer_name_snapshot: string | null;
          required_confirmer_id: string | null;
          required_confirmer_name_snapshot: string | null;
          state: string | null;
          task_id: string | null;
          updated_at: string | null;
          version: number | null;
        };
        Insert: {
          base_task_version?: number | null;
          created_at?: string | null;
          decided_at?: string | null;
          decided_by?: string | null;
          decision_reason?: string | null;
          id?: string | null;
          new_deadline_at?: string | null;
          new_required_submission_file_type?: string | null;
          new_required_submission_file_types?: string[] | null;
          new_weight?: number | null;
          old_deadline_at?: string | null;
          old_required_submission_file_type?: string | null;
          old_required_submission_file_types?: string[] | null;
          old_weight?: number | null;
          project_id?: string | null;
          proposed_by?: string | null;
          proposer_name_snapshot?: never;
          required_confirmer_id?: string | null;
          required_confirmer_name_snapshot?: never;
          state?: string | null;
          task_id?: string | null;
          updated_at?: string | null;
          version?: number | null;
        };
        Update: {
          base_task_version?: number | null;
          created_at?: string | null;
          decided_at?: string | null;
          decided_by?: string | null;
          decision_reason?: string | null;
          id?: string | null;
          new_deadline_at?: string | null;
          new_required_submission_file_type?: string | null;
          new_required_submission_file_types?: string[] | null;
          new_weight?: number | null;
          old_deadline_at?: string | null;
          old_required_submission_file_type?: string | null;
          old_required_submission_file_types?: string[] | null;
          old_weight?: number | null;
          project_id?: string | null;
          proposed_by?: string | null;
          proposer_name_snapshot?: never;
          required_confirmer_id?: string | null;
          required_confirmer_name_snapshot?: never;
          state?: string | null;
          task_id?: string | null;
          updated_at?: string | null;
          version?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_change_proposals_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_change_proposals_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_change_proposals_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_collaborators_visible: {
        Row: {
          created_at: string | null;
          id: string | null;
          invited_by: string | null;
          invited_by_name_snapshot: string | null;
          project_id: string | null;
          removed_at: string | null;
          responded_at: string | null;
          state: string | null;
          task_id: string | null;
          updated_at: string | null;
          user_id: string | null;
          user_name_snapshot: string | null;
          version: number | null;
        };
        Insert: {
          created_at?: string | null;
          id?: string | null;
          invited_by?: string | null;
          invited_by_name_snapshot?: never;
          project_id?: string | null;
          removed_at?: string | null;
          responded_at?: string | null;
          state?: string | null;
          task_id?: string | null;
          updated_at?: string | null;
          user_id?: string | null;
          user_name_snapshot?: never;
          version?: number | null;
        };
        Update: {
          created_at?: string | null;
          id?: string | null;
          invited_by?: string | null;
          invited_by_name_snapshot?: never;
          project_id?: string | null;
          removed_at?: string | null;
          responded_at?: string | null;
          state?: string | null;
          task_id?: string | null;
          updated_at?: string | null;
          user_id?: string | null;
          user_name_snapshot?: never;
          version?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_collaborators_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_collaborators_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_collaborators_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_file_versions_visible: {
        Row: {
          created_at: string | null;
          file_id: string | null;
          id: string | null;
          mime_type: string | null;
          object_path: string | null;
          original_name: string | null;
          project_id: string | null;
          reservation_id: string | null;
          restored_from_version_id: string | null;
          sha256_hex: string | null;
          size_bytes: number | null;
          task_id: string | null;
          uploaded_by: string | null;
          version_number: number | null;
        };
        Insert: {
          created_at?: string | null;
          file_id?: string | null;
          id?: string | null;
          mime_type?: string | null;
          object_path?: string | null;
          original_name?: never;
          project_id?: string | null;
          reservation_id?: string | null;
          restored_from_version_id?: string | null;
          sha256_hex?: string | null;
          size_bytes?: number | null;
          task_id?: string | null;
          uploaded_by?: never;
          version_number?: number | null;
        };
        Update: {
          created_at?: string | null;
          file_id?: string | null;
          id?: string | null;
          mime_type?: string | null;
          object_path?: string | null;
          original_name?: never;
          project_id?: string | null;
          reservation_id?: string | null;
          restored_from_version_id?: string | null;
          sha256_hex?: string | null;
          size_bytes?: number | null;
          task_id?: string | null;
          uploaded_by?: never;
          version_number?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_file_versions_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_file_versions_project_id_task_id_file_id_fkey";
            columns: ["project_id", "task_id", "file_id"];
            isOneToOne: false;
            referencedRelation: "task_files_visible";
            referencedColumns: ["project_id", "task_id", "id"];
          },
          {
            foreignKeyName: "task_file_versions_reservation_id_fkey";
            columns: ["project_id", "task_id", "reservation_id", "object_path"];
            isOneToOne: false;
            referencedRelation: "file_upload_reservations";
            referencedColumns: ["project_id", "task_id", "id", "object_path"];
          },
          {
            foreignKeyName: "task_file_versions_reservation_id_fkey";
            columns: ["project_id", "task_id", "reservation_id", "object_path"];
            isOneToOne: false;
            referencedRelation: "file_upload_reservations_visible";
            referencedColumns: ["project_id", "task_id", "id", "object_path"];
          },
          {
            foreignKeyName: "task_file_versions_restored_same_file_fkey";
            columns: ["file_id", "restored_from_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_file_versions_restored_same_file_fkey";
            columns: ["file_id", "restored_from_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
        ];
      };
      task_files_visible: {
        Row: {
          created_at: string | null;
          created_by: string | null;
          current_version_id: string | null;
          id: string | null;
          logical_name: string | null;
          project_id: string | null;
          purpose: string | null;
          task_id: string | null;
          updated_at: string | null;
          version: number | null;
        };
        Insert: {
          created_at?: string | null;
          created_by?: never;
          current_version_id?: string | null;
          id?: string | null;
          logical_name?: never;
          project_id?: string | null;
          purpose?: string | null;
          task_id?: string | null;
          updated_at?: string | null;
          version?: number | null;
        };
        Update: {
          created_at?: string | null;
          created_by?: never;
          current_version_id?: string | null;
          id?: string | null;
          logical_name?: never;
          project_id?: string | null;
          purpose?: string | null;
          task_id?: string | null;
          updated_at?: string | null;
          version?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_files_current_version_same_file_fkey";
            columns: ["id", "current_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_files_current_version_same_file_fkey";
            columns: ["id", "current_version_id"];
            isOneToOne: false;
            referencedRelation: "task_file_versions_visible";
            referencedColumns: ["file_id", "id"];
          },
          {
            foreignKeyName: "task_files_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_files_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_files_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      task_primary_handoffs_visible: {
        Row: {
          canceled_at: string | null;
          created_at: string | null;
          created_by: string | null;
          from_user_id: string | null;
          from_user_name_snapshot: string | null;
          id: string | null;
          project_id: string | null;
          responded_at: string | null;
          state: string | null;
          task_id: string | null;
          to_user_id: string | null;
          to_user_name_snapshot: string | null;
          updated_at: string | null;
          version: number | null;
        };
        Insert: {
          canceled_at?: string | null;
          created_at?: string | null;
          created_by?: string | null;
          from_user_id?: string | null;
          from_user_name_snapshot?: never;
          id?: string | null;
          project_id?: string | null;
          responded_at?: string | null;
          state?: string | null;
          task_id?: string | null;
          to_user_id?: string | null;
          to_user_name_snapshot?: never;
          updated_at?: string | null;
          version?: number | null;
        };
        Update: {
          canceled_at?: string | null;
          created_at?: string | null;
          created_by?: string | null;
          from_user_id?: string | null;
          from_user_name_snapshot?: never;
          id?: string | null;
          project_id?: string | null;
          responded_at?: string | null;
          state?: string | null;
          task_id?: string | null;
          to_user_id?: string | null;
          to_user_name_snapshot?: never;
          updated_at?: string | null;
          version?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_primary_handoffs_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_primary_handoffs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "project_contribution_share_readiness";
            referencedColumns: ["project_id", "task_id"];
          },
          {
            foreignKeyName: "task_primary_handoffs_project_id_task_id_fkey";
            columns: ["project_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
    };
    Functions: {
      account_lifecycle_access_allowed: {
        Args: { p_user: string };
        Returns: boolean;
      };
      cmd_abandon_task_responsibility: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_reason: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_appeal_contribution_penalty: {
        Args: {
          p_expected_version: number;
          p_penalty_id: string;
          p_project_id: string;
          p_reason: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_archive_project: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_reason: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_batch_rollback_task_files: {
        Args: {
          p_expected_version: number;
          p_items: Json;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_cancel_account_deletion: {
        Args: { p_expected_version: number; p_request_id: string };
        Returns: Json;
      };
      cmd_cancel_account_deletion_f2_internal: {
        Args: { p_expected_version: number; p_request_id: string };
        Returns: Json;
      };
      cmd_cancel_task: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_reason: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_cancel_task_primary_handoff: {
        Args: {
          p_expected_handoff_version: number;
          p_expected_task_version: number;
          p_handoff_id: string;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_claim_task: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_compare_task_file_versions: {
        Args: {
          p_base_file_version_id: string;
          p_project_id: string;
          p_request_id: string;
          p_target_file_version_id: string;
        };
        Returns: Json;
      };
      cmd_compare_task_file_versions_f2_internal: {
        Args: {
          p_base_file_version_id: string;
          p_project_id: string;
          p_request_id: string;
          p_target_file_version_id: string;
        };
        Returns: Json;
      };
      cmd_complete_file_version_withdrawal_service: {
        Args: { p_withdrawal_id: string };
        Returns: Json;
      };
      cmd_confirm_contribution_report: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_report_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_confirm_task_shares: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_proposal_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_consent_auto_penalty_policy: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_consent_task_expected_share: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_share_bps: number;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_correct_task_review_request_changes: {
        Args: {
          p_expected_review_version: number;
          p_expected_task_version: number;
          p_project_id: string;
          p_request_id: string;
          p_review_round_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_create_calendar_feed_subscription: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_show_titles?: boolean;
        };
        Returns: Json;
      };
      cmd_create_contribution_report: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_create_external_evidence: {
        Args: {
          p_description: string;
          p_expected_version: number;
          p_https_url: string;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_create_project: {
        Args: {
          p_allow_member_task_creation?: boolean;
          p_contribution_mode?: string;
          p_course_name?: string;
          p_deadline_at?: string;
          p_description?: string;
          p_expected_version?: number;
          p_name?: string;
          p_request_id: string;
          p_require_real_name?: boolean;
          p_require_student_number?: boolean;
          p_start_at?: string;
          p_timezone?: string;
        };
        Returns: Json;
      };
      cmd_create_project_invite: {
        Args: {
          p_expected_version: number;
          p_expires_in_days?: number;
          p_max_uses?: number;
          p_mode: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_create_project_recovery_point: {
        Args: {
          p_expected_version: number;
          p_label?: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_create_task: {
        Args: {
          p_assignee_id?: string;
          p_assignment_mode?: string;
          p_deadline_at?: string;
          p_description?: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_required_submission_file_type?: string;
          p_requires_review?: boolean;
          p_title: string;
          p_weight?: number;
        };
        Returns: Json;
      };
      cmd_create_task_help_request: {
        Args: {
          p_expected_version: number;
          p_marks_task_blocked?: boolean;
          p_message: string;
          p_project_id: string;
          p_request_id: string;
          p_target_user_id?: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_create_task_v2: {
        Args: {
          p_assignee_id?: string;
          p_assignment_mode?: string;
          p_deadline_at?: string;
          p_description?: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_required_submission_file_types?: string[];
          p_requires_review?: boolean;
          p_title: string;
          p_weight?: number;
        };
        Returns: Json;
      };
      cmd_delete_empty_task: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_edit_task: {
        Args: {
          p_deadline_at: string;
          p_description: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_required_submission_file_type?: string;
          p_task_id: string;
          p_title: string;
          p_weight: number;
        };
        Returns: Json;
      };
      cmd_edit_task_v2: {
        Args: {
          p_deadline_at: string;
          p_description: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_required_submission_file_types?: string[];
          p_task_id: string;
          p_title: string;
          p_weight: number;
        };
        Returns: Json;
      };
      cmd_extend_project_retention: {
        Args: {
          p_additional_days: number;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_finalize_task_file_upload_service: {
        Args: {
          p_actor_id: string;
          p_actual_mime_type: string;
          p_actual_size_bytes: number;
          p_expected_version: number;
          p_request_id: string;
          p_reservation_id: string;
          p_sha256_hex: string;
        };
        Returns: Json;
      };
      cmd_invite_task_collaborator: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
          p_user_id: string;
        };
        Returns: Json;
      };
      cmd_join_project_via_invite: {
        Args: {
          p_expected_version: number;
          p_request_id: string;
          p_token: string;
        };
        Returns: Json;
      };
      cmd_leave_project: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_leave_task_collaboration: {
        Args: {
          p_collaborator_id: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_mark_task_file_reference: {
        Args: {
          p_expected_version: number;
          p_file_id: string;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_propose_task_change: {
        Args: {
          p_deadline_at: string;
          p_expected_task_version: number;
          p_project_id: string;
          p_request_id: string;
          p_required_submission_file_type?: string;
          p_task_id: string;
          p_weight: number;
        };
        Returns: Json;
      };
      cmd_propose_task_change_v2: {
        Args: {
          p_deadline_at: string;
          p_expected_task_version: number;
          p_project_id: string;
          p_request_id: string;
          p_required_submission_file_types?: string[];
          p_task_id: string;
          p_weight: number;
        };
        Returns: Json;
      };
      cmd_propose_task_shares: {
        Args: {
          p_allocations: Json;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_record_task_artifact_use: {
        Args: {
          p_downstream_task_id: string;
          p_file_version_id: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_reject_task_file_upload_service: {
        Args: {
          p_actor_id: string;
          p_expected_version: number;
          p_rejection_code: string;
          p_request_id: string;
          p_reservation_id: string;
        };
        Returns: Json;
      };
      cmd_reject_task_shares: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_proposal_id: string;
          p_reason: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_remove_external_evidence: {
        Args: {
          p_evidence_id: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_remove_project_member: {
        Args: {
          p_expected_version: number;
          p_membership_id: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_remove_task_collaborator: {
        Args: {
          p_collaborator_id: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_renew_project_invite: {
        Args: {
          p_expected_version: number;
          p_extend_days?: number;
          p_invitation_id: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_request_account_deletion: {
        Args: { p_expected_version: number; p_request_id: string };
        Returns: Json;
      };
      cmd_request_account_deletion_f2_internal: {
        Args: { p_expected_version: number; p_request_id: string };
        Returns: Json;
      };
      cmd_request_task_primary_handoff: {
        Args: {
          p_expected_task_version: number;
          p_project_id: string;
          p_request_id: string;
          p_target_user_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_request_upstream_rework: {
        Args: {
          p_downstream_task_id: string;
          p_expected_downstream_version: number;
          p_expected_upstream_version: number;
          p_project_id: string;
          p_request_id: string;
          p_requirement: string;
          p_upstream_task_id: string;
        };
        Returns: Json;
      };
      cmd_reserve_task_file_upload: {
        Args: {
          p_declared_mime_type: string;
          p_declared_size_bytes: number;
          p_expected_version: number;
          p_mode: string;
          p_original_name: string;
          p_project_id: string;
          p_request_id: string;
          p_target_file_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_resolve_contribution_appeal: {
        Args: {
          p_appeal_id: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_resolution: Json;
        };
        Returns: Json;
      };
      cmd_resolve_task_help_request: {
        Args: {
          p_expected_version: number;
          p_help_request_id: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_respond_task_primary_handoff: {
        Args: {
          p_action: string;
          p_expected_handoff_version: number;
          p_expected_task_version: number;
          p_handoff_id: string;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_respond_to_task_assignment: {
        Args: {
          p_action: string;
          p_assignment_offer_id: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_respond_to_task_change: {
        Args: {
          p_action: string;
          p_expected_proposal_version: number;
          p_project_id: string;
          p_proposal_id: string;
          p_rejection_reason: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_respond_to_task_collaborator: {
        Args: {
          p_action: string;
          p_collaborator_id: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_restore_project: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_restore_project_recovery_point: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_recovery_point_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_review_project_join_request: {
        Args: {
          p_action: string;
          p_expected_version: number;
          p_join_request_id: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_review_task_submission: {
        Args: {
          p_action: string;
          p_expected_version: number;
          p_project_id: string;
          p_rejection_reason: string;
          p_request_id: string;
          p_review_round_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_review_upstream_rework: {
        Args: {
          p_action: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_rework_request_id: string;
        };
        Returns: Json;
      };
      cmd_revoke_calendar_feed_subscription: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_subscription_id: string;
        };
        Returns: Json;
      };
      cmd_revoke_project_invite: {
        Args: {
          p_expected_version: number;
          p_invitation_id: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_send_task_nudge: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_set_account_entitlement_service: {
        Args: {
          p_expected_version: number;
          p_expires_at: string;
          p_grant_source: string;
          p_granted_by: string;
          p_note: string;
          p_plan: string;
          p_request_id: string;
          p_starts_at: string;
          p_status: string;
          p_user_id: string;
        };
        Returns: Json;
      };
      cmd_set_analytics_coverage_service: {
        Args: {
          p_complete_since: string;
          p_definition_version: number;
          p_note?: string;
          p_source: string;
          p_verified_at: string;
        };
        Returns: Json;
      };
      cmd_set_project_auto_penalty_policy: {
        Args: {
          p_enabled: boolean;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_set_project_entitlement_service: {
        Args: {
          p_expires_at: string;
          p_grant_source: string;
          p_granted_by: string;
          p_note: string;
          p_plan: string;
          p_project_id: string;
          p_request_id: string;
          p_starts_at: string;
          p_status: string;
        };
        Returns: Json;
      };
      cmd_set_project_permission_delegation: {
        Args: {
          p_enabled: boolean;
          p_expected_version: number;
          p_membership_id: string;
          p_project_id: string;
          p_request_id: string;
          p_template_code: string;
        };
        Returns: Json;
      };
      cmd_set_task_artifact_binding_strength: {
        Args: {
          p_downstream_task_id: string;
          p_expected_version: number;
          p_file_version_id: string;
          p_project_id: string;
          p_request_id: string;
          p_strength: string;
        };
        Returns: Json;
      };
      cmd_set_task_dependencies: {
        Args: {
          p_downstream_task_id: string;
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_upstream_task_ids: string[];
        };
        Returns: Json;
      };
      cmd_set_task_file_version_final: {
        Args: {
          p_expected_version: number;
          p_file_version_id: string;
          p_is_final: boolean;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_set_task_reminder_preferences: {
        Args: {
          p_enabled: boolean;
          p_expected_version: number;
          p_offsets_seconds: number[];
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_submit_task_for_review: {
        Args: {
          p_expected_version: number;
          p_file_version_ids: string[];
          p_project_id: string;
          p_request_id: string;
          p_submission_text: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_switch_task_artifact_binding_version: {
        Args: {
          p_downstream_task_id: string;
          p_expected_version: number;
          p_file_version_id: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_transfer_project_leadership: {
        Args: {
          p_expected_version: number;
          p_project_id: string;
          p_request_id: string;
          p_target_membership_id: string;
        };
        Returns: Json;
      };
      cmd_unassign_task_primary: {
        Args: {
          p_expected_task_version: number;
          p_project_id: string;
          p_request_id: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_update_external_evidence: {
        Args: {
          p_description: string;
          p_evidence_id: string;
          p_expected_version: number;
          p_https_url: string;
          p_project_id: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      cmd_update_project_member_role: {
        Args: {
          p_expected_version: number;
          p_membership_id: string;
          p_project_id: string;
          p_request_id: string;
          p_target_role: string;
        };
        Returns: Json;
      };
      cmd_update_project_settings: {
        Args: {
          p_allow_member_task_creation?: boolean;
          p_auto_penalty_enabled: boolean;
          p_contribution_mode: string;
          p_course_name: string;
          p_deadline_at: string;
          p_description: string;
          p_expected_version: number;
          p_name: string;
          p_project_id: string;
          p_request_id: string;
          p_require_real_name: boolean;
          p_require_student_number: boolean;
          p_start_at?: string;
          p_timezone: string;
        };
        Returns: Json;
      };
      cmd_update_task_progress: {
        Args: {
          p_blocked_reason?: string;
          p_expected_version: number;
          p_progress_text: string;
          p_project_id: string;
          p_request_id: string;
          p_status: string;
          p_task_id: string;
        };
        Returns: Json;
      };
      cmd_withdraw_file_version: {
        Args: {
          p_expected_version: number;
          p_file_version_id: string;
          p_project_id: string;
          p_reason: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      dismiss_notification: {
        Args: { p_notification_id: string };
        Returns: boolean;
      };
      dismiss_read_notifications: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      dispatch_contribution_penalty_events_service: {
        Args: { p_batch_limit?: number };
        Returns: Json;
      };
      dispatch_task_reminders_service: {
        Args: { p_batch_limit?: number };
        Returns: number;
      };
      get_account_lifecycle_status: {
        Args: Record<PropertyKey, never>;
        Returns: Json;
      };
      get_analytics_coverage_service: {
        Args: Record<PropertyKey, never>;
        Returns: Json;
      };
      get_enhanced_project_report_export: {
        Args: { p_report_id: string };
        Returns: Json;
      };
      get_my_account_entitlement: {
        Args: Record<PropertyKey, never>;
        Returns: Json;
      };
      get_my_cross_project_access: {
        Args: { p_project_ids?: string[] };
        Returns: Json;
      };
      get_my_cross_project_projects: {
        Args: {
          p_after_project_id?: string;
          p_limit?: number;
          p_search?: string;
        };
        Returns: Json;
      };
      get_project_analytics: {
        Args: { p_from: string; p_project_id: string; p_to: string };
        Returns: Json;
      };
      get_project_calendar_subscriptions: {
        Args: { p_project_id: string };
        Returns: Json;
      };
      get_project_contribution_report: {
        Args: { p_project_id: string };
        Returns: Json;
      };
      get_project_contribution_report_f2_unmasked: {
        Args: { p_project_id: string };
        Returns: Json;
      };
      get_project_contribution_report_legacy: {
        Args: { p_project_id: string };
        Returns: Json;
      };
      get_project_entitlement: {
        Args: { p_project_id: string };
        Returns: Json;
      };
      get_project_permission_delegations: {
        Args: { p_project_id: string };
        Returns: Json;
      };
      get_project_report_export: {
        Args: { p_report_id: string };
        Returns: Json;
      };
      get_project_report_export_f2_unmasked: {
        Args: { p_report_id: string };
        Returns: Json;
      };
      get_project_report_export_legacy: {
        Args: { p_report_id: string };
        Returns: Json;
      };
      get_project_storage_usage: {
        Args: { p_project_id: string };
        Returns: Json;
      };
      get_task_file_history: {
        Args: {
          p_before_version?: number;
          p_file_id: string;
          p_limit?: number;
        };
        Returns: Json;
      };
      get_task_file_history_f2_unmasked: {
        Args: {
          p_before_version?: number;
          p_file_id: string;
          p_limit?: number;
        };
        Returns: Json;
      };
      get_task_files: { Args: { p_task_id: string }; Returns: Json };
      get_task_files_f2_unmasked: {
        Args: { p_task_id: string };
        Returns: Json;
      };
      get_unread_notification_count: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      get_upstream_artifacts: {
        Args: { p_downstream_task_id: string };
        Returns: Json;
      };
      get_upstream_artifacts_f2_unmasked: {
        Args: { p_downstream_task_id: string };
        Returns: Json;
      };
      is_active_project_member: {
        Args: { target_project_id: string };
        Returns: boolean;
      };
      lifecycle_assess_cleanup_service: {
        Args: { p_generation: number; p_request_id: string; p_user: string };
        Returns: Json;
      };
      lifecycle_finalize_auth_revocation_service: {
        Args: { p_generation: number; p_user: string };
        Returns: Json;
      };
      lifecycle_finalize_soft_delete_service: {
        Args: { p_generation: number; p_user: string };
        Returns: Json;
      };
      lifecycle_get_pii_manifest_service: {
        Args: { p_manifest_id: string };
        Returns: Json;
      };
      lifecycle_list_cleanup_candidates_service: {
        Args: { p_batch_limit?: number };
        Returns: {
          execution_allowed: boolean;
          generation: number;
          review_ready: boolean;
          user_id: string;
        }[];
      };
      lifecycle_list_expired_revocation_candidates_service: {
        Args: { p_batch_limit?: number };
        Returns: {
          generation: number;
          user_id: string;
        }[];
      };
      lifecycle_list_soft_delete_candidates_service: {
        Args: { p_batch_limit?: number };
        Returns: {
          generation: number;
          user_id: string;
        }[];
      };
      lifecycle_pii_preflight_service: {
        Args: { p_user: string };
        Returns: Json;
      };
      lifecycle_prepare_soft_delete_service: {
        Args: { p_generation: number; p_user: string };
        Returns: Json;
      };
      lifecycle_record_auth_revocation: {
        Args: { p_generation: number; p_user: string };
        Returns: boolean;
      };
      lifecycle_scan_pii_service: {
        Args: { p_generation: number; p_request_id: string; p_user: string };
        Returns: Json;
      };
      lifecycle_worker_tick: {
        Args: { p_batch_limit?: number };
        Returns: Json;
      };
      list_pending_file_withdrawals_service: {
        Args: { p_batch_limit?: number };
        Returns: {
          original_path: string;
          project_id: string;
          quarantine_path: string;
          withdrawal_id: string;
        }[];
      };
      mark_all_notifications_read: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      mark_notification_read: {
        Args: { p_notification_id: string };
        Returns: boolean;
      };
      ops_assert_access_service: {
        Args: { p_operator_user_id: string };
        Returns: Json;
      };
      ops_get_account_support_summary_service: {
        Args: {
          p_operator_user_id: string;
          p_query: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      ops_get_product_analytics_service: {
        Args: { p_definition_version: number; p_from: string; p_to: string };
        Returns: Json;
      };
      ops_get_product_timeseries_service: {
        Args: {
          p_definition_version: number;
          p_from_date: string;
          p_to_date: string;
        };
        Returns: Json;
      };
      phase2_calendar_feed_lookup: { Args: { p_token: string }; Returns: Json };
      preview_project_invite: { Args: { p_token: string }; Returns: Json };
      process_contribution_penalty_event_service: {
        Args: { p_source_event_id: number };
        Returns: Json;
      };
      resolve_notification_target: {
        Args: { p_notification_id: string };
        Returns: Json;
      };
      restore_notification: {
        Args: { p_notification_id: string };
        Returns: boolean;
      };
      run_analytics_daily_rollup_service: {
        Args: {
          p_definition_version: number;
          p_from_date: string;
          p_to_date: string;
        };
        Returns: Json;
      };
      teamup_active_upload_reservation: {
        Args: { p_object_path: string };
        Returns: boolean;
      };
      teamup_storage_reserved_upload_allowed: {
        Args: { p_object_path: string };
        Returns: boolean;
      };
      teamup_visible_file_version_object: {
        Args: { p_path: string };
        Returns: boolean;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  "public"
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {},
  },
} as const;
