<script setup lang="ts">
import { computed, ref } from "vue";
interface Penalty {
  id: string;
  kind: "late" | "abandon";
  sourceEventId: string;
  effectiveStartAt: string;
  effectiveDeadlineAt: string;
  occurredAt: string;
  durationSeconds: number;
  delaySeconds: number;
  baseAmount: string;
  ratePercent: number;
  amount: string;
}
const props = defineProps<{
  penalty: Penalty;
  canAppeal: boolean;
  canVote: boolean;
  appealId?: string;
  appealVersion?: number;
  busy?: boolean;
}>();
const emit = defineEmits<{
  appeal: [penaltyId: string, reason: string];
  vote: [
    appealId: string,
    version: number,
    resolution: { decision: string; targetAmount?: string },
  ];
}>();
const reason = ref("");
const decision = ref<"maintain" | "reduce" | "revoke">("maintain");
const targetAmount = ref("");
const appealValid = computed(
  () => reason.value.trim().length > 0 && reason.value.length <= 2000,
);
const voteValid = computed(
  () =>
    decision.value !== "reduce" ||
    /^-?\d+(\.\d{1,4})?$/.test(targetAmount.value),
);
function appeal() {
  if (props.canAppeal && !props.busy && appealValid.value)
    emit("appeal", props.penalty.id, reason.value.trim());
}
function vote() {
  if (
    !props.canVote ||
    !props.appealId ||
    !props.appealVersion ||
    !voteValid.value ||
    props.busy
  )
    return;
  emit(
    "vote",
    props.appealId,
    props.appealVersion,
    decision.value === "reduce"
      ? { decision: decision.value, targetAmount: targetAmount.value }
      : { decision: decision.value },
  );
}
</script>
<template>
  <section class="penalty" aria-label="贡献扣减与申诉">
    <h3>扣减依据</h3>
    <dl>
      <div>
        <dt>触发事件</dt>
        <dd>{{ penalty.kind === "late" ? "首次提交逾期" : "本人超窗放弃" }}</dd>
      </div>
      <div>
        <dt>有效起点</dt>
        <dd>{{ penalty.effectiveStartAt }}</dd>
      </div>
      <div>
        <dt>有效截止</dt>
        <dd>{{ penalty.effectiveDeadlineAt }}</dd>
      </div>
      <div>
        <dt>实际时间</dt>
        <dd>{{ penalty.occurredAt }}</dd>
      </div>
      <div>
        <dt>责任时长 / 延时</dt>
        <dd>{{ penalty.durationSeconds }} / {{ penalty.delaySeconds }} 秒</dd>
      </div>
      <div>
        <dt>基数 × 比率</dt>
        <dd>{{ penalty.baseAmount }} × {{ penalty.ratePercent }}%</dd>
      </div>
      <div>
        <dt>扣减</dt>
        <dd>{{ penalty.amount }}</dd>
      </div>
      <div>
        <dt>源事件</dt>
        <dd>{{ penalty.sourceEventId }}</dd>
      </div>
    </dl>
    <form v-if="canAppeal && !appealId" @submit.prevent="appeal">
      <label for="e-appeal-reason">申诉理由</label>
      <textarea
        id="e-appeal-reason"
        v-model="reason"
        maxlength="2000"
        required
        rows="3"
        :disabled="busy"
      ></textarea>
      <button type="submit" :disabled="busy || !appealValid">
        提交本人申诉
      </button>
    </form>
    <form v-if="canVote && appealId" @submit.prevent="vote">
      <label for="e-appeal-decision">我的独立处理意见</label>
      <select id="e-appeal-decision" v-model="decision" :disabled="busy">
        <option value="maintain">维持</option>
        <option value="reduce">降低</option>
        <option value="revoke">撤销</option>
      </select>
      <label v-if="decision === 'reduce'" for="e-appeal-target"
        >调整后负数金额</label
      >
      <input
        v-if="decision === 'reduce'"
        id="e-appeal-target"
        v-model="targetAmount"
        inputmode="decimal"
        placeholder="-0.2500"
        :disabled="busy"
      />
      <button type="submit" :disabled="busy || !voteValid">提交独立投票</button>
    </form>
    <small
      >申诉通过仅追加调整记录，不修改原始扣减，也不恢复已释放的任务责任。</small
    >
    <small>仅供协作参考，不代表教师评分或成员能力评价。</small>
  </section>
</template>
<style scoped>
.penalty {
  display: grid;
  gap: 0.75rem;
  max-width: 42rem;
}
h3,
dl {
  margin: 0;
}
dl div {
  display: flex;
  justify-content: space-between;
  gap: 0.75rem;
  flex-wrap: wrap;
  border-bottom: 1px solid var(--tu-border);
  padding: 0.4rem 0;
}
dt {
  opacity: 0.8;
}
dd {
  margin: 0;
  overflow-wrap: anywhere;
}
form {
  display: grid;
  gap: 0.5rem;
}
button {
  justify-self: start;
  padding: 0.5rem 0.8rem;
}
button:disabled {
  opacity: 0.5;
}
input,
textarea,
select {
  padding: 0.5rem;
  min-width: 0;
  background: transparent;
  color: inherit;
}
</style>
