<script setup lang="ts">
import { nextTick, onBeforeUnmount, ref, watch } from "vue";
import type { HelpExample } from "@/content/help/examples";

const props = defineProps<{ example: HelpExample | null }>();
const emit = defineEmits<{ close: []; "open-article": [id: string] }>();
const dialog = ref<HTMLElement | null>(null);
let lastActive: HTMLElement | null = null;
let savedOverflow: string | null = null;

function onKeys(event: KeyboardEvent) {
  if (!props.example) return;
  if (event.key === "Escape") {
    event.preventDefault();
    emit("close");
    return;
  }
  if (event.key !== "Tab" || !dialog.value) return;
  const nodes = Array.from(
    dialog.value.querySelectorAll<HTMLElement>(
      'button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])',
    ),
  ).filter((node) => node.getClientRects().length > 0);
  if (!nodes.length) {
    event.preventDefault();
    dialog.value.focus();
    return;
  }
  const first = nodes[0]!;
  const last = nodes[nodes.length - 1]!;
  if (
    event.shiftKey &&
    (document.activeElement === first ||
      document.activeElement === dialog.value)
  ) {
    event.preventDefault();
    last.focus();
  }
  if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

function restore() {
  document.removeEventListener("keydown", onKeys);
  if (savedOverflow !== null) {
    document.body.style.overflow = savedOverflow;
    savedOverflow = null;
  }
  lastActive?.focus();
  lastActive = null;
}

watch(
  () => props.example,
  async (value, previous) => {
    if (value && !previous) {
      lastActive =
        document.activeElement instanceof HTMLElement
          ? document.activeElement
          : null;
      savedOverflow = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      document.addEventListener("keydown", onKeys);
      await nextTick();
      dialog.value?.focus();
    } else if (!value && previous) {
      restore();
    }
  },
);
onBeforeUnmount(restore);
</script>

<template>
  <Teleport to="body">
    <div
      v-if="example"
      class="help-example-overlay"
      @mousedown.self="emit('close')"
    >
      <section
        ref="dialog"
        tabindex="-1"
        role="dialog"
        aria-modal="true"
        :aria-label="example.title"
        class="help-example-dialog"
      >
        <header class="help-example-head">
          <div>
            <small>只读示例 · 不影响实际项目</small>
            <h2>{{ example.title }}</h2>
          </div>
          <button
            type="button"
            class="help-example-close"
            aria-label="关闭示例"
            @click="emit('close')"
          >
            ×
          </button>
        </header>
        <p class="help-example-scene">{{ example.scenario }}</p>
        <ol>
          <li v-for="(step, i) in example.steps" :key="i">{{ step }}</li>
        </ol>
        <p class="help-example-warning">{{ example.warning }}</p>
        <footer>
          <button
            type="button"
            class="help-example-secondary"
            @click="emit('close')"
          >
            返回操作
          </button>
          <button
            type="button"
            class="help-example-primary"
            @click="emit('open-article', example.articleId)"
          >
            查看完整教程 →
          </button>
        </footer>
      </section>
    </div>
  </Teleport>
</template>

<style scoped>
.help-example-overlay {
  position: fixed;
  inset: 0;
  z-index: 2100;
  background: rgb(4 9 18 / 0.65);
  display: grid;
  place-items: center;
  padding: 16px;
}
.help-example-dialog {
  box-sizing: border-box;
  width: min(100%, 550px);
  max-height: min(80dvh, 720px);
  overflow-y: auto;
  outline: none;
  background: var(--tu-surface);
  color: var(--tu-ink);
  border: 1px solid var(--tu-border);
  box-shadow: 0 24px 80px rgb(0 0 0 / 0.25);
  border-radius: 18px;
  padding: clamp(20px, 4vw, 30px);
}
.help-example-head {
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 20px;
}
.help-example-head small {
  color: var(--tu-muted);
}
.help-example-head h2 {
  margin: 7px 0;
  font-size: 23px;
}
.help-example-close {
  border: 1px solid var(--tu-border);
  border-radius: 9px;
  background: var(--tu-bg);
  color: var(--tu-ink);
  width: 44px;
  height: 44px;
  font-size: 24px;
  cursor: pointer;
}
.help-example-scene {
  background: var(--tu-bg);
  border: 1px solid var(--tu-border);
  border-radius: 12px;
  padding: 18px;
  line-height: 1.7;
}
.help-example-dialog ol {
  display: grid;
  gap: 10px;
  line-height: 1.7;
  padding-left: 23px;
}
.help-example-warning {
  border-left: 1px solid var(--tu-border);
  padding: 8px 12px;
  color: var(--tu-muted);
  line-height: 1.6;
}
.help-example-dialog footer {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 10px;
  border-top: 1px solid var(--tu-border);
  padding-top: 20px;
  margin-top: 20px;
}
.help-example-dialog footer button {
  border-radius: 10px;
  cursor: pointer;
  font-weight: 650;
  min-height: 44px;
  padding: 10px 15px;
}
.help-example-secondary {
  color: var(--tu-ink);
  background: var(--tu-surface);
  border: 1px solid var(--tu-border);
}
.help-example-primary {
  color: var(--tu-action-contrast);
  background: var(--tu-action);
  border: 1px solid var(--tu-action);
}
@media (max-width: 767px) {
  .help-example-overlay {
    align-items: end;
    padding: 0;
  }
  .help-example-dialog {
    width: 100%;
    max-height: calc(92dvh - env(safe-area-inset-top));
    border-radius: 20px 20px 0 0;
    padding: 22px 20px calc(18px + env(safe-area-inset-bottom));
  }
}
@media (prefers-reduced-motion: reduce) {
  .help-example-overlay,
  .help-example-dialog {
    scroll-behavior: auto;
    animation: none;
    transition: none;
  }
}
</style>
