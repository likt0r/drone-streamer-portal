<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { z } from 'zod'

const PORT = 5002
const host = window.location.hostname

const schema = z
  .object({
    hostname: z
      .string()
      .regex(/^[a-z0-9][a-z0-9-]{0,62}$/, 'Lowercase a–z, 0–9 and "-" only (max 63)'),
    ap_ssid: z.string().min(1, 'Required').max(32, 'Max 32 characters'),
    ap_psk: z.string(),
    ap_ip: z.string().regex(/^(\d{1,3}\.){3}\d{1,3}$/, 'IPv4 address, e.g. 192.168.50.5'),
    ap_open: z.boolean(),
  })
  .superRefine((val, ctx) => {
    if (!val.ap_open && !(val.ap_psk.length >= 8 && val.ap_psk.length <= 63)) {
      ctx.addIssue({
        path: ['ap_psk'],
        code: z.ZodIssueCode.custom,
        message: 'At least 8 characters (or enable the open network option)',
      })
    }
  })

const ui = ref({ hostname: '', ap_ssid: '', ap_psk: '', ap_ip: '', ap_open: false })
const meta = ref({ band: '', channel: '' })
const showPw = ref(false)

const isSaving = ref(false)
const saveOk = ref(false)
const saveMsg = ref('')
const saveError = ref('')

const bandLabel = computed(() =>
  meta.value.band === 'a' ? '5 GHz' : meta.value.band === 'bg' ? '2.4 GHz' : meta.value.band || '—',
)

const fetchSettings = async () => {
  try {
    const res = await fetch(`http://${host}:${PORT}/api/network-settings`)
    const d = await res.json()
    ui.value.hostname = d.hostname || ''
    ui.value.ap_ssid = d.ap_ssid || ''
    ui.value.ap_psk = d.ap_psk || ''
    ui.value.ap_ip = d.ap_ip || ''
    ui.value.ap_open = !!d.ap_open
    meta.value.band = d.band || ''
    meta.value.channel = d.channel || ''
  } catch (err) {
    console.error('Failed to fetch network settings:', err)
  }
}

const save = async () => {
  isSaving.value = true
  saveOk.value = false
  saveMsg.value = ''
  saveError.value = ''
  try {
    const res = await fetch(`http://${host}:${PORT}/api/network-settings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        hostname: ui.value.hostname.trim().toLowerCase(),
        ap_ssid: ui.value.ap_ssid,
        ap_psk: ui.value.ap_psk,
        ap_ip: ui.value.ap_ip,
        ap_open: ui.value.ap_open,
      }),
    })
    const r = await res.json()
    if (r.status === 'success') {
      saveOk.value = true
      saveMsg.value = r.message || 'Saved.'
    } else {
      saveError.value = r.message || 'Error saving settings'
    }
  } catch (err) {
    console.error('Failed to save network settings:', err)
    saveError.value = 'Network error saving settings'
  } finally {
    isSaving.value = false
  }
}

onMounted(fetchSettings)
</script>

<template>
  <div>
    <UAlert
      class="mb-6"
      color="warning"
      variant="soft"
      icon="i-heroicons-exclamation-triangle"
      title="Changing the hotspot disconnects you"
      description="Saving a new Wi-Fi name, password or hotspot IP restarts the access point. You will be disconnected and must reconnect to the (new) Wi-Fi, then reopen the portal at the new hostname or IP."
    />

    <UCard :ui="{ background: 'bg-black', ring: 'ring-gray-800' }">
      <UForm :schema="schema" :state="ui" @submit="save" class="space-y-6">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <!-- Hostname -->
          <UFormField
            label="Hostname"
            name="hostname"
            description="Device name. Reachable in the browser as http://<hostname>.local/ (and .box). Default: pi-caster."
          >
            <UInput
              v-model="ui.hostname"
              placeholder="pi-caster"
              icon="i-heroicons-server"
            />
          </UFormField>

          <!-- Hotspot SSID -->
          <UFormField
            label="Hotspot Wi-Fi Name (SSID)"
            name="ap_ssid"
            description="The Wi-Fi network the Pi broadcasts. 1–32 characters."
          >
            <UInput v-model="ui.ap_ssid" placeholder="pi-caster" icon="i-heroicons-wifi" />
          </UFormField>

          <!-- Open network toggle -->
          <UFormField
            label="Open Network (no password)"
            name="ap_open"
            description="Broadcast the hotspot without a password. Anyone nearby can connect — use with care."
          >
            <USwitch v-model="ui.ap_open" color="primary" />
          </UFormField>

          <!-- Hotspot password (hidden when open) -->
          <UFormField
            v-if="!ui.ap_open"
            label="Hotspot Password"
            name="ap_psk"
            description="WPA2 password for the hotspot. 8–63 characters."
          >
            <UInput
              v-model="ui.ap_psk"
              :type="showPw ? 'text' : 'password'"
              placeholder="••••••••"
              icon="i-heroicons-key"
            >
              <template #trailing>
                <UButton
                  color="neutral"
                  variant="link"
                  size="xs"
                  :icon="showPw ? 'i-heroicons-eye-slash' : 'i-heroicons-eye'"
                  :aria-label="showPw ? 'Hide password' : 'Show password'"
                  @click="showPw = !showPw"
                />
              </template>
            </UInput>
          </UFormField>

          <!-- Hotspot IP -->
          <UFormField
            label="Hotspot IP Address"
            name="ap_ip"
            description="The Pi's own address inside the hotspot (the /24 subnet derives from it). Default: 192.168.50.5."
          >
            <UInput v-model="ui.ap_ip" placeholder="192.168.50.5" icon="i-heroicons-globe-alt" />
          </UFormField>
        </div>

        <USeparator class="my-2" />

        <p class="text-xs text-gray-500">
          Wi-Fi band <span class="text-gray-300">{{ bandLabel }}</span> / channel
          <span class="text-gray-300">{{ meta.channel || '—' }}</span>
          are read-only here (changing the 5&nbsp;GHz channel can take the hotspot offline).
        </p>

        <div class="pt-2 flex items-center justify-end gap-4">
          <span v-if="saveError" class="text-red-500 text-sm">{{ saveError }}</span>
          <span v-if="saveOk" class="text-green-500 text-sm flex items-center gap-1">
            <UIcon name="i-heroicons-check-circle" /> {{ saveMsg }}
          </span>
          <UButton type="submit" color="primary" :loading="isSaving" icon="i-heroicons-document-check">
            Save Network Settings
          </UButton>
        </div>
      </UForm>
    </UCard>
  </div>
</template>
