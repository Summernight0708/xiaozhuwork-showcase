<script setup lang="ts">
import { computed, nextTick, ref } from "vue";

import {
  memberSwimlaneTasks,
  taskInWindow,
  taskTimelineStyle,
  taskVerticalOffset,
  timelineWindow,
  visibleTaskGroups,
  type MemberFlowMember,
  type MemberFlowTask,
  type MemberTimeRange,
} from "@/domain/member-team-work";

const props = defineProps<{
  members: MemberFlowMember[];
  tasks: MemberFlowTask[];
  range: MemberTimeRange;
  expandedMemberId: string | null;
  remainingExpandedMemberId: string | null;
  title?: string;
}>();

const emit = defineEmits<{
  "update:range": [range: MemberTimeRange];
  "toggle-member": [memberId: string];
  "toggle-remaining": [memberId: string];
  "open-task": [task: MemberFlowTask];
  "update:scroll-position": [position: { left: number; top: number }];
}>();

const scrollRoot = ref<HTMLElement | null>(null);
const windowRange = computed(() => timelineWindow(props.range, props.tasks));
const nowPercent = computed(() => {
  const span = Math.max(windowRange.value.end - windowRange.value.start, 1);
  return ((Date.now() - windowRange.value.start) / span) * 100;
});
const startLabel = computed(() =>
  new Date(windowRange.value.start).toLocaleDateString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
  }),
);
const endLabel = computed(() =>
  new Date(windowRange.value.end).toLocaleDateString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
  }),
);

function tasksFor(member: MemberFlowMember) {
  return memberSwimlaneTasks(member, props.tasks).filter((task) =>
    taskInWindow(task, windowRange.value),
  );
}

function groupsFor(member: MemberFlowMember) {
  return visibleTaskGroups(
    tasksFor(member),
    props.expandedMemberId === member.id,
    props.remainingExpandedMemberId === member.id,
  );
}

function trackHeight(member: MemberFlowMember) {
  if (props.expandedMemberId !== member.id) return 58;
  const groups = groupsFor(member);
  if (!groups.fullyExpanded)
    return groups.remaining.length
      ? 138
      : Math.max(58, groups.recent.length * 44 + 8);
  return Math.max(
    58,
    (groups.recent.length + groups.remaining.length) * 38 + 12,
  );
}

function rowTop(member: MemberFlowMember, task: MemberFlowTask, index: number) {
  const groups = groupsFor(member);
  if (props.expandedMemberId !== member.id)
    return 16 + taskVerticalOffset(index);
  const recentIndex = groups.recent.findIndex(
    (candidate) => candidate.id === task.id,
  );
  if (recentIndex >= 0) return 10 + recentIndex * 44;
  const remainingIndex = groups.remaining.findIndex(
    (candidate) => candidate.id === task.id,
  );
  if (groups.fullyExpanded)
    return 10 + groups.recent.length * 44 + remainingIndex * 38;
  return 98 + taskVerticalOffset(remainingIndex);
}

function styleFor(
  member: MemberFlowMember,
  task: MemberFlowTask,
  index: number,
) {
  return {
    ...taskTimelineStyle(task, windowRange.value),
    top: `${rowTop(member, task, index)}px`,
    "--task-stack-z": `${100 - Math.min(index, 90)}`,
  };
}

function onScroll() {
  if (!scrollRoot.value) return;
  emit("update:scroll-position", {
    left: scrollRoot.value.scrollLeft,
    top: scrollRoot.value.scrollTop,
  });
}

async function restoreScroll(position: { left: number; top: number }) {
  await nextTick();
  if (!scrollRoot.value) return;
  scrollRoot.value.scrollLeft = position.left;
  scrollRoot.value.scrollTop = position.top;
}

defineExpose({ restoreScroll });
</script>

<template>
  <section class="member-task-flow" aria-label="团队任务时间">
    <div class="flow-toolbar">
      <strong>{{ title ?? "团队 MemberTaskFlow" }}</strong>
      <div class="range-switch" role="group" aria-label="时间范围">
        <button
          v-for="option in ['week', 'month', 'all'] as const"
          :key="option"
          type="button"
          :aria-pressed="range === option"
          :class="{ active: range === option }"
          @click="emit('update:range', option)"
        >
          {{
            option === "week" ? "本周" : option === "month" ? "本月" : "全部"
          }}
        </button>
      </div>
    </div>

    <div ref="scrollRoot" class="flow-scroll" @scroll.passive="onScroll">
      <div class="timeline">
        <header class="date-head">
          <span class="sticky-member-head">成员</span>
          <span class="date-start">{{ startLabel }}</span>
          <span class="date-end">{{ endLabel }}</span>
        </header>

        <div
          v-for="member in members"
          :key="member.id"
          class="member-track"
          :class="{ expanded: expandedMemberId === member.id }"
          :style="{ minHeight: `${trackHeight(member)}px` }"
          :data-member-track="member.id"
          @click="emit('toggle-member', member.id)"
        >
          <button
            type="button"
            class="member-name"
            :aria-expanded="expandedMemberId === member.id"
            :aria-label="`${expandedMemberId === member.id ? '收起' : '展开'} ${member.displayName} 的任务泳道`"
            @click.stop="emit('toggle-member', member.id)"
          >
            <strong>{{ member.displayName }}</strong>
            <small
              >主负责 {{ member.primaryCount }} · 协作
              {{ member.collaboratorCount }}</small
            >
          </button>
          <div class="rail" :style="{ minHeight: `${trackHeight(member)}px` }">
            <span
              v-if="nowPercent >= 0 && nowPercent <= 100"
              class="today-line"
              :style="{ left: `${nowPercent}%` }"
              aria-hidden="true"
            />
            <button
              v-for="(task, index) in tasksFor(member)"
              :key="task.id"
              type="button"
              class="task-bar"
              :class="[
                `is-${task.status}`,
                { stacked: expandedMemberId !== member.id || index >= 2 },
              ]"
              :style="styleFor(member, task, index)"
              :title="`${task.title} · ${task.statusLabel}`"
              :data-task-tooltip="`${task.title} · ${task.statusLabel}`"
              :aria-label="`${task.title}，${task.statusLabel}${task.collaboratorCount ? `，${task.collaboratorCount} 名协作者` : ''}`"
              @click.stop="emit('open-task', task)"
            >
              <span>{{ task.title }}</span>
              <small>{{ task.statusLabel }}</small>
              <b v-if="task.collaboratorCount">+{{ task.collaboratorCount }}</b>
            </button>
            <button
              v-if="
                expandedMemberId === member.id &&
                groupsFor(member).remaining.length > 0
              "
              type="button"
              class="remaining-toggle"
              :class="{ 'is-bottom': groupsFor(member).fullyExpanded }"
              :style="{
                top: groupsFor(member).fullyExpanded
                  ? `${trackHeight(member) - 28}px`
                  : '112px',
              }"
              @click.stop="emit('toggle-remaining', member.id)"
            >
              {{
                groupsFor(member).fullyExpanded
                  ? "收起剩余任务"
                  : `展开剩余 ${groupsFor(member).remaining.length} 个任务`
              }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.member-task-flow {
  --flow-lane-shadow-outline: rgb(73 59 39 / 0.12);
  --flow-lane-shadow-blur: rgb(73 59 39 / 0.22);
  min-width: 0;
  display: grid;
  grid-template-rows: auto minmax(320px, 1fr);
  gap: 10px;
}
html[data-theme="dark"] .member-task-flow {
  --flow-lane-shadow-outline: rgb(226 232 240 / 0.12);
  --flow-lane-shadow-blur: rgb(0 0 0 / 0.5);
}
.flow-toolbar,
.range-switch {
  display: flex;
  align-items: center;
}
.flow-toolbar {
  justify-content: space-between;
  gap: 12px;
}
.range-switch {
  gap: 4px;
}
.range-switch button {
  min-height: 32px;
  padding: 0 10px;
  border: 1px solid var(--tu-border);
  background: var(--tu-surface);
  color: var(--tu-muted);
  cursor: pointer;
}
.range-switch button:first-child {
  border-radius: 8px 0 0 8px;
}
.range-switch button:last-child {
  border-radius: 0 8px 8px 0;
}
.range-switch button.active {
  background: var(--tu-blue-soft);
  color: var(--tu-blue-strong);
  font-weight: 700;
}
.flow-scroll {
  overflow: auto;
  max-height: 560px;
  border: 1px solid var(--tu-border);
  border-radius: 12px;
  background: var(--tu-surface);
  overscroll-behavior: contain;
}
.timeline {
  min-width: 860px;
}
.date-head,
.member-track {
  display: grid;
  grid-template-columns: 176px minmax(660px, 1fr);
}
.date-head {
  position: sticky;
  top: 0;
  z-index: 5;
  min-height: 38px;
  border-bottom: 1px solid var(--tu-border);
  background: var(--tu-surface);
  color: var(--tu-muted);
  font-size: 11px;
}
.sticky-member-head,
.member-name {
  position: sticky;
  left: 0;
  z-index: 4;
  background: var(--tu-surface);
  border-right: 1px solid var(--tu-border);
}
.sticky-member-head {
  z-index: 6;
  display: flex;
  align-items: center;
  padding: 0 12px;
}
.date-start,
.date-end {
  position: absolute;
  top: 11px;
}
.date-start {
  left: 192px;
}
.date-end {
  right: 14px;
}
.member-track {
  position: relative;
  z-index: 0;
  border-bottom: 1px solid var(--tu-border);
  cursor: pointer;
  transition: min-height 160ms ease;
}
.member-track:hover,
.member-track:focus-within {
  z-index: 3;
  box-shadow:
    0 0 0 1px var(--flow-lane-shadow-outline),
    0 0 20px var(--flow-lane-shadow-blur);
}
.member-track.expanded {
  z-index: 2;
}
.member-name {
  align-self: stretch;
  min-height: 58px;
  padding: 9px 12px;
  border-top: 0;
  border-bottom: 0;
  border-left: 0;
  color: var(--tu-ink);
  text-align: left;
  cursor: pointer;
}
.member-name:focus-visible {
  outline: 2px solid var(--tu-blue);
  outline-offset: -3px;
}
.member-name strong,
.member-name small {
  display: block;
}
.member-name small {
  margin-top: 4px;
  color: var(--tu-muted);
  font-size: 10px;
}
.rail {
  position: relative;
  margin: 0 14px;
  background-image: linear-gradient(
    90deg,
    transparent 49.8%,
    var(--tu-border) 50%,
    transparent 50.2%
  );
}
.today-line {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: #ef4444;
  opacity: 0.45;
}
.task-bar {
  position: absolute;
  z-index: var(--task-stack-z, 2);
  min-width: 36px;
  height: 28px;
  overflow: visible;
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto auto;
  align-items: center;
  gap: 5px;
  padding: 0 7px;
  border: 1px solid #94a3b8;
  border-radius: 7px;
  background: var(--tu-surface);
  color: var(--tu-ink);
  cursor: pointer;
  text-align: left;
  touch-action: manipulation;
  transition:
    top 160ms ease,
    transform 120ms ease;
}
.task-bar:hover,
.task-bar:focus-visible {
  outline: 2px solid var(--tu-blue);
  outline-offset: 1px;
  transform: translateY(-1px);
}
.task-bar:focus-visible {
  z-index: 120;
}
.task-bar::after {
  content: attr(data-task-tooltip);
  position: absolute;
  left: 0;
  bottom: calc(100% + 6px);
  display: none;
  width: max-content;
  max-width: 260px;
  padding: 6px 8px;
  border-radius: 6px;
  background: var(--tu-ink);
  color: var(--tu-surface);
  box-shadow: var(--tu-shadow);
  font-size: 11px;
  font-weight: 600;
  line-height: 1.35;
  pointer-events: none;
  white-space: nowrap;
}
.task-bar:hover::after,
.task-bar:focus-visible::after {
  display: block;
}
.task-bar span {
  min-width: 0;
  overflow: hidden;
  font-size: 11px;
  font-weight: 700;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.task-bar small,
.task-bar b {
  color: inherit;
  font-size: 9px;
  white-space: nowrap;
}
.task-bar small {
  opacity: 0.78;
}
.task-bar b {
  opacity: 0.86;
}
.task-bar.is-in_progress {
  border-color: #d5ad46;
  background: #f3d88f;
  color: #4d3c13;
}
.task-bar.is-awaiting_review {
  border-color: #b98d67;
  background: #dbc1a7;
  color: #4a3525;
}
.task-bar.is-blocked {
  border-color: #d46b60;
  background: #efaaa2;
  color: #5b211c;
}
.task-bar.is-completed {
  border-color: #8fb795;
  background: #c9ddcb;
  color: #25432a;
}
.task-bar.is-not_started,
.task-bar.is-pending_acceptance {
  border-color: #c8c2b8;
  background: #e8e5df;
  color: #59544c;
}
.task-bar.is-canceled {
  border-color: #bbb4aa;
  border-style: dashed;
  background: #faf8f4;
  color: #746f68;
}
.remaining-toggle {
  position: absolute;
  left: 8px;
  z-index: 30;
  min-height: 32px;
  border: 0;
  background: var(--tu-surface);
  color: var(--tu-blue-strong);
  font-size: 10px;
  cursor: pointer;
}
@media (prefers-reduced-motion: reduce) {
  .member-track,
  .task-bar {
    transition: none;
  }
}
@media (max-width: 767px) {
  .flow-toolbar {
    align-items: flex-start;
    flex-direction: column;
  }
  .flow-scroll {
    max-height: 470px;
  }
}
</style>
