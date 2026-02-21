<script setup lang="ts">
/**
 * Antigravity VR Engine - Vue 3 / TS
 * High Performance Canvas Rendering for Normal Stream
 */
import { ref, onBeforeUnmount } from 'vue'
import { WebRTCClient } from '../utils/webrtc.client'
import { useRouter } from 'vue-router'

const props = defineProps<{
  streamUrl: string // e.g., http://192.168.4.1:8889/fpv
}>()

const router = useRouter()

const videoRef = ref<HTMLVideoElement | null>(null)
const canvasRef = ref<HTMLCanvasElement | null>(null)
const isStreaming = ref(false)
const errorMsg = ref<string | null>(null)

let webRTCClient: WebRTCClient | null = null
let renderFrameId: number | null = null

const startStream = async () => {
  if (!videoRef.value || !canvasRef.value) return
  errorMsg.value = null

  // 1. Request Fullscreen via Native API
  if (document.documentElement.requestFullscreen) {
    try {
      await document.documentElement.requestFullscreen()
    } catch (e) {
      console.warn('Fullscreen request failed, but continuing stream', e)
    }
  }

  // 1.5 Setup canvas initial size and resize listener
  updateCanvasSize()
  window.addEventListener('resize', updateCanvasSize)

  // 2. Setup WebRTC Handshake
  webRTCClient = new WebRTCClient({
    url: props.streamUrl,
    videoElement: videoRef.value,
    onConnect: () => {
      console.log('WebRTC Connected')
      isStreaming.value = true
      videoRef.value?.play().catch((e) => console.error(e))
      renderLoop()
    },
    onDisconnect: () => {
      console.log('WebRTC Disconnected')
      isStreaming.value = false
      stopRenderLoop()
    },
    onError: (err) => {
      console.error('WebRTC Error', err)
      errorMsg.value = `Failed to connect to stream: ${err.message}`
      isStreaming.value = false
      stopRenderLoop()
    },
  })

  await webRTCClient.connect()
}

const stopStream = () => {
  window.removeEventListener('resize', updateCanvasSize)

  if (webRTCClient) {
    webRTCClient.disconnect()
    webRTCClient = null
  }
  isStreaming.value = false
  stopRenderLoop()

  if (document.fullscreenElement && document.exitFullscreen) {
    document.exitFullscreen().catch((e) => console.warn('Exit fullscreen failed:', e))
  }
}

const goBack = () => {
  stopStream()
  router.push('/')
}

const updateCanvasSize = () => {
  if (!canvasRef.value) return
  // Sync canvas size to screen density to avoid blurry rendering
  canvasRef.value.width = window.innerWidth * window.devicePixelRatio
  canvasRef.value.height = window.innerHeight * window.devicePixelRatio
}

const renderLoop = () => {
  if (!canvasRef.value || !videoRef.value || !isStreaming.value) {
    renderFrameId = requestAnimationFrame(renderLoop)
    return
  }

  const ctx = canvasRef.value.getContext('2d', { alpha: false })
  if (!ctx) return

  const w = canvasRef.value.width
  const h = canvasRef.value.height

  // Draw Logic
  ctx.fillStyle = 'black'
  ctx.fillRect(0, 0, w, h)

  // Check if video is playing and has data
  if (videoRef.value.readyState >= 2) {
    const vw = videoRef.value.videoWidth
    const vh = videoRef.value.videoHeight

    if (vw > 0 && vh > 0) {
      // Use "contain" logic to fit the entire video
      const scale = Math.min(w / vw, h / vh)

      const drawWidth = vw * scale
      const drawHeight = vh * scale

      const offsetX = (w - drawWidth) / 2
      const offsetY = (h - drawHeight) / 2

      ctx.drawImage(videoRef.value, 0, 0, vw, vh, offsetX, offsetY, drawWidth, drawHeight)
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

onBeforeUnmount(() => {
  stopStream()
})
</script>

<template>
  <div class="relative w-full h-screen bg-black flex flex-col items-center justify-center">
    <div v-if="errorMsg" class="absolute top-4 w-full px-4 z-50">
      <UAlert
        color="red"
        variant="solid"
        title="Streaming Error"
        :description="errorMsg"
        icon="i-heroicons-exclamation-triangle"
        @close="errorMsg = null"
      />
    </div>

    <!-- Give the user a go back button too -->
    <div v-if="!isStreaming" class="absolute top-4 left-4 z-50">
      <UButton color="gray" variant="ghost" icon="i-heroicons-arrow-left" @click="goBack">
        Back
      </UButton>
    </div>

    <div v-if="!isStreaming" class="flex flex-col items-center gap-4 z-10">
      <UButton color="blue" variant="solid" size="xl" icon="i-heroicons-play" @click="startStream">
        Launch Normal Stream
      </UButton>
      <div class="text-neutral-400 text-sm">Stream URL: {{ props.streamUrl }}</div>
    </div>

    <!-- The actual canvas overlaying the entire screen when streaming -->
    <canvas
      v-show="isStreaming"
      ref="canvasRef"
      class="absolute inset-0 w-full h-full cursor-none z-0"
    />

    <!-- Hidden exit button when hovering near top during stream -->
    <div
      v-if="isStreaming"
      class="absolute top-0 w-full h-16 hover:opacity-100 opacity-0 transition-opacity flex justify-center items-start pt-2 z-50"
    >
      <UButton color="gray" variant="solid" icon="i-heroicons-x-mark" @click="goBack">
        Exit Stream
      </UButton>
    </div>

    <video ref="videoRef" class="hidden" muted playsinline />
  </div>
</template>
