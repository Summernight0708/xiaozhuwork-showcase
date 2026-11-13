<script setup lang="ts">
import {
  PROJECT_PERMISSION_TEMPLATES,
  TEMPLATE_DETAILS,
} from "@/services/project-permissions";
</script>

<template>
  <section class="surface template-list" aria-label="固定权限模板">
    <h2>可委派的权限</h2>
    <p>权限模板只增加指定操作，不会改变成员的基础角色或任务审核权限。</p>
    <ul>
      <li v-for="code in PROJECT_PERMISSION_TEMPLATES" :key="code">
        <strong>{{ TEMPLATE_DETAILS[code].name }}</strong>
        <span>{{ TEMPLATE_DETAILS[code].description }}</span>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.template-list {
  padding: 1rem;
}
.template-list ul {
  list-style: none;
  padding: 0;
  display: grid;
  gap: 0.75rem;
}
.template-list li {
  display: grid;
  gap: 0.25rem;
}
.template-list span,
.template-list p {
  color: var(--tu-muted);
}
</style>
