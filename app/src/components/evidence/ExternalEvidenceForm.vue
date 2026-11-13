<script setup lang="ts">
import { ref, watch } from "vue";
import type { EvidenceDraft } from "@/features/external-evidence/types";
import { validateEvidenceUrl } from "@/features/external-evidence/url";

const props = withDefaults(
  defineProps<{
    initial?: EvidenceDraft;
    busy?: boolean;
    disabled?: boolean;
    editing?: boolean;
  }>(),
  { initial: undefined, busy: false, disabled: false, editing: false },
);
const emit = defineEmits<{ submit: [draft: EvidenceDraft]; cancel: [] }>();
const httpsUrl = ref("");
const description = ref("");
const error = ref("");
watch(
  () => props.initial,
  (draft) => {
    httpsUrl.value = draft?.httpsUrl ?? "";
    description.value = draft?.description ?? "";
    error.value = "";
  },
  { immediate: true },
);
function submit() {
  if (props.busy || props.disabled) return;
  if (!validateEvidenceUrl(httpsUrl.value)) {
    error.value =
      "请输入公开域名的 HTTPS 链接，不支持账号密码、IP 地址或内网地址。";
    return;
  }
  if ([...description.value.trim()].length > 2000) {
    error.value = "证据说明最多 2000 字。";
    return;
  }
  error.value = "";
  emit("submit", { httpsUrl: httpsUrl.value, description: description.value });
}
</script>

<template>
  <form class="evidence-form" @submit.prevent="submit">
    <label
      >HTTPS 链接
      <input
        v-model="httpsUrl"
        type="url"
        required
        maxlength="2048"
        autocomplete="off"
        placeholder="https://…"
        :disabled="busy || disabled"
      />
    </label>
    <label
      >证据说明（可选）
      <textarea
        v-model="description"
        maxlength="2000"
        rows="3"
        placeholder="说明此链接与任务成果的关系"
        :disabled="busy || disabled"
      />
    </label>
    <p class="evidence-note">
      仅保存链接及说明，不读取外部正文；外部内容可能变更或失效，无法在站内回滚。请勿填写私密凭据。
    </p>
    <p v-if="error" role="alert">{{ error }}</p>
    <div class="evidence-actions">
      <button type="submit" :disabled="busy || disabled">
        {{ busy ? "保存中…" : editing ? "保存修改" : "添加证据" }}
      </button>
      <button
        v-if="editing"
        type="button"
        :disabled="busy || disabled"
        @click="emit('cancel')"
      >
        取消编辑
      </button>
    </div>
  </form>
</template>

<style scoped>
.evidence-form,
label {
  display: grid;
  gap: 0.5rem;
}
.evidence-form {
  gap: 0.75rem;
}
input,
textarea {
  box-sizing: border-box;
  width: 100%;
  min-height: 2.75rem;
  padding: 0.65rem;
  color: inherit;
  background: var(--van-background-2, transparent);
  border: 1px solid var(--tu-border);
  border-radius: 0.5rem;
  font: inherit;
}
.evidence-note {
  font-size: 0.875rem;
  line-height: 1.5;
}
.evidence-actions {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
}
button {
  min-height: 2.75rem;
  padding: 0.5rem 0.8rem;
  cursor: pointer;
}
</style>
