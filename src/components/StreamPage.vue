<script setup lang="ts">
/**
 * Drone Streamer Portal FPV Portal - Unified Stream Page
 * One-click streaming with VR and Normal modes.
 */
import { ref, onMounted, onUnmounted } from 'vue'
import { WebRTCClient } from '../utils/webrtc.client'
import StreamButton from './StreamButton.vue'

const props = defineProps<{
  streamUrl: string
}>()

// ─── State ────────────────────────────────────────────────────────────────────
type Mode = 'normal' | 'vr'
type Status = 'idle' | 'connecting' | 'streaming' | 'error'

const status = ref<Status>('idle')
const mode = ref<Mode>('normal')
const errorMsg = ref<string | null>(null)
const isFullscreen = ref(false)

const videoRef = ref<HTMLVideoElement | null>(null)
const canvasRef = ref<HTMLCanvasElement | null>(null)

let webRTCClient: WebRTCClient | null = null
let renderFrameId: number | null = null

const handleFullscreenChange = () => {
  isFullscreen.value = !!document.fullscreenElement
}

onMounted(() => {
  document.addEventListener('fullscreenchange', handleFullscreenChange)
})

onUnmounted(() => {
  document.removeEventListener('fullscreenchange', handleFullscreenChange)
})

const requestFullscreen = async () => {
  if (document.documentElement.requestFullscreen) {
    try {
      await document.documentElement.requestFullscreen()
    } catch (_) {}
  }
}

// ─── Start ────────────────────────────────────────────────────────────────────
const launch = async (selectedMode: Mode) => {
  if (!videoRef.value || !canvasRef.value) return

  mode.value = selectedMode
  status.value = 'connecting'
  errorMsg.value = null

  await requestFullscreen()

  updateCanvasSize()
  window.addEventListener('resize', updateCanvasSize)

  // Push a history entry so the back button fires popstate instead of navigating away
  history.pushState({ streaming: true }, '')
  window.addEventListener('popstate', handlePopState)

  webRTCClient = new WebRTCClient({
    url: props.streamUrl,
    videoElement: videoRef.value,
    onConnect: () => {
      status.value = 'streaming'
      videoRef.value?.play().catch(console.error)
      renderLoop()
    },
    onDisconnect: () => {
      status.value = 'idle'
      stopRenderLoop()
    },
    onError: (err) => {
      errorMsg.value = `Connection failed: ${err.message}`
      status.value = 'error'
      stopRenderLoop()
    },
  })

  await webRTCClient.connect()
}

// ─── Stop ─────────────────────────────────────────────────────────────────────
const handlePopState = () => stop()

const stop = () => {
  window.removeEventListener('resize', updateCanvasSize)
  window.removeEventListener('popstate', handlePopState)
  webRTCClient?.disconnect()
  webRTCClient = null
  stopRenderLoop()
  status.value = 'idle'
  if (document.fullscreenElement) {
    document.exitFullscreen().catch(() => {})
  }
}

// ─── Canvas ───────────────────────────────────────────────────────────────────
const updateCanvasSize = () => {
  if (!canvasRef.value) return
  canvasRef.value.width = window.innerWidth * window.devicePixelRatio
  canvasRef.value.height = window.innerHeight * window.devicePixelRatio
}

const renderLoop = () => {
  if (!canvasRef.value || !videoRef.value || status.value !== 'streaming') {
    renderFrameId = requestAnimationFrame(renderLoop)
    return
  }

  const ctx = canvasRef.value.getContext('2d', { alpha: false })
  if (!ctx) return

  const cw = canvasRef.value.width
  const ch = canvasRef.value.height

  ctx.fillStyle = 'black'
  ctx.fillRect(0, 0, cw, ch)

  if (videoRef.value.readyState >= 2) {
    const vw = videoRef.value.videoWidth
    const vh = videoRef.value.videoHeight

    if (vw > 0 && vh > 0) {
      if (mode.value === 'vr') {
        // Each eye gets half the canvas width
        const eyeW = cw / 2
        const scale = Math.min(eyeW / vw, ch / vh)
        const dw = vw * scale
        const dh = vh * scale
        const ox = (eyeW - dw) / 2
        const oy = (ch - dh) / 2

        ctx.drawImage(videoRef.value, 0, 0, vw, vh, ox, oy, dw, dh)
        ctx.drawImage(videoRef.value, 0, 0, vw, vh, eyeW + ox, oy, dw, dh)
      } else {
        // Normal: contain the video in the full canvas
        const scale = Math.min(cw / vw, ch / vh)
        const dw = vw * scale
        const dh = vh * scale
        const ox = (cw - dw) / 2
        const oy = (ch - dh) / 2
        ctx.drawImage(videoRef.value, 0, 0, vw, vh, ox, oy, dw, dh)
      }
    }
  }

  renderFrameId = requestAnimationFrame(renderLoop)
}

const stopRenderLoop = () => {
  if (renderFrameId !== null) {
    cancelAnimationFrame(renderFrameId)
    renderFrameId = null
  }
}
</script>

<template>
  <div class="relative w-full h-screen bg-black flex flex-col items-center justify-center">
    <!-- ── HOME ─────────────────────────────────────────────────────────────── -->
    <template v-if="status === 'idle'">
      <div class="absolute top-4 right-4 z-50">
        <UButton to="/info" icon="i-heroicons-chart-bar" color="white" variant="ghost" size="lg">
          Pi Stats
        </UButton>
      </div>
      <div class="flex flex-col items-center gap-8 px-6 w-full">
        <div class="flex flex-col landscape:flex-row gap-6">
          <StreamButton
            icon="i-heroicons-device-phone-mobile"
            label="Start Streaming"
            @click="launch('normal')"
          />
          <StreamButton icon="i-heroicons-eye" label="Start VR Mode" @click="launch('vr')" />
        </div>
      </div>
    </template>

    <!-- ── CONNECTING ────────────────────────────────────────────────────────── -->
    <template v-if="status === 'connecting'">
      <div class="flex flex-col items-center gap-6">
        <!-- Neon orange spinning ring -->
        <div class="relative w-24 h-24">
          <div class="absolute inset-0 rounded-full border-4 border-primary-500/20" />
          <div
            class="absolute inset-0 rounded-full border-4 border-transparent border-t-primary-500 animate-spin"
          />
        </div>
        <p class="text-primary-500 text-lg font-semibold tracking-widest uppercase animate-pulse">
          Connecting…
        </p>
        <UButton
          class="cursor-pointer"
          color="neutral"
          variant="solid"
          icon="i-heroicons-x-mark"
          @click="stop"
        >
          Cancel
        </UButton>
      </div>
    </template>

    <!-- ── ERROR ─────────────────────────────────────────────────────────────── -->
    <template v-if="status === 'error'">
      <div class="w-full px-4 max-w-md flex flex-col items-center gap-4">
        <UAlert
          color="error"
          variant="solid"
          title="Connection Failed"
          :description="errorMsg ?? ''"
          icon="i-heroicons-exclamation-triangle"
        />
        <UButton color="primary" variant="outline" @click="status = 'idle'">Try Again</UButton>
      </div>
    </template>

    <!-- ── STREAMING CANVAS ──────────────────────────────────────────────────── -->
    <canvas
      v-show="status === 'streaming'"
      ref="canvasRef"
      class="absolute inset-0 w-full h-full z-0"
    />

    <!-- Always visible exit bar -->
    <div
      v-if="status === 'streaming'"
      class="absolute top-0 w-full h-16 flex justify-center items-start pt-2 z-50 gap-4"
    >
      <UButton
        class="cursor-pointer"
        color="neutral"
        variant="solid"
        icon="i-heroicons-x-mark"
        @click="stop"
      >
        Exit Stream
      </UButton>
      <UButton
        class="cursor-pointer"
        v-if="!isFullscreen"
        color="neutral"
        variant="solid"
        icon="i-heroicons-arrows-pointing-out"
        @click="requestFullscreen"
      >
        Fullscreen
      </UButton>
    </div>

    <!-- Hidden video element used by WebRTC client -->
    <video ref="videoRef" class="hidden" muted playsinline />
  </div>
</template>
