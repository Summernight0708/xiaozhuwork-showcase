<script setup lang="ts">
import { computed, ref, watch } from "vue";
interface Member {
  userId: string;
  name: string;
  shareBps: number;
  confirmed?: boolean;
}
const props = defineProps<{
  members: Member[];
  canPropose: boolean;
  canConfirm: boolean;
  proposalId?: string;
  proposalVersion?: number;
  state?: "pending" | "confirmed" | "superseded";
  busy?: boolean;
}>();
const emit = defineEmits<{
  propose: [shares: { userId: string; shareBps: number }[]];
  confirm: [proposalId: string, expectedVersion: number];
  reject: [proposalId: string, expectedVersion: number, reason: string];
}>();
const rejectionReason = ref("");
function reject() {
  if (
    !props.canConfirm ||
    props.busy ||
    !props.proposalId ||
    !props.proposalVersion
  )
    return;
  const reason = rejectionReason.value.trim();
  if (!reason || reason.length > 2000) return;
  emit("reject", props.proposalId, props.proposalVersion, reason);
}
const values = ref<Record<string, string>>({});
watch(
  () => props.members,
  (members) => {
    values.value = Object.fromEntries(
      members.map((m) => [m.userId, (m.shareBps / 100).toFixed(2)]),
    );
  },
  { immediate: true },
);
const shares = computed(() =>
  props.members.map((m) => ({
    userId: m.userId,
    bpsRaw: Number(values.value[m.userId]) * 100,
  })),
);
const total = computed(() => shares.value.reduce((n, m) => n + m.bpsRaw, 0));
const valid = computed(
  () =>
    total.value === 10000 &&
    shares.value.every(
      (m) => Number.isInteger(m.bpsRaw) && m.bpsRaw >= 0 && m.bpsRaw <= 10000,
    ),
);
function propose() {
  if (!props.canPropose || props.busy || !valid.value) return;
  emit(
    "propose",
    shares.value.map((m) => ({ userId: m.userId, shareBps: m.bpsRaw })),
  );
}
</script>
<template>
  <section class="shares" aria-label="实际贡献比例">
    <h3>实际贡献比例</h3>
    <p>任务星级总池固定，全部参与者逐人确认后才可纳入正式贡献汇总。</p>
    <form @submit.prevent="propose">
      <div v-for="member in members" :key="member.userId" class="member">
        <label :for="'share-' + member.userId">{{ member.name }}</label>
        <input
          :id="'share-' + member.userId"
          v-model="values[member.userId]"
          type="number"
          min="0"
          max="100"
          step="0.01"
          :disabled="!canPropose || busy"
        />
        <span>% · {{ member.confirmed ? "已确认" : "待本人确认" }}</span>
      </div>
      <p :aria-invalid="!valid">
        总计 {{ (total / 100).toFixed(2) }}% / 100.00%
      </p>
      <button v-if="canPropose" :disabled="!valid || busy" type="submit">
        提交比例提案
      </button>
    </form>
    <p v-if="state === 'pending'" role="status">
      待全员确认，暂不计入正式贡献。
    </p>
    <p v-else-if="state === 'confirmed'" role="status">当前比例已确认生效。</p>
    <button
      v-if="canConfirm && state === 'pending' && proposalId && proposalVersion"
      :disabled="busy"
      @click="emit('confirm', proposalId, proposalVersion)"
    >
      确认我的比例
    </button>
    <form
      v-if="canConfirm && state === 'pending' && proposalId && proposalVersion"
      @submit.prevent="reject"
    >
      <label for="e-share-rejection">比例有异议？请说明理由</label>
      <textarea
        id="e-share-rejection"
        v-model="rejectionReason"
        rows="2"
        maxlength="2000"
        :disabled="busy"
        required
      />
      <button type="submit" :disabled="busy || !rejectionReason.trim()">
        拒绝此提案并要求重新分配
      </button>
    </form>
    <small>拒绝将保存审计记录，已确认的其他成员不会被视为同意新提案。</small>
    <small>仅供协作参考，不代表教师评分或成员能力评价。</small>
  </section>
</template>
<style scoped>
.shares {
  display: grid;
  gap: 0.75rem;
  max-width: 42rem;
}
h3,
p {
  margin: 0;
}
.member {
  display: grid;
  grid-template-columns: 1fr 7rem 9rem;
  gap: 0.5rem;
  align-items: center;
}
input,
textarea {
  padding: 0.5rem;
  border: 1px solid var(--color-rule-strong);
  border-radius: 0.5rem;
  min-width: 0;
  background: transparent;
  color: inherit;
}
button {
  justify-self: start;
  padding: 0.6rem 0.8rem;
  border-radius: 0.5rem;
}
button:disabled {
  opacity: 0.5;
}
@media (max-width: 560px) {
  .member {
    grid-template-columns: 1fr 7rem;
  }
  .member span {
    grid-column: 1 / -1;
  }
}
</style>
