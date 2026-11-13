<script setup lang="ts">
defineProps<{
  wechatId: string;
}>();
</script>

<template>
  <section
    class="surface manual-upgrade"
    aria-labelledby="manual-upgrade-title"
  >
    <div>
      <h2 id="manual-upgrade-title">Early Access 人工升级</h2>
      <p>
        Early Access
        当前采用人工确认方案与人工开通，不设置固定价格，也不会在网页中直接收费。
      </p>
    </div>

    <ol class="upgrade-steps" aria-label="人工升级流程">
      <li>添加微信</li>
      <li>确认当前方案</li>
      <li>付款</li>
      <li>人工开通</li>
      <li>刷新页面或重新登录后生效</li>
    </ol>

    <div v-if="wechatId" class="wechat-contact">
      <span>微信号</span>
      <code>{{ wechatId }}</code>
      <small>可直接选中复制。</small>
    </div>
    <div v-else class="contact-unavailable" role="status">
      升级联系方式尚未配置，当前请勿根据非页面信息付款。
    </div>
  </section>
</template>

<style scoped>
.manual-upgrade {
  display: grid;
  grid-template-columns: minmax(0, 0.9fr) minmax(300px, 1.1fr);
  gap: 30px;
  margin-top: 28px;
  padding: 24px;
}
.manual-upgrade h2 {
  margin: 0;
  font-size: 22px;
  text-wrap: balance;
}
.manual-upgrade p {
  max-width: 58ch;
  margin: 8px 0 0;
  color: var(--tu-muted);
  line-height: 1.7;
}
.upgrade-steps {
  display: grid;
  gap: 9px;
  margin: 0;
  padding-left: 24px;
}
.upgrade-steps li {
  padding-left: 4px;
  line-height: 1.55;
}
.wechat-contact,
.contact-unavailable {
  grid-column: 1 / -1;
  padding-top: 18px;
  border-top: 1px solid var(--tu-border);
}
.wechat-contact {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 8px 14px;
}
.wechat-contact span,
.wechat-contact small {
  color: var(--tu-muted);
}
.wechat-contact code {
  user-select: text;
  overflow-wrap: anywhere;
  color: var(--tu-ink);
  font-family: inherit;
  font-size: 18px;
  font-weight: 750;
}
.contact-unavailable {
  color: var(--tu-warning);
  line-height: 1.6;
}
@media (max-width: 720px) {
  .manual-upgrade {
    grid-template-columns: 1fr;
    gap: 20px;
    padding: 20px;
  }
}
</style>
