<script setup lang="ts">
defineProps<{
  icon: string
  label: string
}>()

defineEmits<{
  click: []
}>()
</script>

<template>
  <button
    class="w-80 aspect-video flex flex-col items-center justify-center gap-4 border-2 border-primary-500 rounded-2xl bg-transparent text-primary-500 cursor-pointer hover:bg-primary-500/10 active:bg-primary-500/20 hover:scale-105 transition-all duration-200"
    @click="$emit('click')"
  >
    <UIcon :name="icon" class="w-16 h-16 text-primary-500" />
    <span class="text-lg font-semibold tracking-wide">{{ label }}</span>
  </button>
</template>
