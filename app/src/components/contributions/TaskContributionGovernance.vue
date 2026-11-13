<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showToast } from "vant";
import type { SupabaseClient } from "@supabase/supabase-js";

import ContributionSharesPanel from "@/components/contributions/ContributionSharesPanel.vue";
import ContributionPenaltyPanel from "@/components/contributions/ContributionPenaltyPanel.vue";
import { getBackend } from "@/services/backend";

interface Participant {
  userId: string;
  name: string;
}
type RecordObject = Record<string, unknown>;
interface Proposal {
  id: string;
  version: number;
  status: "pending" | "confirmed" | "superseded";
}
interface Allocation {
  member_user_id: string | null;
  share_bps: number;
}
interface Confirmation {
  member_user_id: string | null;
}
interface Penalty {
  id: string;
  member_user_id: string | null;
  kind: "late" | "abandon";
  source_event_id: number;
  base_amount: number;
  rate: number;
  amount: number;
  duration_seconds: number;
  delay_seconds: number;
  event_snapshot: RecordObject;
}
interface Appeal {
  id: string;
  penalty_id: string;
  status: string;
  version: number;
}

const props = defineProps<{
  projectId: string;
  taskId: string;
  taskVersion: number;
  participants: Participant[];
  userId: string | null;
  isPrimary: boolean;
  taskCompleted: boolean;
  canWrite: boolean;
}>();
const emit = defineEmits<{ changed: [] }>();

const proposal = ref<Proposal | null>(null);
const allocations = ref<Allocation[]>([]);
const confirmations = ref<Confirmation[]>([]);
const penalties = ref<Penalty[]>([]);
const appeals = ref<Appeal[]>([]);
const voted = ref<string[]>([]);
const busy = ref(false);
const loading = ref(false);
const error = ref("");
const retry = ref<{ fingerprint: string; requestId: string } | null>(null);

function client(): SupabaseClient {
  const backend = getBackend();
  if (!backend) throw new Error("当前无法连接服务器");
  return backend.client as unknown as SupabaseClient;
}
function requireSuccess(data: unknown) {
  const response = data as { ok?: boolean; code?: string } | null;
  if (!response?.ok) throw new Error(response?.code ?? "服务器拒绝了操作");
}
function idFor(payload: unknown) {
  const fingerprint = JSON.stringify(payload);
  if (retry.value?.fingerprint !== fingerprint)
    retry.value = { fingerprint, requestId: crypto.randomUUID() };
  return retry.value.requestId;
}
async function load() {
  loading.value = true;
  error.value = "";
  try {
    const api = client();
    const [proposals, penaltyRows] = await Promise.all([
      api
        .from("task_share_proposals")
        .select("id,version,status")
        .eq("project_id", props.projectId)
        .eq("task_id", props.taskId)
        .order("revision", { ascending: false })
        .limit(1),
      api
        .from("contribution_penalties")
        .select(
          "id,member_user_id,kind,source_event_id,base_amount,rate,amount,duration_seconds,delay_seconds,event_snapshot",
        )
        .eq("project_id", props.projectId)
        .eq("task_id", props.taskId),
    ]);
    if (proposals.error) throw proposals.error;
    if (penaltyRows.error) throw penaltyRows.error;
    proposal.value = (proposals.data?.[0] ?? null) as Proposal | null;
    penalties.value = (penaltyRows.data ?? []) as Penalty[];
    allocations.value = [];
    confirmations.value = [];
    appeals.value = [];
    voted.value = [];
    if (proposal.value) {
      const id = proposal.value.id;
      const [allocationResponse, confirmationResponse] = await Promise.all([
        api
          .from("task_share_allocations")
          .select("member_user_id,share_bps")
          .eq("proposal_id", id),
        api
          .from("task_share_confirmations")
          .select("member_user_id")
          .eq("proposal_id", id),
      ]);
      if (allocationResponse.error) throw allocationResponse.error;
      if (confirmationResponse.error) throw confirmationResponse.error;
      allocations.value = (allocationResponse.data ?? []) as Allocation[];
      confirmations.value = (confirmationResponse.data ?? []) as Confirmation[];
    }
    if (penalties.value.length) {
      const ids = penalties.value.map((p) => p.id);
      const appealResponse = await api
        .from("contribution_penalty_appeals")
        .select("id,penalty_id,status,version")
        .eq("project_id", props.projectId)
        .in("penalty_id", ids);
      if (appealResponse.error) throw appealResponse.error;
      appeals.value = (appealResponse.data ?? []) as Appeal[];
      const pendingAppealIds = appeals.value
        .filter((a) => a.status === "pending")
        .map((a) => a.id);
      if (pendingAppealIds.length && props.userId) {
        const votesResponse = await api
          .from("contribution_appeal_votes")
          .select("appeal_id")
          .in("appeal_id", pendingAppealIds)
          .eq("voter_id", props.userId);
        if (votesResponse.error) throw votesResponse.error;
        voted.value = (votesResponse.data ?? []).map(
          (row) => row.appeal_id as string,
        );
      }
    }
  } catch (caught) {
    error.value =
      caught instanceof Error ? caught.message : "读取贡献治理记录失败";
  } finally {
    loading.value = false;
  }
}
watch(
  () => [props.projectId, props.taskId, props.taskVersion],
  () => void load(),
  { immediate: true },
);

const shareMembers = computed(() =>
  props.participants.map((member) => ({
    ...member,
    shareBps:
      allocations.value.find((item) => item.member_user_id === member.userId)
        ?.share_bps ?? 0,
    confirmed: confirmations.value.some(
      (item) => item.member_user_id === member.userId,
    ),
  })),
);
const canPropose = computed(
  () =>
    props.canWrite &&
    props.taskCompleted &&
    props.isPrimary &&
    props.participants.length > 0 &&
    proposal.value?.status !== "pending" &&
    proposal.value?.status !== "confirmed",
);
const canConfirm = computed(
  () =>
    props.canWrite &&
    props.taskCompleted &&
    !!props.userId &&
    proposal.value?.status === "pending" &&
    allocations.value.some((row) => row.member_user_id === props.userId) &&
    !confirmations.value.some((row) => row.member_user_id === props.userId),
);

function appealFor(penaltyId: string) {
  return appeals.value.find(
    (a) => a.penalty_id === penaltyId && a.status === "pending",
  );
}
function penaltyUi(penalty: Penalty) {
  const data = penalty.event_snapshot ?? {};
  return {
    id: penalty.id,
    kind: penalty.kind,
    sourceEventId: String(penalty.source_event_id),
    effectiveStartAt: String(data.effectiveStartAt ?? "未知"),
    effectiveDeadlineAt: String(data.effectiveDeadlineAt ?? "未知"),
    occurredAt: String(data.occurredAt ?? "未知"),
    durationSeconds: penalty.duration_seconds,
    delaySeconds: penalty.delay_seconds,
    baseAmount: String(penalty.base_amount),
    ratePercent: Math.round(Number(penalty.rate) * 10000) / 100,
    amount: String(penalty.amount),
  };
}
async function perform(kind: string, params: Record<string, unknown>) {
  if (busy.value || !props.canWrite) return;
  busy.value = true;
  error.value = "";
  try {
    const requestId = idFor({ kind, params });
    const response = await client().rpc(kind, {
      ...params,
      p_request_id: requestId,
    });
    if (response.error) throw response.error;
    requireSuccess(response.data);
    retry.value = null;
    showToast("贡献治理记录已更新");
    await load();
    emit("changed");
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : "操作失败";
  } finally {
    busy.value = false;
  }
}
function propose(shares: { userId: string; shareBps: number }[]) {
  void perform("cmd_propose_task_shares", {
    p_project_id: props.projectId,
    p_task_id: props.taskId,
    p_allocations: shares,
    p_expected_version: props.taskVersion,
  });
}
function confirm(proposalId: string, expectedVersion: number) {
  void perform("cmd_confirm_task_shares", {
    p_project_id: props.projectId,
    p_proposal_id: proposalId,
    p_expected_version: expectedVersion,
  });
}
function reject(proposalId: string, expectedVersion: number, reason: string) {
  void perform("cmd_reject_task_shares", {
    p_project_id: props.projectId,
    p_proposal_id: proposalId,
    p_expected_version: expectedVersion,
    p_reason: reason,
  });
}
function appeal(penaltyId: string, reason: string) {
  void perform("cmd_appeal_contribution_penalty", {
    p_project_id: props.projectId,
    p_penalty_id: penaltyId,
    p_expected_version: 1,
    p_reason: reason,
  });
}
function vote(
  appealId: string,
  version: number,
  resolution: { decision: string; targetAmount?: string },
) {
  void perform("cmd_resolve_contribution_appeal", {
    p_project_id: props.projectId,
    p_appeal_id: appealId,
    p_expected_version: version,
    p_resolution: resolution,
  });
}
</script>

<template>
  <section class="governance" aria-label="任务贡献治理">
    <div class="governance__head">
      <h3>实际贡献与申诉</h3>
      <button type="button" :disabled="loading || busy" @click="load">
        刷新记录
      </button>
    </div>
    <p v-if="error" role="alert" class="governance__error">{{ error }}</p>
    <p v-if="loading" role="status">加载贡献记录中…</p>
    <template v-else>
      <ContributionSharesPanel
        v-if="taskCompleted && participants.length"
        :members="shareMembers"
        :can-propose="canPropose"
        :can-confirm="canConfirm"
        :proposal-id="proposal?.id"
        :proposal-version="proposal?.version"
        :state="proposal?.status"
        :busy="busy"
        @propose="propose"
        @confirm="confirm"
        @reject="reject"
      />
      <p v-if="taskCompleted && !proposal" class="governance__info">
        尚无已确认的实际贡献比例；不得将未确认数据计入新的正式贡献报告。
      </p>
      <div v-if="penalties.length" class="governance__penalties">
        <ContributionPenaltyPanel
          v-for="penalty in penalties"
          :key="penalty.id"
          :penalty="penaltyUi(penalty)"
          :can-appeal="
            canWrite &&
            penalty.member_user_id === userId &&
            !appeals.some((a) => a.penalty_id === penalty.id)
          "
          :can-vote="
            canWrite &&
            !!appealFor(penalty.id) &&
            !!userId &&
            penalty.member_user_id !== userId &&
            !voted.includes(appealFor(penalty.id)!.id)
          "
          :appeal-id="appealFor(penalty.id)?.id"
          :appeal-version="appealFor(penalty.id)?.version"
          :busy="busy"
          @appeal="appeal"
          @vote="vote"
        />
      </div>
      <p v-if="!penalties.length">当前无贡献扣减记录。</p>
    </template>
  </section>
</template>

<style scoped>
.governance {
  display: grid;
  gap: 1rem;
}
.governance__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
}
.governance__head h3 {
  font-size: 1rem;
  margin: 0;
}
.governance__head button {
  min-height: 36px;
  padding: 0.4rem 0.8rem;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.governance__error {
  color: var(--tu-danger);
}
.governance__info {
  font-size: 0.875rem;
}
.governance__penalties {
  display: grid;
  gap: 1.5rem;
}
</style>
