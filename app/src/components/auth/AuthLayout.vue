<script setup lang="ts">
import pigLogo from "@/assets/brand/pig.svg";

defineProps<{
  summary: string;
  note: string;
  cardLabelledby: string;
}>();
</script>

<template>
  <main class="login-page">
    <section class="login-brand" aria-labelledby="product-title">
      <div class="brand-lockup">
        <span class="brand-mark" aria-hidden="true">
          <img :src="pigLogo" alt="" />
        </span>
        <span class="brand-name">小猪作业</span>
      </div>
      <div class="brand-copy">
        <h1 id="product-title">小猪作业，<br />让小组作业更清楚。</h1>
        <p class="product-summary">{{ summary }}</p>
      </div>
      <ul class="product-benefits" aria-label="小猪作业核心能力">
        <li><strong>任务</strong><span>谁负责、等谁、下一步做什么</span></li>
        <li><strong>文件</strong><span>正式成果与版本持续可追溯</span></li>
        <li><strong>验收</strong><span>提交、反馈、修改形成闭环</span></li>
        <li><strong>贡献</strong><span>用实际完成记录支持复盘</span></li>
      </ul>
      <p class="audience-note">{{ note }}</p>
    </section>

    <section class="login-card" :aria-labelledby="cardLabelledby">
      <slot />
    </section>
  </main>
</template>

<style src="../../styles/auth-entry.css"></style>
