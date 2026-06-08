<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue'
import { z } from 'zod'

const PORT = 5002
const host = window.location.hostname

// ─── Device capabilities (resolutions/framerates the capture device offers) ──
interface Resolution {
  width: number
  height: number
  framerates: number[]
}
interface VideoFormat {
  pixelformat: string
  resolutions: Resolution[]
}
interface CaptureDevice {
  path: string
  name: string
}

const resolutions = ref<Resolution[]>([])
const captureDevices = ref<CaptureDevice[]>([])

// ─── UI state ────────────────────────────────────────────────────────────────
const uiSettings = ref({
  device: '/dev/video0',
  width: 1280,
  height: 720,
  fps: 30,
  bitrateK: 8000,
  maxrateK: 10000,
  bufsizeK: 8000,
  g: 15,
  zerolatency: false,
  bf: 0,
  pix_fmt: 'yuv420p',
  f: 'rtsp',
  rtsp_transport: 'tcp',
})

// Defaults shown as hints next to each field.
const DEFAULTS = {
  fps: 30,
  resolution: '1280×720',
  bitrateK: 8000,
  maxrateK: 10000,
  bufsizeK: 8000,
  g: 15,
  bf: 0,
  pix_fmt: 'yuv420p',
  f: 'rtsp',
  rtsp_transport: 'tcp',
}

const schema = z.object({
  device: z.string().min(1, 'Device path is required'),
  width: z.number().min(160),
  height: z.number().min(120),
  fps: z.number().min(1).max(240),
  bitrateK: z.number().min(100, 'Bitrate must be at least 100'),
  maxrateK: z.number().min(100, 'Maxrate must be at least 100'),
  bufsizeK: z.number().min(100, 'Bufsize must be at least 100'),
  g: z.number().min(1, 'GOP size must be at least 1'),
  zerolatency: z.boolean(),
  bf: z.number().min(0, 'B-frames must be 0 or more'),
  pix_fmt: z.string().min(1),
  f: z.string().min(1),
  rtsp_transport: z.enum(['tcp', 'udp']),
})

// ─── Video device select (attached capture devices) ─────────────────────────
const deviceItems = computed(() => {
  const items = captureDevices.value.map((d) => ({ label: `${d.name} (${d.path})`, value: d.path }))
  // Fallback so the currently-configured device is always selectable.
  if (!items.some((i) => i.value === uiSettings.value.device)) {
    items.unshift({ label: uiSettings.value.device, value: uiSettings.value.device })
  }
  return items
})

// ─── Resolution / FPS selects derived from the device capabilities ───────────
const resolutionItems = computed(() => {
  const items = resolutions.value.map((r) => ({
    label: `${r.width}×${r.height}`,
    value: `${r.width}x${r.height}`,
  }))
  // Fallback so the current value is always selectable even if caps failed to load.
  const current = `${uiSettings.value.width}x${uiSettings.value.height}`
  if (!items.some((i) => i.value === current)) {
    items.unshift({ label: `${uiSettings.value.width}×${uiSettings.value.height}`, value: current })
  }
  return items
})

const selectedResolution = computed({
  get: () => `${uiSettings.value.width}x${uiSettings.value.height}`,
  set: (v: string) => {
    const [w, h] = v.split('x')
    uiSettings.value.width = Number(w)
    uiSettings.value.height = Number(h)
    clampFps()
  },
})

const availableFps = computed(() => {
  const r = resolutions.value.find(
    (r) => r.width === uiSettings.value.width && r.height === uiSettings.value.height,
  )
  return r ? r.framerates : []
})

const fpsItems = computed(() => {
  const list = availableFps.value.length ? availableFps.value : [uiSettings.value.fps]
  return list.map((f) => ({ label: `${f} fps`, value: f }))
})

const clampFps = () => {
  if (availableFps.value.length && !availableFps.value.includes(uiSettings.value.fps)) {
    uiSettings.value.fps = availableFps.value.includes(30) ? 30 : (availableFps.value[0] ?? 30)
  }
}

// ─── Presets (only adjust the bitrate group; resolution/fps stay user-chosen) ─
const presetOptions = [
  { label: 'Custom Settings', value: 'custom', description: 'User-defined parameters' },
  { label: 'Low (3 Mbps)', value: 'low', description: 'Poor network, lowest latency' },
  { label: 'Mid (5 Mbps)', value: 'mid', description: 'Balanced quality and latency' },
  { label: 'High (8 Mbps)', value: 'high', description: 'Best quality, strong signal' },
]
const selectedPreset = ref('custom')

const applyPreset = (name: 'low' | 'mid' | 'high') => {
  const presets = {
    low: { bitrateK: 3000, maxrateK: 4000, bufsizeK: 3000 },
    mid: { bitrateK: 5000, maxrateK: 6000, bufsizeK: 5000 },
    high: { bitrateK: 8000, maxrateK: 10000, bufsizeK: 8000 },
  }
  Object.assign(uiSettings.value, presets[name])
}

watch(selectedPreset, (v) => {
  if (v === 'low' || v === 'mid' || v === 'high') applyPreset(v)
})

const pixFmtOptions = [
  { label: 'yuv420p', value: 'yuv420p', description: 'Widest compatibility (recommended)' },
  { label: 'nv12', value: 'nv12', description: 'Hardware-acceleration friendly' },
  { label: 'yuv422p', value: 'yuv422p', description: 'Higher chroma resolution' },
  { label: 'yuv444p', value: 'yuv444p', description: 'Full chroma, highest quality' },
]

const fOptions = [
  { label: 'rtsp', value: 'rtsp', description: 'Real Time Streaming Protocol (default)' },
  { label: 'rtmp', value: 'rtmp', description: 'Real-Time Messaging Protocol' },
  { label: 'mpegts', value: 'mpegts', description: 'MPEG Transport Stream' },
]

const transportOptions = [
  { label: 'TCP', value: 'tcp', description: 'Reliable, no packet loss (recommended)' },
  { label: 'UDP', value: 'udp', description: 'Lower overhead, may drop packets' },
]

const isSaving = ref(false)
const saveSuccess = ref(false)
const saveError = ref('')

// ─── Backend mapping ─────────────────────────────────────────────────────────
const mapToUI = (data: any) => {
  if (!data) return
  uiSettings.value.device = data.device || '/dev/video0'
  uiSettings.value.width = data.width || 1280
  uiSettings.value.height = data.height || 720
  uiSettings.value.fps = data.fps || 30
  uiSettings.value.bitrateK = parseInt((data.bitrate || '8000k').replace('k', ''), 10) || 8000
  uiSettings.value.maxrateK = parseInt((data.maxrate || '10000k').replace('k', ''), 10) || 10000
  uiSettings.value.bufsizeK = parseInt((data.bufsize || '8000k').replace('k', ''), 10) || 8000
  uiSettings.value.g = parseInt(data.g || '15', 10) || 15
  uiSettings.value.zerolatency = data.tune === 'zerolatency'
  uiSettings.value.bf = parseInt(data.bf || '0', 10) || 0
  uiSettings.value.pix_fmt = data.pix_fmt || 'yuv420p'
  uiSettings.value.f = data.f || 'rtsp'
  uiSettings.value.rtsp_transport = data.rtsp_transport === 'udp' ? 'udp' : 'tcp'
}

const mapToAPI = () => ({
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
  rtsp_transport: uiSettings.value.rtsp_transport,
})

const fetchDevices = async () => {
  try {
    const res = await fetch(
      `http://${host}:${PORT}/api/video-devices?device=${encodeURIComponent(uiSettings.value.device)}`,
    )
    const data = await res.json()
    const formats: VideoFormat[] = data.formats || []
    const mjpg = formats.find((f) => f.pixelformat === 'MJPG') || formats[0]
    resolutions.value = mjpg ? mjpg.resolutions : []
  } catch (err) {
    console.error('Failed to fetch device capabilities:', err)
    resolutions.value = []
  }
}

const fetchCaptureDevices = async () => {
  try {
    const res = await fetch(`http://${host}:${PORT}/api/capture-devices`)
    const data = await res.json()
    captureDevices.value = data.devices || []
  } catch (err) {
    console.error('Failed to fetch capture devices:', err)
    captureDevices.value = []
  }
}

const fetchSettings = async () => {
  try {
    const res = await fetch(`http://${host}:${PORT}/api/stream-settings`)
    mapToUI(await res.json())
  } catch (err) {
    console.error('Failed to fetch stream settings:', err)
  }
}

const saveSettings = async () => {
  isSaving.value = true
  saveSuccess.value = false
  saveError.value = ''
  try {
    const response = await fetch(`http://${host}:${PORT}/api/stream-settings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(mapToAPI()),
    })
    const result = await response.json()
    if (result.status === 'success') {
      saveSuccess.value = true
      setTimeout(() => (saveSuccess.value = false), 4000)
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

// Re-query capabilities whenever the device path changes.
watch(
  () => uiSettings.value.device,
  () => fetchDevices(),
)

onMounted(async () => {
  await Promise.all([fetchSettings(), fetchDevices(), fetchCaptureDevices()])
})
</script>

<template>
  <div>
    <div class="mb-6">
      <UFormField label="Quick Profile" description="Apply a predefined bitrate profile">
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
          <!-- Device (attached capture devices) -->
          <UFormField
            label="Video Device"
            name="device"
            description="Attached V4L2 capture device. Resolutions/framerates below are read from it."
          >
            <USelect
              v-model="uiSettings.device"
              value-key="value"
              :items="deviceItems"
              icon="i-heroicons-video-camera"
              class="w-full"
            />
          </UFormField>

          <!-- Resolution (device-constrained) -->
          <UFormField
            label="Resolution"
            name="width"
            :description="`Only resolutions the device supports. Higher = sharper but more bandwidth & encode load. Default: ${DEFAULTS.resolution}.`"
          >
            <USelect
              v-model="selectedResolution"
              value-key="value"
              :items="resolutionItems"
              class="w-full"
              icon="i-heroicons-rectangle-group"
            />
          </UFormField>

          <!-- FPS (depends on chosen resolution) -->
          <UFormField
            label="Framerate"
            name="fps"
            :description="`Frames per second supported at the chosen resolution. Higher = smoother but more bandwidth. Default: ${DEFAULTS.fps} fps.`"
          >
            <USelect
              v-model="uiSettings.fps"
              value-key="value"
              :items="fpsItems"
              class="w-full"
              icon="i-heroicons-clock"
            />
          </UFormField>

          <!-- Bitrate -->
          <UFormField
            label="Target Bitrate (-b:v)"
            name="bitrateK"
            :description="`Average encoding bitrate. Higher = better quality, more bandwidth. Default: ${DEFAULTS.bitrateK} kbps.`"
          >
            <UInput v-model.number="uiSettings.bitrateK" type="number" placeholder="8000">
              <template #trailing><span class="text-gray-400 text-xs">kbps</span></template>
            </UInput>
          </UFormField>

          <!-- Maxrate -->
          <UFormField
            label="Maximum Bitrate (-maxrate)"
            name="maxrateK"
            :description="`Peak bitrate cap for spikes. Keep above target bitrate. Default: ${DEFAULTS.maxrateK} kbps.`"
          >
            <UInput v-model.number="uiSettings.maxrateK" type="number" placeholder="10000">
              <template #trailing><span class="text-gray-400 text-xs">kbps</span></template>
            </UInput>
          </UFormField>

          <!-- Bufsize -->
          <UFormField
            label="Buffer Size (-bufsize)"
            name="bufsizeK"
            :description="`Rate-control buffer. Smaller = more constant bitrate & lower latency. Default: ${DEFAULTS.bufsizeK} kbps.`"
          >
            <UInput v-model.number="uiSettings.bufsizeK" type="number" placeholder="8000">
              <template #trailing><span class="text-gray-400 text-xs">kbps</span></template>
            </UInput>
          </UFormField>

          <!-- GOP -->
          <UFormField
            label="GOP Size (-g)"
            name="g"
            :description="`Keyframe interval in frames (15 @30fps ≈ 0.5 s). Smaller = faster recovery on loss, more bandwidth. Default: ${DEFAULTS.g}.`"
          >
            <UInput v-model.number="uiSettings.g" type="number" placeholder="15">
              <template #trailing><span class="text-gray-400 text-xs">frames</span></template>
            </UInput>
          </UFormField>

          <!-- B-frames -->
          <UFormField
            label="B-Frames (-bf)"
            name="bf"
            :description="`Bidirectional frames. >0 improves compression but ADDS LATENCY — keep 0 for real-time FPV. Default: ${DEFAULTS.bf}.`"
          >
            <UInput v-model.number="uiSettings.bf" type="number" placeholder="0">
              <template #trailing><span class="text-gray-400 text-xs">frames</span></template>
            </UInput>
          </UFormField>

          <!-- Pixel format -->
          <UFormField
            label="Pixel Format (-pix_fmt)"
            name="pix_fmt"
            :description="`Encoder pixel format. Default: ${DEFAULTS.pix_fmt} (widest compatibility).`"
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

          <!-- Output format -->
          <UFormField
            label="Output Format (-f)"
            name="f"
            :description="`Packaging format published to MediaMTX. Default: ${DEFAULTS.f}.`"
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

          <!-- RTSP transport (ffmpeg → MediaMTX publish link) -->
          <UFormField
            label="RTSP Transport (ffmpeg → MediaMTX)"
            name="rtsp_transport"
            :description="`Internal capture→server link only — does NOT affect the browser (playback is WebRTC/UDP). TCP = reliable (recommended), UDP = less overhead but may drop packets locally. Default: ${DEFAULTS.rtsp_transport}.`"
          >
            <USelect
              v-model="uiSettings.rtsp_transport"
              value-key="value"
              :items="transportOptions"
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

          <!-- Zero latency -->
          <UFormField
            label="Zero Latency Tuning"
            name="zerolatency"
            description="Adds -tune zerolatency. Note: the hardware encoder (h264_v4l2m2m) largely ignores this. Default: off."
          >
            <USwitch v-model="uiSettings.zerolatency" color="primary" />
          </UFormField>
        </div>

        <USeparator class="my-2" />

        <p class="text-xs text-gray-500">
          Saving rewrites the <code>runOnInit</code> command in the system
          <code>mediamtx.yml</code> and restarts MediaMTX. The boot-safe capture wrapper is
          always kept. Input format is fixed to MJPEG. Browser playback always uses
          WebRTC (UDP) regardless of the RTSP transport above.
        </p>

        <div class="pt-2 flex items-center justify-end gap-4">
          <span v-if="saveError" class="text-red-500 text-sm">{{ saveError }}</span>
          <span v-if="saveSuccess" class="text-green-500 text-sm flex items-center gap-1">
            <UIcon name="i-heroicons-check-circle" /> Saved &amp; stream restarted
          </span>
          <UButton type="submit" color="primary" :loading="isSaving" icon="i-heroicons-document-check">
            Save &amp; Restart Stream
          </UButton>
        </div>
      </UForm>
    </UCard>
  </div>
</template>
