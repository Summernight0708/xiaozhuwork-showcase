<script setup lang="ts">
import { checkedPrivacyRow } from "@/domain/privacy-view-rows";
import ContextHelpLink from "@/components/help/ContextHelpLink.vue";
import { computed, onActivated, onMounted, ref, watch } from "vue";
import { useRoute } from "vue-router";

import MemberPermissionDelegation from "@/components/permissions/MemberPermissionDelegation.vue";
import PermissionDelegationStatus from "@/components/permissions/PermissionDelegationStatus.vue";
import PermissionTemplateList from "@/components/permissions/PermissionTemplateList.vue";
import { getBackend } from "@/services/backend";
import {
  createProjectPermissionsService,
  permissionErrorMessage,
  type PermissionMember,
  type PermissionSnapshot,
  type ProjectPermissionTemplate,
  type PermissionRpcClient,
} from "@/services/project-permissions";

const route = useRoute();
const projectId = computed(() =>
  String(route.params.projectId ?? route.params.id ?? ""),
);
const snapshot = ref<PermissionSnapshot | null>(null);
const projectState = ref<"free" | "active" | "grace" | "unknown">("unknown");
const members = ref<PermissionMember[]>([]);
const loading = ref(false);
const pendingMemberId = ref<string | null>(null);
const error = ref("");
const notice = ref("");

function service() {
  const backend = getBackend();
  if (!backend) throw new Error("Supabase not configured");
  return createProjectPermissionsService(
    backend.client as unknown as PermissionRpcClient,
  );
}

async function refresh() {
  if (!projectId.value) return;
  loading.value = true;
  error.value = "";
  try {
    const id = projectId.value;
    const [current, entitlement] = await Promise.all([
      service().get(id),
      getBackend()!.client.rpc("get_project_entitlement", { p_project_id: id }),
    ]);
    if (projectId.value !== id) return;
    snapshot.value = current;
    const ent = entitlement.data as { state?: unknown } | null;
    projectState.value =
      ent?.state === "free" || ent?.state === "active" || ent?.state === "grace"
        ? ent.state
        : "unknown";
    members.value = [];
    if (current.viewerRole === "leader") {
      const { data, error: dbError } = await getBackend()!
        .client.from("project_members_visible")
        .select("id,display_name_snapshot,role,member_state,version")
        .eq("project_id", id)
        .eq("member_state", "active")
        .eq("role", "member")
        .order("joined_at", { ascending: true });
      if (dbError) throw new Error("Unable to load project members");
      if (projectId.value !== id) return;
      members.value = (data ?? []).map((row) => {
        const member = checkedPrivacyRow("project_members", row);
        return {
          id: member.id,
          displayName: member.display_name_snapshot?.trim() || "未命名成员",
          role: member.role,
          version: member.version,
        };
      });
    }
  } catch (err) {
    error.value = permissionErrorMessage(err);
  } finally {
    loading.value = false;
  }
}

async function changeDelegation(
  membershipId: string,
  templateCode: ProjectPermissionTemplate,
  enabled: boolean,
  expectedVersion: number,
) {
  if (pendingMemberId.value || !snapshot.value || !canEdit.value) return;
  pendingMemberId.value = membershipId;
  error.value = "";
  notice.value = "";
  try {
    await service().set({
      projectId: projectId.value,
      membershipId,
      templateCode,
      enabled,
      expectedVersion,
      requestId: crypto.randomUUID(),
    });
    notice.value = enabled ? "权限已授予" : "权限已撤销";
  } catch (err) {
    error.value = permissionErrorMessage(err);
  } finally {
    pendingMemberId.value = null;
    await refresh();
  }
}

const canEdit = computed(
  () =>
    snapshot.value?.viewerRole === "leader" &&
    snapshot.value.capability.effective,
);

watch(projectId, () => {
  snapshot.value = null;
  void refresh();
});
onMounted(() => void refresh());
onActivated(() => void refresh());
</script>

<template>
  <div class="xiaozhuwork-page project-permissions-page">
    <header class="page-heading">
      <div>
        <div class="page-title-line">
          <h1>高级权限</h1>
          <ContextHelpLink example-id="advanced-permissions" />
        </div>
      </div>
      <button
        class="refresh-button"
        :disabled="loading"
        type="button"
        @click="refresh"
      >
        刷新服务端状态
      </button>
    </header>

    <p v-if="error" role="alert" class="error-message">{{ error }}</p>
    <p v-if="notice" role="status">{{ notice }}</p>
    <p v-if="loading" role="status">正在同步权限…</p>
    <template v-if="snapshot">
      <PermissionDelegationStatus
        :released="snapshot.capability.released"
        :entitled="snapshot.capability.entitled"
        :project-state="projectState"
        :viewer-role="snapshot.viewerRole"
      />
      <PermissionTemplateList />
      <MemberPermissionDelegation
        v-if="snapshot.viewerRole === 'leader'"
        :members="members"
        :snapshot="snapshot"
        :pending-member-id="pendingMemberId"
        :can-edit="canEdit"
        @change="changeDelegation"
      />
      <section v-else class="surface readonly-message">
        <p>只有组长能分配和撤销模板。你只能查看自己被授权的权限。</p>
        <p v-for="item in snapshot.delegations" :key="item.delegationId">
          {{
            item.templateCode === "invitation_coordinator"
              ? "邀请管理员"
              : "入组审核员"
          }}：
          {{ item.effective ? "生效中" : "暂不生效" }}
        </p>
      </section>
    </template>
  </div>
</template>

<style scoped>
.project-permissions-page {
  display: grid;
  gap: 1rem;
  min-width: 0;
}
.page-heading {
  display: flex;
  justify-content: space-between;
  align-items: start;
  flex-wrap: wrap;
  gap: 1rem;
}
.refresh-button {
  border: 1px solid var(--tu-blue-strong);
  border-radius: 0.5rem;
  background: var(--tu-surface);
  color: var(--tu-blue-strong);
  padding: 0.6rem 0.9rem;
  min-height: 44px;
}
.error-message {
  color: var(--tu-danger);
}
.readonly-message {
  padding: 1rem;
}
</style>
