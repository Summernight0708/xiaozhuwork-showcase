<script setup lang="ts">
import { computed, ref } from "vue";

import { callOpsApi } from "@ops/lib/ops-api";
import {
  isExactAccountLookup,
  normalizeExactAccountLookup,
} from "@ops/features/account/lookup";
import { useOpsAuthStore } from "@ops/stores/auth";

type Activity = { eventType: string; at: string };
type AccountSupportSummary = {
  schemaVersion: 1;
  userId: string;
  email: string | null;
  createdAt: string;
  lastSignInAt: string | null;
  accountState: string;
  activeProjectCount: number;
  historicalProjectCount: number;
  plan: string;
  entitlementState: string;
  proExpiresAt: string | null;
  recentActivity: Activity[];
};

const auth = useOpsAuthStore();
const query = ref("");
const loading = ref(false);
const error = ref("");
const result = ref<AccountSupportSummary | null>(null);

const valid = computed(() => isExactAccountLookup(query.value));

function cleanString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function cleanCount(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : 0;
}

function sanitizeSummary(value: unknown): AccountSupportSummary | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const data = value as Record<string, unknown>;
  if (
    data.schemaVersion !== 1 ||
    typeof data.userId !== "string" ||
    typeof data.createdAt !== "string" ||
    typeof data.accountState !== "string" ||
    typeof data.plan !== "string" ||
    typeof data.entitlementState !== "string"
  ) {
    return null;
  }

  const activities = Array.isArray(data.recentActivity)
    ? data.recentActivity.slice(0, 20).flatMap((entry): Activity[] => {
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
          return [];
        }
        const item = entry as Record<string, unknown>;
        return typeof item.eventType === "string" && typeof item.at === "string"
          ? [{ eventType: item.eventType, at: item.at }]
          : [];
      })
    : [];

  return {
    schemaVersion: 1,
    userId: data.userId,
    email: cleanString(data.email),
    createdAt: data.createdAt,
    lastSignInAt: cleanString(data.lastSignInAt),
    accountState: data.accountState,
    activeProjectCount: cleanCount(data.activeProjectCount),
    historicalProjectCount: cleanCount(data.historicalProjectCount),
    plan: data.plan,
    entitlementState: data.entitlementState,
    proExpiresAt: cleanString(data.proExpiresAt),
    recentActivity: activities,
  };
}

function displayTime(value: string | null): string {
  if (!value) return "—";
  const time = Date.parse(value);
  if (!Number.isFinite(time)) return "—";
  return new Intl.DateTimeFormat("zh-CN", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(time));
}

async function submitLookup() {
  error.value = "";
  result.value = null;
  const normalized = normalizeExactAccountLookup(query.value);
  if (!isExactAccountLookup(normalized)) {
    error.value = "请输入完整邮箱或完整用户 UUID。";
    return;
  }

  const accessToken = auth.session?.access_token;
  if (!accessToken) {
    error.value = "当前内部会话无效，请重新登录。";
    return;
  }

  loading.value = true;
  try {
    const response = await callOpsApi(
      {
        action: "account.lookup",
        query: normalized,
        requestId: crypto.randomUUID(),
      },
      accessToken,
    );
    if (!response.ok) {
      error.value =
        response.code === "NOT_FOUND"
          ? "未找到该精确账号。"
          : response.code === "VALIDATION_FAILED"
            ? "账号查询格式无效。"
            : "账号摘要暂时不可用。";
      return;
    }

    const sanitized = sanitizeSummary(response.data);
    if (!sanitized) {
      error.value = "账号摘要返回格式异常。";
      return;
    }
    result.value = sanitized;
  } catch {
    error.value = "账号摘要暂时不可用。";
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <section class="support-lookup" aria-labelledby="support-lookup-title">
    <header class="section-heading">
      <div>
        <h2 id="support-lookup-title">精确账号查询</h2>
        <p>仅用于支持与故障定位。每次成功查看都会写入审计。</p>
      </div>
    </header>

    <form class="lookup-form" @submit.prevent="submitLookup">
      <label for="account-query">完整邮箱或用户 UUID</label>
      <div class="lookup-form__row">
        <input
          id="account-query"
          v-model="query"
          name="account-query"
          type="text"
          autocomplete="off"
          spellcheck="false"
          placeholder="name@example.com"
        />
        <button type="submit" :disabled="loading || !valid">
          {{ loading ? "查询中…" : "查询账号" }}
        </button>
      </div>
      <p class="form-hint">不支持模糊邮箱、通配符或批量扫描。</p>
      <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    </form>

    <div v-if="result" class="support-summary">
      <div class="support-summary__identity">
        <strong>{{ result.email || "无邮箱" }}</strong>
        <code>{{ result.userId }}</code>
      </div>
      <dl class="support-summary__facts">
        <div>
          <dt>账号状态</dt>
          <dd>{{ result.accountState }}</dd>
        </div>
        <div>
          <dt>注册时间</dt>
          <dd>{{ displayTime(result.createdAt) }}</dd>
        </div>
        <div>
          <dt>最近登录</dt>
          <dd>{{ displayTime(result.lastSignInAt) }}</dd>
        </div>
        <div>
          <dt>项目</dt>
          <dd>
            活跃 {{ result.activeProjectCount }} / 历史
            {{ result.historicalProjectCount }}
          </dd>
        </div>
        <div>
          <dt>权益</dt>
          <dd>{{ result.plan }} · {{ result.entitlementState }}</dd>
        </div>
        <div>
          <dt>Pro 到期</dt>
          <dd>{{ displayTime(result.proExpiresAt) }}</dd>
        </div>
      </dl>

      <section class="support-activity">
        <h3>最近业务活动</h3>
        <p v-if="result.recentActivity.length === 0" class="empty-note">
          暂无可显示的业务事件。
        </p>
        <ol v-else>
          <li
            v-for="activity in result.recentActivity"
            :key="activity.eventType + activity.at"
          >
            <span>{{ activity.eventType }}</span>
            <time :datetime="activity.at">{{ displayTime(activity.at) }}</time>
          </li>
        </ol>
      </section>
    </div>
  </section>
</template>
