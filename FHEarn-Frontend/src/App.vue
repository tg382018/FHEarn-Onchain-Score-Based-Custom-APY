<template>
  <div class="app">
    <FHEarn />
  </div>
</template>

<script lang="ts">
import { defineComponent } from "vue";
import FHEarn from "./components/FHEarn.vue";

export default defineComponent({
  name: "App",
  components: {
    FHEarn,
  },
});
</script>

<style>
/* Global styles */
</style>
