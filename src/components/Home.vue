<script setup lang="ts">
import { useRouter } from 'vue-router'

const router = useRouter()

const startNormal = () => {
  router.push('/normal')
}

const startVr = () => {
  router.push('/vr')
}
</script>

<template>
  <div class="w-full h-screen bg-black flex flex-col items-center justify-center gap-8">
    <h1 class="text-white text-3xl font-bold tracking-tight">Antigravity FPV Portal</h1>

    <div class="flex flex-col sm:flex-row gap-6">
      <UButton
        color="blue"
        variant="solid"
        size="xl"
        icon="i-heroicons-computer-desktop"
        @click="startNormal"
        class="w-72 justify-center"
      >
        Start Streaming (Normal)
      </UButton>

      <UButton
        color="orange"
        variant="solid"
        size="xl"
        icon="i-heroicons-device-phone-mobile"
        @click="startVr"
        class="w-72 justify-center"
      >
        Start VR Mode
      </UButton>
    </div>
  </div>
</template>
