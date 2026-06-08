<script setup lang="ts">
const tabs = [
  { label: 'MediaMTX', icon: 'i-heroicons-cog-6-tooth', slot: 'mediamtx' },
  { label: 'Hardware Monitoring', icon: 'i-heroicons-chart-bar', slot: 'monitoring' },
]
</script>

<template>
  <div class="dark bg-black min-h-screen w-full text-white">
    <UContainer class="py-8">
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-white">Settings</h1>
          <p class="text-gray-400">Stream configuration &amp; hardware monitoring</p>
        </div>
        <UButton to="/" icon="i-heroicons-arrow-left" color="primary" variant="ghost">
          Back to Stream
        </UButton>
      </div>

      <UTabs :items="tabs" :unmount-on-hide="false" class="w-full">
        <template #mediamtx>
          <div class="pt-6">
            <MediaMtxSettingsTab />
          </div>
        </template>
        <template #monitoring>
          <div class="pt-6">
            <HardwareMonitorTab />
          </div>
        </template>
      </UTabs>
    </UContainer>
  </div>
</template>
