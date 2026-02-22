import './assets/main.css'

import { addCollection } from '@iconify/vue'
import heroicons from '@iconify-json/heroicons/icons.json'
//import lucide from '@iconify-json/lucide/icons.json'

// Register full collections for offline use
addCollection(heroicons)
//addCollection(lucide)

import { createApp } from 'vue'
import App from './App.vue'
import router from './router'
import ui from '@nuxt/ui/vue-plugin'

const app = createApp(App)

app.use(router)
app.use(ui)

app.mount('#app')
