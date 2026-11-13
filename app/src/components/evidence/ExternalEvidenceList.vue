<script setup lang="ts">
import { computed } from "vue";
import { showConfirmDialog } from "vant";
import type { ExternalEvidence } from "@/features/external-evidence/types";
import { validateEvidenceUrl } from "@/features/external-evidence/url";

const props = withDefaults(
  defineProps<{
    items: readonly ExternalEvidence[];
    editableIds?: readonly string[];
    busy?: boolean;
    memberNames?: Record<string, string>;
  }>(),
  { editableIds: () => [], busy: false, memberNames: () => ({}) },
);
// Current evidence excludes revoked references; revisions remain readable via history.
const activeItems = computed(() =>
  props.items.filter((item) => !item.revokedAt),
);
const emit = defineEmits<{
  edit: [item: ExternalEvidence];
  remove: [item: ExternalEvidence];
  history: [item: ExternalEvidence];
}>();
async function confirmExternal(url: string) {
  if (!validateEvidenceUrl(url)) return;
  try {
    await showConfirmDialog({
      title: "即将离开小猪作业",
      message:
        "该链接指向第三方网站。XiaozhuWork 不控制其内容、权限或版本，请确认地址可信后再打开。",
      confirmButtonText: "继续前往",
    });
  } catch {
    return;
  }
  window.location.assign(url);
}
</script>

<template>
  <p v-if="activeItems.length === 0">暂无外部链接证据。</p>
  <ul v-else class="evidence-list">
    <li v-for="item in activeItems" :key="item.id">
      <a
        v-if="!item.revokedAt && validateEvidenceUrl(item.httpsUrl)"
        :href="item.httpsUrl"
        target="_blank"
        rel="noopener noreferrer"
        referrerpolicy="no-referrer"
        @click.prevent="confirmExternal(item.httpsUrl)"
        >{{ item.host }} · 在外部打开</a
      >
      <span v-else
        >{{ item.host }} · {{ item.revokedAt ? "已撤销" : "链接不可用" }}</span
      >
      <p>{{ item.description }}</p>
      <small
        >{{
          item.submittedBy
            ? (memberNames[item.submittedBy] ?? "项目成员")
            : "已注销成员"
        }}
        ·
        <time :datetime="item.createdAt">{{
          new Date(item.createdAt).toLocaleString()
        }}</time>
        · 元数据修订 {{ item.version }}</small
      >
      <div class="evidence-actions">
        <button type="button" :disabled="busy" @click="emit('history', item)">
          查看修订记录
        </button>
        <template v-if="!item.revokedAt && editableIds.includes(item.id)">
          <button type="button" :disabled="busy" @click="emit('edit', item)">
            编辑
          </button>
          <button type="button" :disabled="busy" @click="emit('remove', item)">
            撤销链接
          </button>
        </template>
      </div>
    </li>
  </ul>
</template>

<style scoped>
.evidence-list {
  list-style: none;
  padding: 0;
  display: grid;
  gap: 1rem;
}
li {
  border: 1px solid var(--tu-border);
  border-radius: 0.5rem;
  padding: 0.75rem;
  overflow-wrap: anywhere;
}
p {
  white-space: pre-wrap;
}
a {
  color: var(--tu-action);
}
.evidence-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-top: 0.75rem;
}
button {
  min-height: 2.75rem;
  padding: 0.5rem;
  cursor: pointer;
}
</style>
