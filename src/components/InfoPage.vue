<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
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
}

// Current live values to display prominently
const currentCpuTemp = ref<number>(0)
const currentGpuTemp = ref<number>(0)
const currentCpuLoad = ref<number>(0)

const historyData = ref<StatResponse[]>([])
const ws = ref<WebSocket | null>(null)

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
        label: 'CPU Temp (°C)',
        backgroundColor: '#ef4444',
        borderColor: '#ef4444',
        data: historyData.value.map((s) => ({ x: s.timestamp, y: s.cpu_temp })),
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.1,
      },
      {
        label: 'GPU Temp (°C)',
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
        label: 'CPU Load (%)',
        backgroundColor: '#10b981',
        borderColor: '#10b981',
        data: historyData.value.map((s) => ({ x: s.timestamp, y: s.cpu_load })),
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.1,
        fill: true,
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
    }
  } catch (err) {
    console.error('Failed to fetch history:', err)
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

    // Append to array and manage 30 minute array strictly if frontend misses cleanup
    historyData.value.push(data)
    if (historyData.value.length > 1800) {
      historyData.value.shift()
    }
  }

  ws.value.onclose = () => {
    console.log('WebSocket disconnected, reconnecting in 5s...')
    setTimeout(connectWebSocket, 5000)
  }
}

onMounted(async () => {
  await fetchHistory()
  connectWebSocket()
})

onUnmounted(() => {
  if (ws.value) {
    ws.value.close()
  }
})
</script>

<template>
  <div class="dark bg-black min-h-screen w-full text-white">
    <UContainer class="py-8">
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-white">Hardware Monitoring</h1>
          <p class="text-gray-400">Live 30-minute system metrics</p>
        </div>
        <UButton to="/" icon="i-heroicons-arrow-left" color="primary" variant="ghost">
          Back to Stream
        </UButton>
      </div>

      <div class="flex flex-wrap items-center justify-center gap-2 sm:gap-4 mb-6 mt-[-10px]">
        <UBadge
          color="error"
          variant="soft"
          size="lg"
          icon="i-heroicons-fire"
          :ui="{ rounded: 'rounded-full' }"
        >
          <span class="font-normal text-gray-400 mr-1 hidden sm:inline">CPU:</span>
          <span class="font-bold text-white">{{ currentCpuTemp }}</span
          ><span class="font-normal opacity-75 ml-0.5 text-gray-400">°C</span>
        </UBadge>

        <UBadge
          color="info"
          variant="soft"
          size="lg"
          icon="i-heroicons-fire"
          :ui="{ rounded: 'rounded-full' }"
        >
          <span class="font-normal text-gray-400 mr-1 hidden sm:inline">GPU:</span>
          <span class="font-bold text-white">{{ currentGpuTemp }}</span
          ><span class="font-normal opacity-75 ml-0.5 text-gray-400">°C</span>
        </UBadge>

        <UBadge
          color="success"
          variant="soft"
          size="lg"
          icon="i-heroicons-cpu-chip"
          :ui="{ rounded: 'rounded-full' }"
        >
          <span class="font-normal text-gray-400 mr-1 hidden sm:inline">Load:</span>
          <span class="font-bold text-white">{{ currentCpuLoad }}</span
          ><span class="font-normal opacity-75 ml-0.5 text-gray-400">%</span>
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
            <h3 class="font-semibold text-white">CPU Load History</h3>
          </template>
          <div class="h-[300px]">
            <Line
              v-if="historyData.length > 0"
              :data="getLoadChartData()"
              :options="
                {
                  ...chartOptions,
                  scales: { x: chartOptions.scales.x, y: { min: 0, max: 100 } },
                } as any
              "
            />
            <div v-else class="h-full flex items-center justify-center text-gray-500">
              Loading data...
            </div>
          </div>
        </UCard>
      </div>
    </UContainer>
  </div>
</template>
