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
    // On the Pi (PI_DEV=1, set in drone-dev-web.service) the HMR websocket is
    // proxied through nginx on port 80; locally Vite serves it directly.
    hmr: process.env.PI_DEV ? { clientPort: 80 } : undefined,
    proxy: {
      // Local dev without the Pi: forward WHEP to a MediaMTX on this machine.
      // On the Pi this is unused — nginx routes /whep before it reaches Vite.
      '^/[^/]+/whep$': {
        target: 'http://localhost:8889',
      },
    },
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
