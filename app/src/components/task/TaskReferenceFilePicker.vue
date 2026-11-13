<script setup lang="ts">
import { ref } from "vue";

const props = defineProps<{ modelValue: File[] }>();
const emit = defineEmits<{ "update:modelValue": [files: File[]] }>();
const input = ref<HTMLInputElement | null>(null);

function choose() {
  input.value?.click();
}

function add(event: Event) {
  const element = event.target as HTMLInputElement;
  const selected = Array.from(element.files ?? []);
  if (!selected.length) return;

  const known = new Set(
    props.modelValue.map(
      (file) => `${file.name}:${file.size}:${file.lastModified}`,
    ),
  );
  emit("update:modelValue", [
    ...props.modelValue,
    ...selected.filter(
      (file) => !known.has(`${file.name}:${file.size}:${file.lastModified}`),
    ),
  ]);
  element.value = "";
}

function remove(index: number) {
  emit(
    "update:modelValue",
    props.modelValue.filter((_, current) => current !== index),
  );
}
</script>

<template>
  <div class="reference-picker">
    <div class="reference-heading">
      <div>
        <strong>任务资料（可选）</strong>
        <p>模板、要求或原始数据，不会作为成果附件提交。</p>
      </div>
      <button type="button" class="plain-action" @click="choose">
        添加文件
      </button>
      <input
        ref="input"
        class="sr-only"
        type="file"
        multiple
        aria-label="添加任务资料"
        @change="add"
      />
    </div>
    <ul v-if="modelValue.length" class="reference-list">
      <li
        v-for="(file, index) in modelValue"
        :key="`${file.name}-${file.size}-${file.lastModified}`"
      >
        <span>{{ file.name }}</span>
        <button type="button" @click="remove(index)">移除</button>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.reference-picker {
  display: grid;
  gap: 10px;
  padding-top: var(--space-md);
  border-top: 1px solid var(--tu-border);
}
.reference-heading,
.reference-list li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.reference-heading p {
  margin: 4px 0 0;
  color: var(--tu-muted);
  font-size: 13px;
}
.plain-action,
.reference-list button {
  border: 0;
  padding: 4px 0;
  background: transparent;
  color: var(--tu-blue-strong);
  font: inherit;
  font-weight: 650;
  cursor: pointer;
}
.reference-list {
  display: grid;
  gap: 0;
  margin: 0;
  padding: 0;
  list-style: none;
  border-top: 1px solid var(--tu-border);
}
.reference-list li {
  padding: 9px 0;
  border-bottom: 1px solid var(--tu-border);
}
.reference-list span {
  min-width: 0;
  overflow-wrap: anywhere;
}
</style>
