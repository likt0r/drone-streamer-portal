<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  TimeScale,
} from 'chart.js'
import 'chartjs-adapter-date-fns'

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  TimeScale,
)

interface StatResponse {
  timestamp: number
  cpu_temp: number
  gpu_temp: number
  cpu_load: number
  gpu_load: number
  fan_rpm: number | null
}

interface FanState {
  mode: 'auto' | 'manual'
  manual_on: boolean
  temp_on: number
  temp_off: number
  state: 'on' | 'off'
  available: boolean
  rpm: number
}

// Current live values to display prominently
const currentCpuTemp = ref<number>(0)
const currentGpuTemp = ref<number>(0)
const currentCpuLoad = ref<number>(0)
const currentGpuLoad = ref<number>(0)
// null when the backend has no fan/GPIO (e.g. dev laptop)
const currentFanRpm = ref<number | null>(null)

// Fan control state (mirrors GET/POST /api/fan-settings)
const fan = ref<FanState>({
  mode: 'auto',
  manual_on: false,
  temp_on: 60,
  temp_off: 50,
  state: 'off',
  available: false,
  rpm: 0,
})
const fanSaving = ref(false)

const modeItems = [
  { label: 'Automatisch (Temperatur)', value: 'auto' },
  { label: 'Manuell', value: 'manual' },
]

// Live "is the fan spinning?" derived from the tacho reading.
const fanRunning = computed(() => (currentFanRpm.value ?? 0) > 0)

const historyData = ref<StatResponse[]>([])
const ws = ref<WebSocket | null>(null)
let wsClosedByUs = false

// Chart options to configure Time X-axis properly
const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: {
    duration: 0, // Disable animation for live graph feel
  },
  scales: {
    x: {
      type: 'time',
      time: {
        unit: 'minute',
        displayFormats: {
          minute: 'HH:mm',
        },
      },
      title: {
        display: true,
        text: 'Time',
        color: '#9ca3af',
      },
      ticks: {
        color: '#9ca3af',
      },
      grid: {
        color: '#374151',
      },
    },
    y: {
      ticks: {
        color: '#9ca3af',
      },
      grid: {
        color: '#374151',
      },
    },
  },
  plugins: {
    legend: {
      labels: {
        color: '#f3f4f6',
      },
    },
  },
  interaction: {
    mode: 'index' as const,
    intersect: false,
  },
} as const

const getTemperatureChartData = () => {
  return {
    datasets: [
      {
        label: 'CPU (°C)',
        backgroundColor: '#ef4444',
        borderColor: '#ef4444',
        data: historyData.value.map((s) => ({ x: s.timestamp, y: s.cpu_temp })),
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.1,
      },
      {
        label: 'GPU (°C)',
        backgroundColor: '#3b82f6',
        borderColor: '#3b82f6',
        data: historyData.value.map((s) => ({ x: s.timestamp, y: s.gpu_temp })),
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.1,
      },
    ],
  }
}

const getLoadChartData = () => {
  return {
    datasets: [
      {
        label: 'CPU (%)',
        backgroundColor: '#10b981',
        borderColor: '#10b981',
        data: historyData.value.map((s) => ({ x: s.timestamp, y: s.cpu_load })),
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.1,
      },
      {
        label: 'GPU (%)',
        backgroundColor: '#a855f7',
        borderColor: '#a855f7',
        data: historyData.value.map((s) => ({ x: s.timestamp, y: s.gpu_load })),
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.1,
      },
    ],
  }
}

const getFanChartData = () => {
  return {
    datasets: [
      {
        label: 'Fan (RPM)',
        backgroundColor: '#f59e0b',
        borderColor: '#f59e0b',
        data: historyData.value.map((s) => ({ x: s.timestamp, y: s.fan_rpm })),
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.1,
      },
    ],
  }
}

const PORT = 5002

const fetchHistory = async () => {
  try {
    const host = window.location.hostname
    const res = await fetch(`http://${host}:${PORT}/api/stats/history`)
    const data = await res.json()
    historyData.value = data

    if (data.length > 0) {
      const last = data[data.length - 1]
      currentCpuTemp.value = Math.round(last.cpu_temp)
      currentGpuTemp.value = Math.round(last.gpu_temp)
      currentCpuLoad.value = Math.round(last.cpu_load)
      currentGpuLoad.value = Math.round(last.gpu_load)
      currentFanRpm.value = last.fan_rpm === null ? null : Math.round(last.fan_rpm)
    }
  } catch (err) {
    console.error('Failed to fetch history:', err)
  }
}

const fetchFanSettings = async () => {
  try {
    const host = window.location.hostname
    const res = await fetch(`http://${host}:${PORT}/api/fan-settings`)
    fan.value = await res.json()
  } catch (err) {
    console.error('Failed to fetch fan settings:', err)
  }
}

const saveFanSettings = async () => {
  fanSaving.value = true
  try {
    const host = window.location.hostname
    const res = await fetch(`http://${host}:${PORT}/api/fan-settings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        mode: fan.value.mode,
        manual_on: fan.value.manual_on,
        temp_on: fan.value.temp_on,
        temp_off: fan.value.temp_off,
      }),
    })
    fan.value = await res.json()
  } catch (err) {
    console.error('Failed to save fan settings:', err)
  } finally {
    fanSaving.value = false
  }
}

const connectWebSocket = () => {
  const host = window.location.hostname
  ws.value = new WebSocket(`ws://${host}:${PORT}/ws/stats`)

  ws.value.onmessage = (event) => {
    const data: StatResponse = JSON.parse(event.data)

    // Update live readouts
    currentCpuTemp.value = Math.round(data.cpu_temp)
    currentGpuTemp.value = Math.round(data.gpu_temp)
    currentCpuLoad.value = Math.round(data.cpu_load)
    currentGpuLoad.value = Math.round(data.gpu_load)
    currentFanRpm.value = data.fan_rpm === null ? null : Math.round(data.fan_rpm)

    // Append to array and manage 30 minute array strictly if frontend misses cleanup
    historyData.value.push(data)
    if (historyData.value.length > 1800) {
      historyData.value.shift()
    }
  }

  ws.value.onclose = () => {
    if (wsClosedByUs) return
    console.log('WebSocket disconnected, reconnecting in 5s...')
    setTimeout(connectWebSocket, 5000)
  }
}

onMounted(async () => {
  await Promise.all([fetchHistory(), fetchFanSettings()])
  connectWebSocket()
})

onUnmounted(() => {
  wsClosedByUs = true
  if (ws.value) {
    ws.value.close()
  }
})
</script>

<template>
  <div>
    <div class="flex flex-wrap items-center justify-center gap-1 sm:gap-4 mb-6">
      <UBadge
        color="error"
        variant="soft"
        size="md"
        icon="i-heroicons-fire"
        :ui="{ rounded: 'rounded-full' }"
      >
        <span class="font-normal text-gray-400 mr-1 hidden sm:inline">CPU:</span>
        <span class="font-bold text-white inline-block w-[3ch] text-right">{{
          currentCpuTemp
        }}</span
        ><span class="font-normal opacity-75 ml-0.5 text-gray-400">°C</span>
      </UBadge>

      <UBadge
        color="info"
        variant="soft"
        size="md"
        icon="i-heroicons-fire"
        :ui="{ rounded: 'rounded-full' }"
      >
        <span class="font-normal text-gray-400 mr-1 hidden sm:inline">GPU:</span>
        <span class="font-bold text-white inline-block w-[3ch] text-right">{{
          currentGpuTemp
        }}</span
        ><span class="font-normal opacity-75 ml-0.5 text-gray-400">°C</span>
      </UBadge>

      <UBadge
        color="success"
        variant="soft"
        size="md"
        icon="i-heroicons-cpu-chip"
        :ui="{ rounded: 'rounded-full' }"
      >
        <span class="font-normal text-gray-400 mr-1 hidden sm:inline">CPU Load:</span>
        <span class="font-bold text-white inline-block w-[3ch] text-right">{{
          currentCpuLoad
        }}</span
        ><span class="font-normal opacity-75 ml-0.5 text-gray-400">%</span>
      </UBadge>

      <UBadge
        color="primary"
        variant="soft"
        size="md"
        icon="i-heroicons-cpu-chip"
        :ui="{ rounded: 'rounded-full' }"
      >
        <span class="font-normal text-gray-400 mr-1 hidden sm:inline">GPU Load:</span>
        <span class="font-bold text-white inline-block w-[3ch] text-right">{{
          currentGpuLoad
        }}</span
        ><span class="font-normal opacity-75 ml-0.5 text-gray-400">%</span>
      </UBadge>

      <UBadge
        color="warning"
        variant="soft"
        size="md"
        icon="i-heroicons-arrow-path"
        :ui="{ rounded: 'rounded-full' }"
      >
        <span class="font-normal text-gray-400 mr-1 hidden sm:inline">Fan:</span>
        <span class="font-bold text-white inline-block w-[4ch] text-right">{{
          currentFanRpm === null ? '—' : currentFanRpm
        }}</span
        ><span class="font-normal opacity-75 ml-0.5 text-gray-400">RPM</span>
      </UBadge>
    </div>

    <!-- Charts -->
    <div class="grid grid-cols-1 gap-6">
      <UCard :ui="{ background: 'bg-black', ring: 'ring-gray-800' }">
        <template #header>
          <h3 class="font-semibold text-white">Temperature History</h3>
        </template>
        <div class="h-[300px]">
          <Line
            v-if="historyData.length > 0"
            :data="getTemperatureChartData()"
            :options="chartOptions as any"
          />
          <div v-else class="h-full flex items-center justify-center text-gray-500">
            Loading data...
          </div>
        </div>
      </UCard>

      <UCard :ui="{ background: 'bg-black', ring: 'ring-gray-800' }">
        <template #header>
          <h3 class="font-semibold text-white">System Load History</h3>
        </template>
        <div class="h-[300px]">
          <Line
            v-if="historyData.length > 0"
            :data="getLoadChartData()"
            :options="
              {
                ...chartOptions,
                scales: {
                  x: chartOptions.scales.x,
                  y: { ...chartOptions.scales.y, min: 0, max: 100 },
                },
              } as any
            "
          />
          <div v-else class="h-full flex items-center justify-center text-gray-500">
            Loading data...
          </div>
        </div>
      </UCard>

      <UCard :ui="{ background: 'bg-black', ring: 'ring-gray-800' }">
        <template #header>
          <h3 class="font-semibold text-white">Fan Speed History</h3>
        </template>
        <div class="h-[300px]">
          <Line
            v-if="historyData.length > 0"
            :data="getFanChartData()"
            :options="
              {
                ...chartOptions,
                scales: {
                  x: chartOptions.scales.x,
                  y: { ...chartOptions.scales.y, min: 0 },
                },
              } as any
            "
          />
          <div v-else class="h-full flex items-center justify-center text-gray-500">
            Loading data...
          </div>
        </div>
      </UCard>

      <!-- Fan control -->
      <UCard :ui="{ background: 'bg-black', ring: 'ring-gray-800' }">
        <template #header>
          <div class="flex items-center justify-between">
            <h3 class="font-semibold text-white">Fan Control</h3>
            <UBadge
              :color="fanRunning ? 'success' : 'neutral'"
              variant="soft"
              size="sm"
              :icon="fanRunning ? 'i-heroicons-arrow-path' : 'i-heroicons-pause'"
            >
              {{ fanRunning ? 'läuft' : 'steht' }}
            </UBadge>
          </div>
        </template>

        <div class="space-y-6">
          <p v-if="!fan.available" class="text-amber-500 text-sm flex items-center gap-1">
            <UIcon name="i-heroicons-exclamation-triangle" />
            GPIO nicht verfügbar (kein Raspberry Pi / kein Zugriff) — Steuerung inaktiv.
          </p>

          <UFormField
            label="Modus"
            description="Automatisch regelt per CPU-Temperatur (An/Aus mit Hysterese). Manuell schaltet fest."
          >
            <USelect
              v-model="fan.mode"
              value-key="value"
              :items="modeItems"
              class="w-full sm:w-72"
              :disabled="!fan.available"
              @update:model-value="saveFanSettings"
            />
          </UFormField>

          <UFormField
            v-if="fan.mode === 'manual'"
            label="Lüfter an"
            description="Schaltet den Lüfter dauerhaft ein oder aus."
          >
            <USwitch
              v-model="fan.manual_on"
              color="primary"
              :disabled="!fan.available"
              @update:model-value="saveFanSettings"
            />
          </UFormField>

          <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <UFormField
              label="Einschalten ab (°C)"
              description="Über dieser CPU-Temperatur läuft der Lüfter."
            >
              <UInput v-model.number="fan.temp_on" type="number" :disabled="!fan.available">
                <template #trailing><span class="text-gray-400 text-xs">°C</span></template>
              </UInput>
            </UFormField>
            <UFormField
              label="Ausschalten unter (°C)"
              description="Unter dieser Temperatur schaltet der Lüfter wieder aus (muss kleiner als der Einschaltwert sein)."
            >
              <UInput v-model.number="fan.temp_off" type="number" :disabled="!fan.available">
                <template #trailing><span class="text-gray-400 text-xs">°C</span></template>
              </UInput>
            </UFormField>
          </div>

          <div v-if="fan.mode === 'auto'" class="flex justify-end">
            <UButton
              color="primary"
              :loading="fanSaving"
              :disabled="!fan.available"
              icon="i-heroicons-document-check"
              @click="saveFanSettings"
            >
              Schwellen speichern
            </UButton>
          </div>
        </div>
      </UCard>
    </div>
  </div>
</template>
