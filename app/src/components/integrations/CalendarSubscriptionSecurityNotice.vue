<template>
  <section class="calendar-notice" aria-label="日历订阅安全提示">
    <strong>关于订阅链接的安全</strong>
    <p>
      订阅链接是访问凭据。持有链接的人可以读取未来 90 天内最多 500
      个未完成任务的截止时间，请勿公开分享。
    </p>
    <p>
      默认隐藏任务标题。启用标题后，第三方日历服务可能长期缓存标题。撤销链接会立即阻止新的读取，但不能清除第三方已经缓存的事件。
    </p>
    <p>
      链接只在首次创建时显示，离开页面后无法找回；丢失后请重新签发并撤销旧链接。
    </p>
  </section>
</template>

<style scoped>
.calendar-notice {
  padding: 1rem;
  background: var(--tu-surface);
  border-radius: 12px;
  font-size: 0.9rem;
  line-height: 1.65;
}
.calendar-notice p {
  margin: 0.5rem 0 0;
}
</style>
