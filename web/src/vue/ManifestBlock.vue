<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive } from 'vue'
import { BlockController, type ErrorUri, type ManifestCaller } from '../runtime'

// A mounted block. It mounts when created and unmounts when removed.
const props = defineProps<{
  block: Record<string, any>
  context: Record<string, unknown>
  caller: ManifestCaller
  errorUri?: ErrorUri
}>()

const controller = reactive(new BlockController(props.block, props.context, props.caller, props.errorUri))
const component = computed(() => controller.component)
const label = computed(() => String(controller.eval(component.value.label) ?? ''))
const icon = computed(() => {
  const url = controller.eval(component.value.icon)
  return typeof url === 'string' && url.startsWith('https://') ? url : undefined
})
const error = computed(() => (controller.error == null ? undefined : String(controller.error)))

onMounted(() => controller.mount())
onUnmounted(() => controller.dispose())
</script>

<template>
  <button v-if="component.type === 'button'" type="button" :disabled="controller.busy" @click="controller.activate()">
    <span v-if="controller.busy" role="progressbar" />
    <img v-else-if="icon" :src="icon" alt="" width="40" height="40" />
    <span>{{ label }}</span>
    <small v-if="error">{{ error }}</small>
  </button>
  <div v-else-if="component.type === 'text'">
    <span v-if="controller.busy" role="progressbar" />
    <small v-else-if="error">{{ error }}</small>
    <span v-else>{{ label }}</span>
  </div>
  <div v-else>Unsupported component {{ component.type }}</div>
</template>
