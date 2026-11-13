<script setup lang="ts">
import { computed, onActivated, ref } from "vue";
import { showToast } from "vant";
import { Capacitor } from "@capacitor/core";

import ActiveInviteLinkCard from "@/components/invitation/ActiveInviteLinkCard.vue";
import PageState from "@/components/common/PageState.vue";
import { buildProjectInviteUrl } from "@/platform/project-invite-url";
import { useWorkspaceRoute } from "@/composables/useWorkspaceRoute";
import type { CreateProjectInviteData } from "@/types/commands";

const { workspace, reload } = useWorkspaceRoute();
const mode = ref<"direct" | "approval">("approval");
const expiresInDays = ref(7);
const maxUses = ref(8);
const activeInvites = ref<CreateProjectInviteData[]>([]);
const createOpen = ref(false);
const creating = computed(() => workspace.pendingAction === "invite");
const revokingId = ref<string | null>(null);
const renewingId = ref<string | null>(null);

const visibleInvites = computed(() =>
  activeInvites.value.filter(
    (invite) => Date.parse(invite.expiresAt) > Date.now(),
  ),
);

async function load() {
  await workspace.loadInvitations();
}

function inviteUrl(token: string) {
  return buildProjectInviteUrl(token, {
    isNative: Capacitor.isNativePlatform(),
    webOrigin: window.location.origin,
    backendUrl: import.meta.env.VITE_SUPABASE_URL ?? "",
  });
}

async function createInvite() {
  const result = await workspace.createInvite(
    mode.value,
    expiresInDays.value,
    maxUses.value,
  );
  if (!result.ok) {
    showToast(workspace.actionError || "邀请创建失败");
    return;
  }
  activeInvites.value = [result.data, ...activeInvites.value];
  createOpen.value = false;
  showToast("邀请链接已创建");
}

async function copyInvite(invite: CreateProjectInviteData) {
  try {
    await navigator.clipboard.writeText(inviteUrl(invite.token));
    showToast("已复制");
  } catch {
    showToast("复制失败，请手动复制链接");
  }
}

async function renewInvite(invite: CreateProjectInviteData) {
  renewingId.value = invite.invitationId;
  try {
    const result = await workspace.renewInvite(
      { id: invite.invitationId, version: invite.invitationVersion },
      7,
    );
    if (!result.ok) {
      showToast(workspace.actionError || "邀请续期失败");
      return;
    }
    activeInvites.value = activeInvites.value.map((item) =>
      item.invitationId === invite.invitationId
        ? {
            ...item,
            expiresAt: result.data.expiresAt,
            invitationVersion: result.data.invitationVersion,
          }
        : item,
    );
    showToast("邀请链接已延长 7 天");
  } finally {
    renewingId.value = null;
  }
}

async function stopInvite(invite: CreateProjectInviteData) {
  revokingId.value = invite.invitationId;
  try {
    const result = await workspace.revokeInvite({
      id: invite.invitationId,
      version: invite.invitationVersion,
    });
    if (!result.ok) {
      showToast(workspace.actionError || "停止邀请失败");
      return;
    }
    activeInvites.value = activeInvites.value.filter(
      (item) => item.invitationId !== invite.invitationId,
    );
    showToast("邀请链接已停止");
  } finally {
    revokingId.value = null;
  }
}

async function review(
  request: (typeof workspace.joinRequests)[number],
  action: "approve" | "reject",
) {
  const result = await workspace.reviewJoinRequest(request, action);
  showToast(
    result.ok
      ? action === "approve"
        ? "已批准加入"
        : "已拒绝申请"
      : workspace.actionError || "处理失败",
  );
}

function applicantDisplayName(
  request: (typeof workspace.joinRequests)[number],
) {
  return request.display_name_snapshot?.trim() || "未设置昵称的申请者";
}

onActivated(() => void load());
void load();
</script>

<template>
  <div class="xiaozhuwork-page invitations-page">
    <header class="page-heading">
      <div>
        <h1>邀请成员</h1>
      </div>
      <van-button
        v-if="workspace.capabilities.canManageInvites"
        type="primary"
        @click="createOpen = !createOpen"
      >
        {{ createOpen ? "收起" : "创建邀请链接" }}
      </van-button>
    </header>

    <PageState
      :loading="workspace.loading"
      :error="workspace.error"
      :not-found-or-denied="!workspace.project || !workspace.membership"
      :permission-denied="
        !!workspace.membership && !workspace.capabilities.canManageInvites
      "
      @retry="
        async () => {
          await reload();
          await load();
        }
      "
    >
      <template v-if="workspace.capabilities.canManageInvites">
        <section v-if="createOpen" class="surface invite-create">
          <div class="section-heading">
            <h2>创建邀请链接</h2>
            <p>设置加入方式和有效期；链接本身只在创建成功后展示。</p>
          </div>
          <div class="invite-fields">
            <label>
              <span>加入方式</span>
              <select v-model="mode">
                <option value="approval">需要审批</option>
                <option value="direct">直接加入</option>
              </select>
            </label>
            <label>
              <span>有效天数</span>
              <input
                v-model.number="expiresInDays"
                type="number"
                min="1"
                max="30"
              />
            </label>
            <label>
              <span>最多使用次数</span>
              <input v-model.number="maxUses" type="number" min="1" max="8" />
            </label>
          </div>
          <van-button type="primary" :loading="creating" @click="createInvite">
            创建链接
          </van-button>
        </section>

        <section class="active-links">
          <div class="active-heading">
            <div>
              <h2>当前邀请链接</h2>
              <p>只展示当前会话中仍有效、未停止的可操作链接。</p>
            </div>
            <span>{{ visibleInvites.length }} 个</span>
          </div>

          <div v-if="visibleInvites.length" class="active-list">
            <ActiveInviteLinkCard
              v-for="invite in visibleInvites"
              :key="invite.invitationId"
              :url="inviteUrl(invite.token)"
              :expires-at="invite.expiresAt"
              :busy="
                revokingId === invite.invitationId ||
                renewingId === invite.invitationId
              "
              :renewable="true"
              @copy="copyInvite(invite)"
              @renew="renewInvite(invite)"
              @stop="stopInvite(invite)"
            />
          </div>
          <div v-else class="surface empty-active">
            <strong>当前没有可展示的邀请链接</strong>
            <p>创建新链接后会在这里出现。</p>
          </div>

          <div class="capability-note">
            为保护邀请链接，页面刷新后不会再次显示已经创建过的原始链接。如需再次分享，请创建一个新链接。
          </div>
        </section>

        <section class="surface join-requests">
          <div class="active-heading">
            <div>
              <h2>待处理加入申请</h2>
              <p>这里只显示仍需要决定的申请，不作为邀请历史记录。</p>
            </div>
          </div>
          <div
            v-if="
              workspace.joinRequests.filter((item) => item.state === 'pending')
                .length
            "
            class="request-list"
          >
            <article
              v-for="request in workspace.joinRequests.filter(
                (item) => item.state === 'pending',
              )"
              :key="request.id"
            >
              <div>
                <strong>{{ applicantDisplayName(request) }}</strong>
                <span>
                  申请加入 ·
                  {{ new Date(request.created_at).toLocaleString("zh-CN") }}
                </span>
              </div>
              <div class="request-actions">
                <button type="button" @click="review(request, 'approve')">
                  批准
                </button>
                <button type="button" @click="review(request, 'reject')">
                  拒绝
                </button>
              </div>
            </article>
          </div>
          <p v-else class="empty-request">当前没有待处理加入申请。</p>
        </section>
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.invitations-page {
}
.invite-create {
  display: grid;
  gap: 16px;
  padding: 20px;
  margin-bottom: 22px;
}
.section-heading h2,
.active-heading h2 {
  margin: 0;
  font-size: 18px;
}
.section-heading p,
.active-heading p {
  margin: 5px 0 0;
  color: var(--tu-muted);
  font-size: 13px;
}
.invite-fields {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
}
.invite-fields label {
  display: grid;
  gap: 6px;
}
.invite-fields span {
  color: var(--tu-muted);
  font-size: 13px;
}
.invite-fields select,
.invite-fields input {
  min-height: 42px;
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  padding: 0 10px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.active-links {
  display: grid;
  gap: 10px;
  margin-bottom: 22px;
}
.active-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 12px;
}
.active-heading > span {
  color: var(--tu-muted);
  font-size: 13px;
}
.active-list {
  display: grid;
  gap: 10px;
}
.empty-active {
  padding: 22px;
}
.empty-active p,
.empty-request {
  margin: 6px 0 0;
  color: var(--tu-muted);
}
.join-requests {
  overflow: hidden;
}
.join-requests > .active-heading {
  padding: 18px;
  border-bottom: 1px solid var(--tu-border);
}
.request-list article {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 14px 18px;
  border-bottom: 1px solid var(--tu-border);
}
.request-list article:last-child {
  border-bottom: 0;
}
.request-list strong,
.request-list span {
  display: block;
}
.request-list span {
  margin-top: 4px;
  color: var(--tu-muted);
  font-size: 12px;
}
.request-actions {
  display: flex;
  gap: 8px;
}
.request-actions button {
  min-height: 36px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 0 11px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  cursor: pointer;
}
.empty-request {
  padding: 18px;
}
@media (max-width: 680px) {
  .invite-fields {
    grid-template-columns: 1fr;
  }
  .request-list article,
  .active-heading {
    align-items: start;
    flex-direction: column;
  }
}
</style>
