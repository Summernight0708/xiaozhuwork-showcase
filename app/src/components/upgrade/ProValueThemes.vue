<script setup lang="ts">
const themes = [
  {
    title: "更大空间",
    items: ["更大单文件", "更多项目存储", "更多成员", "更多并发任务"],
  },
  {
    title: "更安心的成果管理",
    items: ["完整历史", "版本比较", "批量回滚", "恢复点"],
  },
  {
    title: "更强的项目管理",
    items: ["增强报告", "项目统计", "跨项目工作台", "高级权限", "日历订阅"],
  },
] as const;
</script>

<template>
  <section class="pro-value-themes" aria-labelledby="pro-value-themes-title">
    <header class="section-heading">
      <div>
        <h2 id="pro-value-themes-title">Pro 能带来什么</h2>
        <p>
          重点提升团队容量、成果安全与项目管理效率；具体 Free / Pro
          差异见下方完整权益表。
        </p>
      </div>
    </header>

    <div class="pro-value-themes__grid">
      <article
        v-for="theme in themes"
        :key="theme.title"
        class="pro-value-theme"
      >
        <h3>{{ theme.title }}</h3>
        <ul>
          <li v-for="item in theme.items" :key="item">{{ item }}</li>
        </ul>
      </article>
    </div>
  </section>
</template>

<style scoped>
.pro-value-themes {
  margin-top: 28px;
}

.section-heading {
  margin-bottom: 14px;
}

.section-heading h2 {
  margin: 0;
  font-size: 22px;
  text-wrap: balance;
}

.section-heading p {
  max-width: 70ch;
  margin: 7px 0 0;
  color: var(--tu-muted);
  line-height: 1.65;
}

.pro-value-themes__grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
  align-items: stretch;
}

.pro-value-theme {
  min-width: 0;
  padding: 20px;
  border: 1px solid var(--tu-border);
  border-radius: var(--tu-radius);
  background: var(--tu-surface);
}

.pro-value-theme h3 {
  margin: 0;
  font-size: 17px;
  line-height: 1.35;
  text-wrap: balance;
}

.pro-value-theme ul {
  display: grid;
  gap: 8px;
  margin: 16px 0 0;
  padding-left: 20px;
}

.pro-value-theme li {
  color: var(--tu-muted);
  line-height: 1.55;
}

@media (max-width: 760px) {
  .pro-value-themes__grid {
    grid-template-columns: 1fr;
  }

  .pro-value-theme {
    padding: 18px;
  }
}
</style>
