import { createRouter, createWebHistory } from 'vue-router'

import Home from '../components/Home.vue'
import VrStream from '../components/VrStream.vue'
import NormalStream from '../components/NormalStream.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: Home,
    },
    {
      path: '/vr',
      name: 'vr',
      component: VrStream,
      props: { streamUrl: 'http://localhost:8889/fpv' },
    },
    {
      path: '/normal',
      name: 'normal',
      component: NormalStream,
      props: { streamUrl: 'http://localhost:8889/fpv' },
    },
  ],
})

export default router
