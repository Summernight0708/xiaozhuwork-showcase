<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { findHelpExample } from "@/content/help/examples";
import { isNativeAndroid } from "@/platform/downloads";
import HelpExampleDialog from "@/components/help/HelpExampleDialog.vue";

const props = defineProps<{ exampleId: string }>();
const route = useRoute();
const router = useRouter();
const visible = ref(false);
const example = computed(() => findHelpExample(props.exampleId));

async function showArticle(id: string) {
  visible.value = false;
  const projectId =
    typeof route.params.projectId === "string"
      ? route.params.projectId
      : undefined;
  const target = {
    name: "help-article",
    params: { articleId: id },
    query: projectId ? { projectId } : {},
  };
  if (!isNativeAndroid() && typeof window !== "undefined") {
    const link = document.createElement("a");
    link.href = router.resolve(target).href;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.click();
    return;
  }
  if (
    typeof window !== "undefined" &&
    !window.confirm(
      "离开当前页面可能会丢失尚未保存的编辑内容。继续查看教程吗？",
    )
  )
    return;
  await router.push(target);
}
</script>

<template>
  <span v-if="example" class="context-help">
    <button
      type="button"
      class="context-help-button"
      aria-label="查看示例"
      @click="visible = true"
    >
      <span class="context-help-arrow" aria-hidden="true">↗</span>
    </button>
    <HelpExampleDialog
      :example="visible ? example : null"
      @close="visible = false"
      @open-article="showArticle"
    />
  </span>
</template>

<style scoped>
.context-help {
  position: relative;
  display: inline-flex;
  align-items: center;
}
/* Only a transient tooltip: the arrow itself has no persistent frame. */
@media (hover: hover) {
  .context-help::after {
    content: "查看示例";
    position: absolute;
    right: -8px;
    bottom: calc(100% + 4px);
    white-space: nowrap;
    color: var(--tu-ink);
    background: var(--tu-surface);
    border: 1px solid var(--tu-border);
    border-radius: 6px;
    padding: 5px 9px;
    box-shadow: var(--tu-shadow);
    font-size: 12px;
    pointer-events: none;
    opacity: 0;
    visibility: hidden;
    transition: opacity 120ms ease;
  }
  .context-help:hover::after,
  .context-help:focus-within::after {
    opacity: 1;
    visibility: visible;
  }
} /* No visible frame; the accessible hit target remains 40 x 40. */
.context-help-button {
  display: inline-grid;
  place-items: center;
  min-width: 40px;
  min-height: 40px;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--tu-muted);
  cursor: pointer;
}
.context-help-arrow {
  font-size: 23px;
  line-height: 1;
  transition:
    color 120ms ease,
    transform 120ms ease;
}
.context-help-button:hover,
.context-help-button:focus-visible {
  color: var(--tu-action);
}
.context-help-button:hover .context-help-arrow {
  transform: translate(1px, -1px);
}
</style>
