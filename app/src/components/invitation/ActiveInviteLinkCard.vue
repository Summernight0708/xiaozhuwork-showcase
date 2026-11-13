<script setup lang="ts">
import { ref } from "vue";

defineProps<{
  url: string;
  expiresAt: string;
  busy?: boolean;
  renewable?: boolean;
}>();

const emit = defineEmits<{
  copy: [];
  renew: [];
  stop: [];
}>();

const confirmingStop = ref(false);
</script>

<template>
  <article class="invite-card surface">
    <div class="invite-main">
      <strong>成员邀请</strong>
      <span>有效至 {{ new Date(expiresAt).toLocaleString("zh-CN") }}</span>
      <code>{{ url }}</code>
    </div>

    <div v-if="!confirmingStop" class="invite-actions">
      <button type="button" aria-label="复制邀请链接" @click="emit('copy')">
        复制链接
      </button>
      <button
        v-if="renewable"
        type="button"
        aria-label="续期邀请链接"
        @click="emit('renew')"
      >
        续期
      </button>
      <button
        type="button"
        class="danger-action"
        aria-label="停止邀请链接"
        @click="confirmingStop = true"
      >
        停止邀请
      </button>
    </div>

    <div
      v-else
      class="stop-confirmation"
      role="alertdialog"
      aria-label="停止邀请确认"
    >
      <div>
        <strong>停止这个邀请链接？</strong>
        <p>停止后，该链接将无法继续加入项目。已经加入的成员不会受影响。</p>
      </div>
      <div class="invite-actions">
        <button type="button" @click="confirmingStop = false">取消</button>
        <button
          type="button"
          class="danger-action"
          :disabled="busy"
          @click="emit('stop')"
        >
          {{ busy ? "停止中…" : "停止邀请" }}
        </button>
      </div>
    </div>
  </article>
</template>

<style scoped>
.invite-card {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 18px;
  align-items: center;
  padding: 18px;
}
.invite-main {
  min-width: 0;
  display: grid;
  gap: 6px;
}
.invite-main span {
  color: var(--tu-muted);
  font-size: 13px;
}
.invite-main code {
  overflow: hidden;
  color: var(--tu-blue-strong);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.invite-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.invite-actions button {
  min-height: 38px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  padding: 0 12px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  cursor: pointer;
}
.invite-actions .danger-action {
  border-color: color-mix(in srgb, var(--tu-danger) 30%, var(--tu-border));
  color: var(--tu-danger);
}
.stop-confirmation {
  grid-column: 1 / -1;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px;
  border-radius: 10px;
  background: color-mix(in srgb, var(--tu-danger) 6%, var(--tu-surface));
}
.stop-confirmation p {
  margin: 5px 0 0;
  color: var(--tu-muted);
  font-size: 13px;
}
@media (max-width: 680px) {
  .invite-card,
  .stop-confirmation {
    grid-template-columns: 1fr;
  }
  .invite-actions {
    width: 100%;
  }
  .invite-actions button {
    flex: 1;
  }
}
</style>
