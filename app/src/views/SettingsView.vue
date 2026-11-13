<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { showToast } from "vant";

import PageState from "@/components/common/PageState.vue";
import {
  displayNameError,
  normalizeDisplayName,
  safeReturnPath,
} from "@/domain/profile-completion";
import {
  getAppearancePreference,
  saveAppearancePreference,
  type AppearancePreference,
} from "@/services/appearance";
import { useAuthStore } from "@/stores/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

const appearance = ref<AppearancePreference>(getAppearancePreference());
const displayName = ref("");
const realName = ref("");
const studentNumber = ref("");
const nextEmail = ref("");
const savingProfile = ref(false);
const changingEmail = ref(false);
// Do not expose an editable profile until its first authenticated read has
// completed, and never overwrite unsaved input with a delayed Auth event.
const profileHydrating = ref(true);
const profileDirty = ref(false);
const completionMode = computed(() => route.query.mode === "complete");
const accountDeletionEnabled =
  import.meta.env.VITE_ACCOUNT_DELETION_ENABLED === "true";
const returnTarget = computed(() => safeReturnPath(route.query.return));

function syncAccountForm() {
  displayName.value = auth.profile?.display_name ?? "";
  realName.value = auth.profile?.real_name ?? "";
  studentNumber.value = auth.profile?.student_number ?? "";
  nextEmail.value = auth.user?.email ?? "";
}

function setAppearance(value: AppearancePreference) {
  appearance.value = value;
  saveAppearancePreference(value);
}

async function saveProfile() {
  const error = displayNameError(displayName.value);
  if (error) {
    showToast(error);
    return;
  }

  savingProfile.value = true;
  try {
    if (completionMode.value) {
      await auth.saveDisplayName(normalizeDisplayName(displayName.value));
      profileDirty.value = false;
      syncAccountForm();
      showToast("昵称已保存");
      await router.replace(returnTarget.value);
      return;
    }

    await auth.saveProfile({
      displayName: displayName.value,
      realName: realName.value,
      studentNumber: studentNumber.value,
    });
    profileDirty.value = false;
    syncAccountForm();
    showToast("账号资料已保存");
  } catch {
    showToast(completionMode.value ? "昵称保存失败" : "账号资料保存失败");
  } finally {
    savingProfile.value = false;
  }
}

async function changeEmail() {
  const normalized = nextEmail.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
    showToast("请输入有效邮箱地址");
    return;
  }
  if (normalized === auth.user?.email) {
    showToast("邮箱没有变化");
    return;
  }

  changingEmail.value = true;
  try {
    const result = await auth.requestEmailChange(normalized);
    showToast(
      result.ok
        ? "确认邮件已发送，请按邮件提示完成邮箱修改"
        : "邮箱修改请求失败",
    );
  } finally {
    changingEmail.value = false;
  }
}

watch(
  () => [auth.profile, auth.user],
  () => {
    if (!profileDirty.value) syncAccountForm();
  },
  { immediate: true },
);
onMounted(async () => {
  try {
    await auth.refreshProfile();
    syncAccountForm();
  } catch {
    showToast("资料读取失败，请重新打开账号设置");
  } finally {
    profileHydrating.value = false;
  }
});
</script>

<template>
  <div class="xiaozhuwork-page settings-page">
    <header class="page-heading">
      <div>
        <h1>{{ completionMode ? "欢迎" : "账号设置" }}</h1>
        <p>
          {{
            completionMode
              ? "先设置显示名称，保存后将返回你原本要前往的位置。"
              : "管理你在小猪作业中的账号资料、本机外观与当前可用的账号能力。"
          }}
        </p>
      </div>
    </header>

    <PageState
      :loading="!auth.initialized || profileHydrating"
      :error="auth.error"
      :empty="!auth.user"
      empty-title="当前没有登录账号"
      @retry="auth.refreshProfile"
    >
      <template v-if="auth.user">
        <section class="setting-section">
          <div class="section-heading">
            <div>
              <h2>账号信息</h2>
              <p>这些资料用于项目协作，不是公开社交主页。</p>
            </div>
            <van-button
              type="primary"
              :loading="savingProfile"
              @click="saveProfile"
              >保存资料</van-button
            >
          </div>

          <div class="account-grid">
            <div class="avatar-preview" aria-hidden="true">
              {{
                (displayName || auth.user.email || "小")
                  .slice(0, 1)
                  .toUpperCase()
              }}
            </div>
            <div class="account-form">
              <van-field
                v-model="displayName"
                name="displayName"
                autocomplete="off"
                label="显示名称"
                maxlength="40"
                placeholder="项目成员看到的名称"
                @update:model-value="profileDirty = true"
              />
              <van-field
                v-if="!completionMode"
                v-model="realName"
                name="realName"
                autocomplete="off"
                label="真实姓名"
                maxlength="80"
                placeholder="仅在项目规则要求时使用"
                @update:model-value="profileDirty = true"
              />
              <van-field
                v-if="!completionMode"
                v-model="studentNumber"
                name="studentNumber"
                autocomplete="off"
                label="学号"
                maxlength="40"
                placeholder="仅在项目规则要求时使用"
                @update:model-value="profileDirty = true"
              />
            </div>
          </div>

          <div v-if="!completionMode" class="privacy-note">
            真实姓名与学号是否必填由各项目规则决定；这些字段不会被当作贡献分、信誉分或能力评价。
          </div>

          <div v-if="!completionMode" class="email-row">
            <van-field
              v-model="nextEmail"
              name="email"
              :spellcheck="false"
              type="email"
              label="登录邮箱"
              autocomplete="email"
            />
            <van-button
              plain
              type="primary"
              :loading="changingEmail"
              @click="changeEmail"
              >申请修改邮箱</van-button
            >
          </div>

          <dl class="account-facts">
            <div>
              <dt>创建时间</dt>
              <dd>
                {{
                  auth.user.created_at
                    ? new Date(auth.user.created_at).toLocaleString()
                    : "—"
                }}
              </dd>
            </div>
            <div>
              <dt>最近登录</dt>
              <dd>
                {{
                  auth.user.last_sign_in_at
                    ? new Date(auth.user.last_sign_in_at).toLocaleString()
                    : "—"
                }}
              </dd>
            </div>
          </dl>
        </section>

        <section
          v-if="accountDeletionEnabled && !completionMode"
          class="setting-section"
        >
          <h2>注销账号</h2>
          <p>注销须先完成项目责任交接。提交申请后有 30 天撤销窗口。</p>
          <van-button
            plain
            type="danger"
            @click="router.push({ name: 'account-deletion' })"
          >
            查看注销与撤销
          </van-button>
        </section>

        <section class="setting-section">
          <h2>外观</h2>
          <p>外观是当前设备本地偏好，不影响项目协作数据。</p>
          <div class="appearance-grid">
            <button
              type="button"
              :class="{ selected: appearance === 'light' }"
              :aria-pressed="appearance === 'light'"
              @click="setAppearance('light')"
            >
              <span class="preview light" aria-hidden="true" />浅色
            </button>
            <button
              type="button"
              :class="{ selected: appearance === 'dark' }"
              :aria-pressed="appearance === 'dark'"
              @click="setAppearance('dark')"
            >
              <span class="preview dark" aria-hidden="true" />深色
            </button>
            <button
              type="button"
              :class="{ selected: appearance === 'system' }"
              :aria-pressed="appearance === 'system'"
              @click="setAppearance('system')"
            >
              <span class="preview system" aria-hidden="true" />跟随系统
            </button>
          </div>
        </section>

        <section class="setting-section">
          <div class="section-heading">
            <div>
              <h2>方案与升级</h2>
              <p>
                账号方案与项目有效权益是两个层级。前往统一升级页查看当前账号方案、Free
                / Pro 权益与 Early Access 人工升级方式。
              </p>
            </div>
            <RouterLink class="settings-link" to="/upgrade">
              查看方案与升级
            </RouterLink>
          </div>
          <div class="capability-note">
            当前不提供在线支付或固定价格；已上线与规划中能力会在升级页分开标注。
          </div>
        </section>
      </template>
    </PageState>
  </div>
</template>

<style scoped>
.settings-page {
  width: 100%;
  max-width: none;
}
.setting-section {
  padding: var(--space-lg) 0;
  margin-bottom: var(--space-sm);
  border-bottom: 1px solid var(--tu-border);
}
.setting-section h2 {
  margin: 0 0 8px;
  font-size: 18px;
}
.setting-section > p,
.section-heading p {
  margin: 0 0 14px;
  color: var(--tu-muted);
  line-height: 1.6;
}
.section-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
  margin-bottom: 14px;
}
.section-heading h2,
.section-heading p {
  margin-top: 0;
}
.account-grid {
  display: grid;
  grid-template-columns: 76px minmax(0, 1fr);
  gap: 18px;
  align-items: start;
}
.avatar-preview {
  width: 68px;
  height: 68px;
  display: grid;
  place-items: center;
  border-radius: var(--radius-control);
  background: var(--tu-blue);
  color: white;
  font-size: 28px;
  font-weight: 800;
}
.account-form {
  min-width: 0;
}
.privacy-note {
  margin-top: 12px;
  padding: 12px 0;
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
  font-size: 13px;
  line-height: 1.6;
}
.email-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 12px;
  align-items: center;
  margin-top: 14px;
}
.account-facts {
  margin: 16px 0 0;
}
.account-facts div {
  display: grid;
  grid-template-columns: 150px minmax(0, 1fr);
  gap: 12px;
  padding: 10px 0;
  border-top: 1px solid var(--tu-border);
}
.account-facts dt {
  color: var(--tu-muted);
}
.account-facts dd {
  margin: 0;
  overflow-wrap: anywhere;
}
.appearance-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}
.appearance-grid button {
  display: grid;
  gap: 8px;
  padding: 10px;
  border: 1px solid var(--tu-border);
  border-radius: var(--radius-control);
  background: var(--tu-surface);
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.appearance-grid button.selected {
  border-color: var(--tu-blue);
  outline: 2px solid var(--tu-action);
  outline-offset: 1px;
}
.preview {
  height: 80px;
  border-radius: 8px;
  border: 1px solid var(--tu-border);
}
.preview.light {
  background: linear-gradient(135deg, #fffdf9 50%, #edf2ed 50%);
}
.preview.dark {
  background: linear-gradient(135deg, #1b211d 50%, #98bdaa 50%);
}
.preview.system {
  background: linear-gradient(135deg, #fffdf9 49%, #656c63 50%, #1b211d 51%);
}
.settings-link {
  min-height: 42px;
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: center;
  padding: 8px 12px;
  border: 1px solid var(--tu-action-border);
  border-radius: var(--radius-control);
  background: var(--tu-action-surface);
  color: var(--tu-action);
  font-size: 14px;
  font-weight: 650;
}
@media (hover: hover) {
  .settings-link:hover {
    background: var(--tu-action-surface-hover);
  }
}
.session-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 14px;
  padding: 14px 0;
  border-top: 1px solid var(--tu-border);
}
.session-row strong,
.session-row small {
  display: block;
}
.session-row small {
  margin-top: 4px;
  color: var(--tu-muted);
}
@media (max-width: 680px) {
  .appearance-grid,
  .email-row {
    grid-template-columns: 1fr;
  }
  .section-heading,
  .session-row {
    align-items: stretch;
    flex-direction: column;
  }
}
@media (max-width: 520px) {
  .account-grid,
  .account-facts div {
    grid-template-columns: 1fr;
  }
}
</style>
