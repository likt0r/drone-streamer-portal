<script setup lang="ts">
import VrStream from './components/VrStream.vue'

const testingStreamUrl = 'http://localhost:8889/fpv'
</script>

<template>
  <UApp>
    <!-- We inject the VrStream component here on the main page for testing -->
    <VrStream :stream-url="testingStreamUrl" />
  </UApp>
</template>

<style scoped></style>
