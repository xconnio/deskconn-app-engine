<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref } from 'vue'
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

const number = (key: string): number | undefined => {
  const value = controller.eval(component.value[key])
  return typeof value === 'number' ? value : undefined
}
const min = computed(() => number('min') ?? 0)
const max = computed(() => number('max') ?? 100)
// The value being dragged, held until its change call returns.
const dragging = ref<number>()
const sliderValue = computed(() => Math.min(Math.max(dragging.value ?? number('value') ?? min.value, min.value), max.value))

function onSliderChange(event: Event) {
  dragging.value = Number((event.target as HTMLInputElement).value)
  void controller.change(dragging.value).finally(() => (dragging.value = undefined))
}

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
  <label v-else-if="component.type === 'slider'">
    <span>{{ label }}</span>
    <output>{{ sliderValue }}</output>
    <input
      type="range"
      :min="min"
      :max="max"
      :step="number('step') ?? 'any'"
      :value="sliderValue"
      :disabled="controller.busy"
      @input="dragging = Number(($event.target as HTMLInputElement).value)"
      @change="onSliderChange"
    />
    <small v-if="error">{{ error }}</small>
  </label>
  <div v-else>Unsupported component {{ component.type }}</div>
</template>
