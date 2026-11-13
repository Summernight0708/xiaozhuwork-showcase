<script setup lang="ts">
import { computed, onMounted, shallowRef } from "vue";
import { showToast } from "vant";

import pigIcon from "@/assets/brand/pig.svg";
import { downloadUrl } from "@/platform/downloads";
import {
  fetchAndroidDownloadManifest,
  type AndroidDownloadManifest,
} from "@/services/android-download-manifest";

const state = shallowRef<"loading" | "ready">("loading");
const manifest = shallowRef<AndroidDownloadManifest>({ available: false });
const downloadBusy = shallowRef(false);
const publishedLabel = computed(() => {
  if (!manifest.value.available) return "";
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(manifest.value.publishedAt));
});

const sizeLabel = computed(() => {
  if (!manifest.value.available) return "";
  const bytes = manifest.value.sizeBytes;
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(2)} GiB`;
  return `${(bytes / 1024 ** 2).toFixed(1)} MiB`;
});

onMounted(async () => {
  manifest.value = await fetchAndroidDownloadManifest();
  state.value = "ready";
});

async function downloadApk() {
  if (!manifest.value.available || downloadBusy.value) return;
  downloadBusy.value = true;
  try {
    const result = await downloadUrl({
      url: manifest.value.apkUrl,
      fileName: `xiaozhu-homework-v${manifest.value.versionName}.apk`,
      mimeType: "application/vnd.android.package-archive",
    });
    if (result.native) showToast("APK 已加入系统下载");
  } catch {
    showToast("下载未能开始，请稍后重试");
  } finally {
    downloadBusy.value = false;
  }
}
</script>

<template>
  <div class="download-page">
    <section class="download-card" aria-labelledby="download-title">
      <header class="download-brand">
        <span class="download-mark" aria-hidden="true"
          ><img :src="pigIcon" alt=""
        /></span>
        <div>
          <p class="eyebrow">小猪作业</p>
          <h1 id="download-title">Android 版</h1>
        </div>
      </header>

      <div v-if="state === 'loading'" class="download-state" role="status">
        正在检查最新版本…
      </div>

      <template v-else-if="manifest.available">
        <dl class="release-facts">
          <div>
            <dt>当前版本</dt>
            <dd>v{{ manifest.versionName }}</dd>
          </div>
          <div>
            <dt>文件大小</dt>
            <dd>{{ sizeLabel }}</dd>
          </div>
          <div>
            <dt>更新时间</dt>
            <dd>{{ publishedLabel }}</dd>
          </div>
          <div>
            <dt>系统要求</dt>
            <dd>Android {{ manifest.minAndroid }}+</dd>
          </div>
        </dl>
        <button
          class="download-button"
          type="button"
          :disabled="downloadBusy"
          @click="downloadApk"
        >
          {{ downloadBusy ? "正在开始下载…" : "下载 Android APK" }}
        </button>
      </template>

      <div v-else class="download-state download-state--pending" role="status">
        <strong>Android 版正在准备中</strong>
        <span>正式 APK 发布后，这里会自动显示最新版本与下载入口。</span>
      </div>

      <section class="install-guide" aria-labelledby="install-title">
        <h2 id="install-title">安装说明</h2>
        <ol>
          <li>点击“下载 Android APK”。</li>
          <li>浏览器提示时，仅为本次来源允许“安装未知应用”。</li>
          <li>返回安装页面并确认安装。</li>
          <li>安装完成后打开“小猪作业”。</li>
        </ol>
        <p>
          这是 Android 对非应用商店 APK 的正常安全提示。无需关闭 Play
          Protect，也不建议降低系统整体安全设置。
        </p>
      </section>
    </section>
  </div>
</template>

<style scoped>
.download-page {
  min-height: calc(100dvh - 100px);
  padding: 24px 18px 32px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 14px;
  background: var(--tu-bg);
  color: var(--tu-ink);
}
.download-card {
  width: min(720px, 100%);
  display: grid;
  gap: 24px;
  padding: clamp(24px, 5vw, 44px);
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-panel);
  background: var(--tu-surface);
  box-shadow: var(--tu-shadow);
}
.download-brand {
  display: flex;
  align-items: center;
  gap: 14px;
}
.download-mark {
  width: 48px;
  height: 48px;
  display: grid;
  place-items: center;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-panel);
  background: var(--tu-subtle-surface);
}
.download-mark img {
  width: 28px;
  height: 28px;
}
.eyebrow {
  margin: 0 0 2px;
  color: var(--tu-muted);
  font-size: 14px;
  font-weight: 700;
}
h1 {
  margin: 0;
  font-size: clamp(30px, 6vw, 42px);
  letter-spacing: -0.04em;
}
.release-facts {
  margin: 0;
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1px;
  overflow: hidden;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-panel);
  background: var(--tu-border);
}
.release-facts div {
  padding: 14px 16px;
  background: var(--tu-surface);
}
.release-facts dt {
  margin-bottom: 4px;
  color: var(--tu-muted);
  font-size: 13px;
}
.release-facts dd {
  margin: 0;
  font-weight: 750;
}
.download-button {
  min-height: 48px;
  border: 0;
  border-radius: var(--radius-control);
  background: var(--tu-action);
  color: var(--tu-action-contrast);
  font-weight: 800;
  cursor: pointer;
}
.download-button:disabled {
  opacity: 0.55;
  cursor: wait;
}
.download-state {
  min-height: 120px;
  display: grid;
  place-items: center;
  color: var(--tu-muted);
  text-align: center;
}
.download-state--pending {
  gap: 8px;
  align-content: center;
  padding: 24px;
  border: 1px dashed var(--tu-border);
  border-radius: var(--radius-panel);
  background: var(--tu-subtle-surface);
}
.download-state--pending strong {
  color: var(--tu-ink);
  font-size: 20px;
}
.install-guide {
  display: grid;
  gap: 10px;
}
.install-guide h2 {
  margin: 0;
  font-size: 20px;
}
.install-guide ol {
  margin: 0;
  padding-left: 22px;
  line-height: 1.8;
}
.install-guide p {
  margin: 0;
  color: var(--tu-muted);
  line-height: 1.65;
}
@media (max-width: 520px) {
  .download-page {
    padding-inline: 12px;
  }
  .download-card {
    padding: 22px 18px;
    border-radius: var(--radius-panel);
  }
  .release-facts {
    grid-template-columns: 1fr;
  }
}
html[data-theme="dark"] .download-mark img {
  filter: invert(1);
}
</style>
