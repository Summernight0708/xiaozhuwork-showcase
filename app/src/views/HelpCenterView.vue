<script setup lang="ts">
import { computed, ref } from "vue";
import { HELP_GUIDES, searchHelpGuides } from "@/content/help/guides";

const query = ref("");
const filtered = computed(() => searchHelpGuides(query.value));
</script>

<template>
  <main class="xiaozhuwork-page help-center">
    <header class="help-heading">
      <div>
        <p class="help-eyebrow">小猪作业 · 使用帮助</p>
        <h1>使用指南</h1>
        <p>从完整流程入手学习协作，具体权限仍以所在项目为准。</p>
      </div>
      <label class="help-search">
        <span class="sr-only">搜索指南及章节</span>
        <input
          v-model.trim="query"
          type="search"
          placeholder="搜索主负责人、回滚、验收、Pro…"
          aria-label="搜索指南及章节"
        />
      </label>
    </header>

    <section aria-label="业务操作指南">
      <p class="guide-count" role="status">
        共 {{ HELP_GUIDES.length }} 篇完整指南<span v-if="query">
          · 匹配 {{ filtered.length }} 篇</span
        >
      </p>
      <div class="guide-list">
        <RouterLink
          v-for="(guide, index) in filtered"
          :key="guide.id"
          class="guide-row"
          :to="{ name: 'help-article', params: { articleId: guide.id } }"
        >
          <span class="guide-index">{{
            String(index + 1).padStart(2, "0")
          }}</span>
          <span class="guide-details">
            <strong>{{ guide.title }}</strong>
            <span>{{ guide.summary }}</span>
            <small>{{
              guide.articles.map((item) => item.title).join(" · ")
            }}</small>
          </span>
          <span class="guide-arrow" aria-hidden="true">↗</span>
        </RouterLink>
      </div>
      <p v-if="!filtered.length" role="status">
        没有找到匹配指南，请尝试更换搜索词。
      </p>
    </section>
  </main>
</template>

<style scoped>
.help-center {
  width: 100%;
  max-width: none;
}
.help-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 20px;
  margin-bottom: 28px;
  padding-bottom: 20px;
  border-bottom: 1px solid var(--tu-border);
}
.help-heading h1 {
  margin: 4px 0 10px;
  font-size: clamp(27px, 3vw, 33px);
}
.help-heading p {
  margin: 0;
  line-height: 1.55;
  color: var(--tu-muted);
}
.help-heading .help-eyebrow {
  font-size: 12px;
  font-weight: 650;
}
.help-search {
  flex: 0 1 390px;
  width: 100%;
}
.help-search input {
  width: 100%;
  min-height: 46px;
  padding: 10px 14px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  background: var(--tu-surface);
  color: var(--tu-ink);
}
.guide-count {
  margin: 0 0 12px;
  color: var(--tu-muted);
  font-size: 13px;
}
.guide-list {
  border-top: 1px solid var(--tu-border);
}
.guide-row {
  display: grid;
  grid-template-columns: 42px minmax(0, 1fr) 24px;
  align-items: start;
  gap: 14px;
  padding: 22px 6px;
  border-bottom: 1px solid var(--tu-border);
  color: var(--tu-ink);
}
.guide-row:hover,
.guide-row:focus-visible {
  background: var(--tu-subtle-surface);
}
.guide-index {
  font-size: 14px;
  color: var(--tu-muted);
  font-variant-numeric: tabular-nums;
}
.guide-details {
  display: grid;
  gap: 7px;
  min-width: 0;
}
.guide-details strong {
  font-size: 18px;
}
.guide-details span {
  font-size: 14px;
  color: var(--tu-muted);
}
.guide-details small {
  line-height: 1.6;
  color: var(--tu-muted);
  font-size: 12px;
  overflow-wrap: anywhere;
}
.guide-arrow {
  color: var(--tu-muted);
  font-size: 19px;
}
@media (max-width: 767px) {
  .help-heading {
    align-items: stretch;
  }
  .help-search {
    flex-basis: 100%;
  }
  .guide-row {
    grid-template-columns: 30px minmax(0, 1fr) 20px;
    padding: 17px 2px;
  }
  .guide-details strong {
    font-size: 16px;
  }
}
</style>
