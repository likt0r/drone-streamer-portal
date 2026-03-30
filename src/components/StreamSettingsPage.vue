<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { z } from 'zod'

const PORT = 5002

const schema = z.object({
  device: z.string().min(1, 'Device path is required'),
  width: z.number().min(320, 'Width must be at least 320').max(7680, 'Width must be at most 7680'),
  height: z
    .number()
    .min(240, 'Height must be at least 240')
    .max(4320, 'Height must be at most 4320'),
  fps: z.number().min(1, 'FPS must be greater than 0').max(240, 'FPS must be at most 240'),
  bitrateK: z.number().min(100, 'Bitrate must be at least 100'),
  maxrateK: z.number().min(100, 'Maxrate must be at least 100'),
  bufsizeK: z.number().min(100, 'Bufsize must be at least 100'),
  g: z.number().min(1, 'GOP format must be valid'),
  zerolatency: z.boolean(),
  bf: z.number().min(0, 'B-frames must be 0 or more'),
  pix_fmt: z.string().min(1, 'Pixel format is required'),
  f: z.string().min(1, 'Output format is required'),
})

// This maps to the UI fields
const uiSettings = ref({
  device: '/dev/video0',
  width: 1280,
  height: 720,
  fps: 30,
  bitrateK: 8000,
  maxrateK: 10000,
  bufsizeK: 8000,
  g: 15,
  zerolatency: true,
  bf: 0,
  pix_fmt: 'yuv420p',
  f: 'rtsp',
})

const presetOptions = [
  { label: 'Custom Settings', value: 'custom', description: 'User-defined parameters' },
  {
    label: 'Low Quality Profile',
    value: 'low',
    description: 'Optimized for poor network (3Mbps, Low Latency)',
  },
  {
    label: 'Mid Quality Profile',
    value: 'mid',
    description: 'Balanced quality and latency (5Mbps)',
  },
  {
    label: 'High Quality Profile',
    value: 'high',
    description: 'Best quality for strong signal (8Mbps)',
  },
]
const selectedPreset = ref('custom')

watch(selectedPreset, (newVal) => {
  if (newVal === 'low') applyPreset('low')
  else if (newVal === 'mid') applyPreset('mid')
  else if (newVal === 'high') applyPreset('high')
})

const pixFmtOptions = [
  { label: 'yuv420p', value: 'yuv420p', description: 'Widest compatibility, standard color space' },
  { label: 'nv12', value: 'nv12', description: 'Hardware acceleration friendly' },
  { label: 'yuv422p', value: 'yuv422p', description: 'Higher color resolution' },
  { label: 'yuv444p', value: 'yuv444p', description: 'Full color resolution, highest quality' },
  { label: 'rgb24', value: 'rgb24', description: 'Raw RGB, large file size' },
]

const fOptions = [
  { label: 'rtsp', value: 'rtsp', description: 'Real Time Streaming Protocol (Default)' },
  { label: 'rtmp', value: 'rtmp', description: 'Real-Time Messaging Protocol (Twitch/YouTube)' },
  { label: 'mpegts', value: 'mpegts', description: 'MPEG Transport Stream' },
  { label: 'flv', value: 'flv', description: 'Flash Video format' },
  { label: 'matroska', value: 'matroska', description: 'MKV container' },
]

const isSaving = ref(false)
const saveSuccess = ref(false)
const saveError = ref('')

const applyPreset = (presetName: 'low' | 'mid' | 'high') => {
  const presets = {
    low: { bitrateK: 3000, maxrateK: 4000, bufsizeK: 3000 },
    mid: { bitrateK: 5000, maxrateK: 6000, bufsizeK: 5000 },
    high: { bitrateK: 8000, maxrateK: 10000, bufsizeK: 8000 },
  }
  Object.assign(uiSettings.value, {
    device: '/dev/video0',
    width: 1280,
    height: 720,
    fps: 30,
    ...presets[presetName],
    g: 15,
    zerolatency: true,
    bf: 0,
    pix_fmt: 'yuv420p',
    f: 'rtsp',
  })
}

const mapToUI = (data: any) => {
  if (!data) return
  uiSettings.value.device = data.device || '/dev/video0'
  uiSettings.value.width = data.width || 1280
  uiSettings.value.height = data.height || 720
  uiSettings.value.fps = data.fps || 30

  // Extract numbers from "8000k" strings
  uiSettings.value.bitrateK = parseInt((data.bitrate || '8000k').replace('k', ''), 10) || 8000
  uiSettings.value.maxrateK = parseInt((data.maxrate || '10000k').replace('k', ''), 10) || 10000
  uiSettings.value.bufsizeK = parseInt((data.bufsize || '8000k').replace('k', ''), 10) || 8000

  uiSettings.value.g = parseInt(data.g || '15', 10) || 15
  uiSettings.value.zerolatency = data.tune === 'zerolatency'
  uiSettings.value.bf = parseInt(data.bf || '0', 10) || 0
  uiSettings.value.pix_fmt = data.pix_fmt || 'yuv420p'
  uiSettings.value.f = data.f || 'rtsp'
}

const mapToAPI = () => {
  return {
    device: uiSettings.value.device,
    width: uiSettings.value.width,
    height: uiSettings.value.height,
    fps: uiSettings.value.fps,
    bitrate: `${uiSettings.value.bitrateK}k`,
    maxrate: `${uiSettings.value.maxrateK}k`,
    bufsize: `${uiSettings.value.bufsizeK}k`,
    g: uiSettings.value.g.toString(),
    tune: uiSettings.value.zerolatency ? 'zerolatency' : '',
    bf: uiSettings.value.bf.toString(),
    pix_fmt: uiSettings.value.pix_fmt,
    f: uiSettings.value.f,
  }
}

const fetchSettings = async () => {
  try {
    const host = window.location.hostname
    const res = await fetch(`http://${host}:${PORT}/api/stream-settings`)
    const data = await res.json()
    mapToUI(data)
  } catch (err) {
    console.error('Failed to fetch stream settings:', err)
  }
}

const saveSettings = async () => {
  isSaving.value = true
  saveSuccess.value = false
  saveError.value = ''

  try {
    const payload = mapToAPI()
    const host = window.location.hostname
    const response = await fetch(`http://${host}:${PORT}/api/stream-settings`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
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

      <div class="mb-6">
        <UFormField label="Quick Profile" description="Select a predefined quality profile">
          <USelect v-model="selectedPreset" value-key="value" :items="presetOptions" class="w-full">
            <template #item-label="{ item }">
              <div class="flex flex-col py-1">
                <span class="font-medium">{{ item.label }}</span>
                <span class="text-xs text-gray-500">{{ item.description }}</span>
              </div>
            </template>
          </USelect>
        </UFormField>
      </div>

      <UCard :ui="{ background: 'bg-black', ring: 'ring-gray-800' }">
        <UForm :schema="schema" :state="uiSettings" @submit="saveSettings" class="space-y-6">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <UFormField
              label="Video Device"
              name="device"
              description="Path to the V4L2 video capture device (e.g. /dev/video0)"
            >
              <UInput
                v-model="uiSettings.device"
                placeholder="/dev/video0"
                icon="i-heroicons-video-camera"
              />
            </UFormField>

            <UFormField
              label="Target FPS"
              name="fps"
              description="Target capture and stream framerate"
            >
              <UInput v-model.number="uiSettings.fps" type="number" placeholder="30">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">fps</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="Resolution Width"
              name="width"
              description="Video frame width in pixels"
            >
              <UInput v-model.number="uiSettings.width" type="number" placeholder="1280">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">px</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="Resolution Height"
              name="height"
              description="Video frame height in pixels"
            >
              <UInput v-model.number="uiSettings.height" type="number" placeholder="720">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">px</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="Target Bitrate (-b:v)"
              name="bitrateK"
              description="Average encoding bitrate"
            >
              <UInput v-model.number="uiSettings.bitrateK" type="number" placeholder="8000">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">kbps</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="Maximum Bitrate (-maxrate)"
              name="maxrateK"
              description="Maximum allowed spike bitrate"
            >
              <UInput v-model.number="uiSettings.maxrateK" type="number" placeholder="10000">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">kbps</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="Buffer Size (-bufsize)"
              name="bufsizeK"
              description="Size of the rate control buffer"
            >
              <UInput v-model.number="uiSettings.bufsizeK" type="number" placeholder="8000">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">kbps</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="GOP Size (-g)"
              name="g"
              description="Group of Pictures size (keyframe interval)"
            >
              <UInput v-model.number="uiSettings.g" type="number" placeholder="15">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">frames</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="B-Frames (-bf)"
              name="bf"
              description="Bidirectional predictive frames. Higher values improve quality/compression but increase latency. Keep at 0 for real-time FPV."
            >
              <UInput v-model.number="uiSettings.bf" type="number" placeholder="0">
                <template #trailing>
                  <span class="text-gray-500 dark:text-gray-400 text-xs">frames</span>
                </template>
              </UInput>
            </UFormField>

            <UFormField
              label="Pixel Format (-pix_fmt)"
              name="pix_fmt"
              description="Output pixel format for h264 scaling"
            >
              <USelect
                v-model="uiSettings.pix_fmt"
                value-key="value"
                :items="pixFmtOptions"
                class="w-full"
              >
                <template #item-label="{ item }">
                  <div class="flex flex-col py-1">
                    <span class="font-medium">{{ item.label }}</span>
                    <span class="text-xs text-gray-500">{{ item.description }}</span>
                  </div>
                </template>
              </USelect>
            </UFormField>

            <UFormField
              label="Output Format (-f)"
              name="f"
              description="Target packaging format (usually rtsp)"
            >
              <USelect v-model="uiSettings.f" value-key="value" :items="fOptions" class="w-full">
                <template #item-label="{ item }">
                  <div class="flex flex-col py-1">
                    <span class="font-medium">{{ item.label }}</span>
                    <span class="text-xs text-gray-500">{{ item.description }}</span>
                  </div>
                </template>
              </USelect>
            </UFormField>

            <UFormField
              label="Zero Latency Tuning"
              name="zerolatency"
              description="Enable -tune zerolatency flag for real-time FPV"
            >
              <USwitch v-model="uiSettings.zerolatency" color="primary" />
            </UFormField>
          </div>

          <UDivider class="my-6" />

          <p class="text-xs text-gray-500">
            These settings will be applied to the ffmpeg initialization command. Application of
            settings will restart the MediaMTX service.
          </p>

          <div class="pt-2 flex items-center justify-end gap-4">
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
        </UForm>
      </UCard>
    </UContainer>
  </div>
</template>
