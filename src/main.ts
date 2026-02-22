import './assets/main.css'

import { addIcon } from '@iconify/vue'
import devicePhoneMobile from '@iconify-icons/heroicons/device-phone-mobile'
import exclamationTriangle from '@iconify-icons/heroicons/exclamation-triangle'
import eye from '@iconify-icons/heroicons/eye'
import xMark from '@iconify-icons/heroicons/x-mark'

addIcon('heroicons-device-phone-mobile', devicePhoneMobile)
addIcon('heroicons-exclamation-triangle', exclamationTriangle)
addIcon('heroicons-eye', eye)
addIcon('heroicons-x-mark', xMark)

import { createApp } from 'vue'
import App from './App.vue'
import router from './router'
import ui from '@nuxt/ui/vue-plugin'

const app = createApp(App)

app.use(router)
app.use(ui)

app.mount('#app')
