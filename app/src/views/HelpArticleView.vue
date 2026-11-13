<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from "vue";
import { useRoute } from "vue-router";
import { findHelpArticle } from "@/content/help/articles";
import { findHelpGuide } from "@/content/help/guides";
import { HELP_EXAMPLES } from "@/content/help/examples";
import { resolveHelpDestination } from "@/domain/help-navigation";
import { useProjectsStore } from "@/stores/projects";
import { useWorkspaceStore } from "@/stores/workspace";
import ContextHelpLink from "@/components/help/ContextHelpLink.vue";

const route = useRoute();
const projects = useProjectsStore();
const workspace = useWorkspaceStore();
const guide = computed(() =>
  findHelpGuide(String(route.params.articleId || "")),
);
const article = computed(
  () =>
    findHelpArticle(String(route.params.articleId || "")) ??
    guide.value?.articles[0],
);
const selectedProjectId = ref(
  typeof route.query.projectId === "string" ? route.query.projectId : "",
);
const knownProject = computed(
  () =>
    projects.loaded &&
    projects.activeItems.some(
      (item) => item.project.id === selectedProjectId.value,
    ),
);
const contextReady = computed(
  () =>
    knownProject.value &&
    !workspace.loading &&
    workspace.projectId === selectedProjectId.value &&
    !!workspace.membership &&
    !!workspace.project,
);
const helpContext = computed(() => ({
  projectId: contextReady.value ? selectedProjectId.value : null,
  activeMember: contextReady.value,
  role: workspace.role,
  capabilities: workspace.capabilities,
  pro:
    contextReady.value &&
    (workspace.entitlement?.state === "active" ||
      workspace.entitlement?.state === "grace"),
  archived: !!workspace.project?.archived_at,
  released: true,
}));
const destination = computed(() =>
  article.value
    ? resolveHelpDestination(article.value, helpContext.value)
    : null,
);
const chapterLinks = computed(
  () =>
    guide.value?.articles.map((part) => {
      const target = resolveHelpDestination(part, helpContext.value);
      return target.kind === "navigate" ? target.to : null;
    }) ?? [],
);
const needsProject = computed(() => {
  const globalPages = new Set([
    "projects",
    "project-create",
    "notifications",
    "account-settings",
    "upgrade",
  ]);
  return guide.value
    ? guide.value.articles.some((part) => !globalPages.has(part.routeName))
    : article.value !== undefined && !globalPages.has(article.value.routeName);
});
const example = computed(() =>
  HELP_EXAMPLES.find((item) =>
    guide.value
      ? guide.value.articleIds.includes(item.articleId)
      : item.articleId === article.value?.id,
  ),
);
watch(
  [selectedProjectId, knownProject],
  ([id, allowed]) => {
    if (id && allowed) void workspace.loadBase(id);
  },
  { immediate: true },
);
function scrollToRequestedChapter() {
  const currentId = String(route.params.articleId || "");
  const legacyAnchor =
    guide.value && guide.value.id !== currentId
      ? "guide-part-" + currentId
      : "";
  const sectionId = route.hash.replace(/^#/, "") || legacyAnchor;
  const section = sectionId ? document.getElementById(sectionId) : null;
  if (section && typeof section.scrollIntoView === "function") {
    section.scrollIntoView({ block: "start" });
  }
}
watch(
  () => [route.params.articleId, route.hash],
  async () => {
    await nextTick();
    scrollToRequestedChapter();
  },
  { flush: "post" },
);
onMounted(async () => {
  await projects.load();
  await nextTick();
  scrollToRequestedChapter();
});
</script>

<template>
  <main class="xiaozhuwork-page help-article">
    <RouterLink :to="{ name: 'help-center' }" class="help-back"
      >← 返回使用帮助</RouterLink
    >
    <div v-if="!article" class="surface help-paper">
      <h1>没有找到这篇教程</h1>
      <p>教程可能已经更新。请返回帮助中心搜索相关功能。</p>
    </div>
    <article v-else class="surface help-paper">
      <p class="help-category">
        {{ article.category }}
        <span v-if="article.pro" class="help-pro">Pro</span>
        <span v-if="article.status !== 'released'">· 尚未上线</span>
      </p>
      <h1>{{ guide?.title || article.title }}</h1>
      <p class="help-lead">{{ guide?.summary || article.goal }}</p>
      <template v-if="guide">
        <nav class="guide-outline" aria-label="本篇指南章节">
          <strong>本篇内容</strong>
          <a
            v-for="(part, index) in guide.articles"
            :key="part.id"
            :href="'#guide-part-' + part.id"
          >
            {{ index + 1 }}. {{ part.title }}
          </a>
        </nav>
        <section
          v-for="(part, index) in guide.articles"
          :id="'guide-part-' + part.id"
          :key="part.id"
          class="guide-part"
        >
          <h2 class="guide-part-heading">
            {{ index + 1 }}. {{ part.title }}
            <span v-if="part.pro" class="help-pro">Pro</span>
            <span v-if="part.status !== 'released'" class="help-part-planned"
              >尚未上线</span
            >
            <ContextHelpLink
              v-for="partExample in HELP_EXAMPLES.filter(
                (item) => item.articleId === part.id,
              )"
              :key="partExample.id"
              :example-id="partExample.id"
            />
          </h2>
          <p class="help-lead">{{ part.goal }}</p>
          <ol class="help-steps">
            <li v-for="(step, stepIndex) in part.steps" :key="stepIndex">
              {{ step }}
            </li>
          </ol>
          <p class="guide-tip"><strong>注意：</strong>{{ part.note }}</p>
          <RouterLink
            v-if="chapterLinks[index]"
            :to="chapterLinks[index]!"
            class="help-action chapter-action"
            >前往本节对应页面 →</RouterLink
          >
        </section>
        <section class="guide-faq">
          <h2>常见问题</h2>
          <p v-for="question in guide.questions" :key="question">
            {{ question }}
          </p>
        </section>
      </template>
      <template v-else>
        <h2>如何操作</h2>
        <ol class="help-steps">
          <li v-for="(step, index) in article.steps" :key="index">
            {{ step }}
          </li>
        </ol>
        <div class="help-notice">
          <strong>需要注意</strong>
          <p>{{ article.note }}</p>
        </div>
      </template>
      <section v-if="example && !guide" class="help-example-section">
        <h2>看一个简短示例</h2>
        <p>示例只供阅读，不会修改项目数据。</p>
        <ContextHelpLink :example-id="example.id" />
      </section>
      <section aria-label="下一步" class="help-next">
        <h2>下一步</h2>
        <label v-if="needsProject" class="help-project-picker">
          在项目中练习
          <select v-model="selectedProjectId">
            <option value="">选择项目</option>
            <option
              v-for="item in projects.activeItems"
              :key="item.project.id"
              :value="item.project.id"
            >
              {{ item.project.name }}
            </option>
          </select>
        </label>
        <p v-if="workspace.loading && knownProject" role="status">
          正在验证当前项目权限…
        </p>
        <template v-else-if="destination">
          <RouterLink
            v-if="destination.kind === 'navigate'"
            :to="destination.to"
            class="help-action"
            >{{ destination.label }} →</RouterLink
          >
          <RouterLink
            v-else-if="destination.kind === 'upgrade'"
            :to="{ name: 'upgrade' }"
            class="help-action"
            >了解 Pro 权益 →</RouterLink
          >
          <p v-if="destination.kind !== 'navigate'" class="help-reason">
            {{ destination.reason }}
          </p>
        </template>
        <p class="help-footnote">
          教程不替代真实权限校验；受保护的操作仍以服务器判定为准。
        </p>
      </section>
    </article>
  </main>
</template>

<style scoped>
.guide-part-heading {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.help-part-planned {
  color: var(--tu-muted);
  font-size: 12px;
  font-weight: 500;
}
.chapter-action {
  display: inline-flex;
  margin: 12px 0 0;
}
.guide-outline {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 18px;
  padding: 16px;
  border-top: 1px solid var(--tu-border);
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-subtle-surface);
}
.guide-outline strong {
  flex-basis: 100%;
}
.guide-outline a {
  color: var(--tu-action);
  font-size: 14px;
  text-decoration: underline;
  text-underline-offset: 3px;
}
.guide-part {
  scroll-margin-top: 85px;
  padding: 8px 0 18px;
  border-bottom: 1px solid var(--tu-border);
}
.guide-tip {
  padding: 12px 16px;
  background: var(--tu-subtle-surface);
  color: var(--tu-muted);
  line-height: 1.7;
}
.guide-faq p {
  padding: 10px 0;
  border-bottom: 1px solid var(--tu-border);
  line-height: 1.7;
}
.help-article {
  max-width: 920px;
}
.help-back {
  display: inline-block;
  margin-bottom: 18px;
  color: var(--tu-muted);
  text-decoration: underline;
  text-underline-offset: 3px;
}
.help-paper {
  padding: clamp(20px, 4vw, 42px);
  border-radius: 18px;
}
.help-category {
  color: var(--tu-muted);
  font-size: 13px;
  font-weight: 700;
}
.help-pro {
  margin-left: 8px;
  border: 1px solid var(--tu-border);
  border-radius: 7px;
  padding: 3px 7px;
  font-size: 12px;
}
.help-paper h1 {
  font-size: clamp(27px, 4vw, 37px);
  letter-spacing: -0.03em;
}
.help-lead {
  color: var(--tu-muted);
  line-height: 1.8;
}
.help-paper h2 {
  font-size: 19px;
  margin: 26px 0 14px;
}
.help-steps {
  padding-left: 25px;
  display: grid;
  gap: 13px;
  line-height: 1.8;
}
.help-notice {
  border-left: 1px solid var(--tu-border);
  background: var(--tu-bg);
  border-radius: 8px;
  padding: 16px;
}
.help-notice p,
.help-footnote {
  color: var(--tu-muted);
  line-height: 1.7;
}
.help-next {
  border-top: 1px solid var(--tu-border);
  margin-top: 30px;
  padding-top: 16px;
}
.help-project-picker {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  align-items: center;
  margin: 18px 0;
}
.help-project-picker select {
  background: var(--tu-bg);
  color: var(--tu-ink);
  padding: 10px 12px;
  border: 1px solid var(--tu-border);
  border-radius: 8px;
  max-width: 100%;
}
.help-action {
  display: inline-block;
  margin: 12px 0;
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  padding: 12px 18px;
  border-radius: 9px;
  font-weight: 700;
}
.help-reason {
  color: var(--tu-muted);
}
.help-footnote {
  font-size: 12px;
}
</style>
