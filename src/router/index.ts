import { createRouter, createWebHistory } from 'vue-router'
import StreamPage from '../components/StreamPage.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: StreamPage,
      props: { streamUrl: `http://${location.host}/fpv` },
    },
  ],
})

export default router
