<script setup lang="ts">
/**
 * PWA install banner shown on the home screen.
 * Android/Chrome: captures beforeinstallprompt (HTTPS only) and offers the
 * native install dialog. iOS: no install API exists, so show instructions
 * for Share → Add to Home Screen instead. Hidden once installed or dismissed.
 */
import { ref, onMounted, onBeforeUnmount } from 'vue'

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

const DISMISS_KEY = 'pwa-install-dismissed'

const installEvent = ref<BeforeInstallPromptEvent | null>(null)
const showIosHint = ref(false)
const dismissed = ref(localStorage.getItem(DISMISS_KEY) === '1')

const isStandalone = () =>
  window.matchMedia('(display-mode: standalone), (display-mode: fullscreen)').matches ||
  (navigator as Navigator & { standalone?: boolean }).standalone === true

const isIos = () =>
  /iPhone|iPad|iPod/.test(navigator.userAgent) ||
  // iPadOS reports itself as a Mac, but Macs have no touch screen
  (navigator.userAgent.includes('Macintosh') && navigator.maxTouchPoints > 1)

const isAndroid = () => /Android/.test(navigator.userAgent)

const handleBeforeInstallPrompt = (e: Event) => {
  e.preventDefault()
  installEvent.value = e as BeforeInstallPromptEvent
}

onMounted(() => {
  if (isStandalone()) return
  // Mobile only: desktop browsers fire beforeinstallprompt too, but
  // installing makes no sense there (fullscreen works directly)
  if (isAndroid()) {
    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
  }
  showIosHint.value = isIos()
})

onBeforeUnmount(() => {
  window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt)
})

const install = async () => {
  if (!installEvent.value) return
  await installEvent.value.prompt()
  const choice = await installEvent.value.userChoice
  if (choice.outcome === 'accepted') installEvent.value = null
}

const dismiss = () => {
  dismissed.value = true
  localStorage.setItem(DISMISS_KEY, '1')
}
</script>

<template>
  <div
    v-if="!dismissed && (installEvent || showIosHint)"
    class="fixed bottom-4 inset-x-4 z-50 mx-auto max-w-md rounded-xl bg-neutral-900/95 ring-1 ring-neutral-700 p-4 flex items-center gap-3"
  >
    <UIcon name="i-heroicons-device-phone-mobile" class="size-8 shrink-0 text-primary-500" />

    <div class="flex-1 text-sm text-neutral-200">
      <template v-if="installEvent">
        Install the portal as an app for fullscreen streaming without browser bars.
      </template>
      <template v-else>
        Install for fullscreen VR: tap
        <UIcon name="i-heroicons-arrow-up-on-square" class="inline size-4 align-text-bottom" />
        Share, then <span class="font-semibold">"Add to Home Screen"</span>.
      </template>
    </div>

    <UButton v-if="installEvent" color="primary" size="sm" class="cursor-pointer" @click="install">
      Install
    </UButton>
    <UButton
      icon="i-heroicons-x-mark"
      color="neutral"
      variant="ghost"
      size="sm"
      class="cursor-pointer shrink-0"
      aria-label="Dismiss"
      @click="dismiss"
    />
  </div>
</template>
