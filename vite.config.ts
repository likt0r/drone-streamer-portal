import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import ui from '@nuxt/ui/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    ui({
      ui: {
        colors: {
          primary: 'orange',
        },
      },
    }),
    vueDevTools(),
  ],
  server: {
    host: true, // bind to 0.0.0.0 so nginx (dev-pi.conf) can reach it
    allowedHosts: true, // reached via nginx, which forwards the Pi's Host header
    hmr: {
      clientPort: 80, // HMR websocket is proxied through nginx on port 80
    },
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
