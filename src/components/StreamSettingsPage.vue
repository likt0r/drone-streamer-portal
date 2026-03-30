<script setup lang="ts">
import { ref, onMounted } from 'vue'

const PORT = 5002

const settings = ref({
  device: '/dev/video0',
  width: 1280,
  height: 720,
  fps: 30,
  bitrate: '8000k',
  maxrate: '10000k',
  bufsize: '8000k',
  g: '15',
  tune: 'zerolatency',
  bf: '0',
  pix_fmt: 'yuv420p',
  f: 'rtsp',
})

const isSaving = ref(false)
const saveSuccess = ref(false)
const saveError = ref('')

const presets = {
  low: {
    device: '/dev/video0',
    width: 1280,
    height: 720,
    fps: 30,
    bitrate: '3000k',
    maxrate: '4000k',
    bufsize: '3000k',
    g: '15',
    tune: 'zerolatency',
    bf: '0',
    pix_fmt: 'yuv420p',
    f: 'rtsp',
  },
  mid: {
    device: '/dev/video0',
    width: 1280,
    height: 720,
    fps: 30,
    bitrate: '5000k',
    maxrate: '6000k',
    bufsize: '5000k',
    g: '15',
    tune: 'zerolatency',
    bf: '0',
    pix_fmt: 'yuv420p',
    f: 'rtsp',
  },
  high: {
    device: '/dev/video0',
    width: 1280,
    height: 720,
    fps: 30,
    bitrate: '8000k',
    maxrate: '10000k',
    bufsize: '8000k',
    g: '15',
    tune: 'zerolatency',
    bf: '0',
    pix_fmt: 'yuv420p',
    f: 'rtsp',
  },
}

const applyPreset = (presetName: keyof typeof presets) => {
  settings.value = { ...presets[presetName] }
}

const fetchSettings = async () => {
  try {
    const host = window.location.hostname
    const res = await fetch(`http://${host}:${PORT}/api/stream-settings`)
    const data = await res.json()
    if (data) Object.assign(settings.value, data)
  } catch (err) {
    console.error('Failed to fetch stream settings:', err)
  }
}

const saveSettings = async () => {
  isSaving.value = true
  saveSuccess.value = false
  saveError.value = ''

  try {
    const host = window.location.hostname
    const response = await fetch(`http://${host}:${PORT}/api/stream-settings`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(settings.value),
    })

    const result = await response.json()
    if (result.status === 'success') {
      saveSuccess.value = true
      setTimeout(() => (saveSuccess.value = false), 3000)
    } else {
      saveError.value = result.message || 'Error saving settings'
    }
  } catch (err) {
    console.error('Failed to save settings:', err)
    saveError.value = 'Network error saving settings'
  } finally {
    isSaving.value = false
  }
}

onMounted(() => {
  fetchSettings()
})
</script>

<template>
  <div class="dark bg-black min-h-screen w-full text-white">
    <UContainer class="py-8">
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-white">Stream Settings</h1>
          <p class="text-gray-400">Configure video stream parameters</p>
        </div>
        <UButton to="/info" icon="i-heroicons-arrow-left" color="primary" variant="ghost">
          Back to Info
        </UButton>
      </div>

      <div class="mb-6 grid grid-cols-3 gap-4">
        <UButton color="gray" variant="solid" @click="applyPreset('low')" block>
          Low Quality Profile
        </UButton>
        <UButton color="blue" variant="solid" @click="applyPreset('mid')" block>
          Mid Quality Profile
        </UButton>
        <UButton color="primary" variant="solid" @click="applyPreset('high')" block>
          High Quality Profile
        </UButton>
      </div>

      <UCard :ui="{ background: 'bg-black', ring: 'ring-gray-800' }">
        <form @submit.prevent="saveSettings" class="space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <UFormGroup label="Video Device" name="device">
              <UInput v-model="settings.device" placeholder="/dev/video0" />
            </UFormGroup>

            <UFormGroup label="FPS" name="fps">
              <UInput v-model.number="settings.fps" type="number" placeholder="30" />
            </UFormGroup>

            <UFormGroup label="Width" name="width">
              <UInput v-model.number="settings.width" type="number" placeholder="1280" />
            </UFormGroup>

            <UFormGroup label="Height" name="height">
              <UInput v-model.number="settings.height" type="number" placeholder="720" />
            </UFormGroup>

            <UFormGroup label="Bitrate (-b:v)" name="bitrate">
              <UInput v-model="settings.bitrate" placeholder="8000k" />
            </UFormGroup>

            <UFormGroup label="Maxrate (-maxrate)" name="maxrate">
              <UInput v-model="settings.maxrate" placeholder="10000k" />
            </UFormGroup>

            <UFormGroup label="Bufsize (-bufsize)" name="bufsize">
              <UInput v-model="settings.bufsize" placeholder="8000k" />
            </UFormGroup>

            <UFormGroup label="GOP Size (-g)" name="g">
              <UInput v-model="settings.g" placeholder="15" />
            </UFormGroup>

            <UFormGroup label="Tune Options (-tune)" name="tune">
              <UInput v-model="settings.tune" placeholder="zerolatency" />
            </UFormGroup>

            <UFormGroup label="B-Frames (-bf)" name="bf">
              <UInput v-model="settings.bf" placeholder="0" />
            </UFormGroup>

            <UFormGroup label="Pixel Format (-pix_fmt)" name="pix_fmt">
              <UInput v-model="settings.pix_fmt" placeholder="yuv420p" />
            </UFormGroup>

            <UFormGroup label="Output Format (-f)" name="f">
              <UInput v-model="settings.f" placeholder="rtsp" />
            </UFormGroup>
          </div>

          <p class="text-xs text-gray-500 mt-2">
            These settings will be applied to the ffmpeg initialization command. Application of
            settings will restart the MediaMTX service.
          </p>

          <div class="pt-4 flex items-center justify-end gap-4">
            <span v-if="saveError" class="text-red-500 text-sm">{{ saveError }}</span>
            <span v-if="saveSuccess" class="text-green-500 text-sm flex items-center gap-1">
              <UIcon name="i-heroicons-check-circle" /> Saved successfully
            </span>
            <UButton
              type="submit"
              color="primary"
              :loading="isSaving"
              icon="i-heroicons-document-check"
            >
              Save & Restart Stream
            </UButton>
          </div>
        </form>
      </UCard>
    </UContainer>
  </div>
</template>
