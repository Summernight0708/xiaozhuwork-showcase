import { useHelpStore } from "@/stores/help";
import { useNotificationsStore } from "@/stores/notifications";
import { useProjectsStore } from "@/stores/projects";
import { useTaskNavigationStore } from "@/stores/task-navigation";
import { useWorkspaceStore } from "@/stores/workspace";

export function clearSessionScopedState() {
  useProjectsStore().reset();
  useNotificationsStore().reset();
  useWorkspaceStore().reset();
  useTaskNavigationStore().reset();
  useHelpStore().reset();
}
