<script setup lang="ts">
import { useRouter } from 'vue-router'
import StreamButton from './StreamButton.vue'

const router = useRouter()
</script>

<template>
  <div class="w-full h-screen bg-black flex flex-col items-center justify-center gap-8 px-6">
    <!--
      Portrait  → flex-col (stacked)
      Landscape → flex-row (side by side)
    -->
    <div class="flex flex-col landscape:flex-row gap-6">
      <StreamButton
        icon="i-heroicons-computer-desktop"
        label="Start Streaming"
        @click="router.push('/normal')"
      />
      <StreamButton icon="i-heroicons-eye" label="Start VR Mode" @click="router.push('/vr')" />
    </div>
  </div>
</template>
