<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'
import { manifestIcons } from '../icons'
import { BlockController, type ErrorUri, type ManifestCaller, type ManifestFileLoader } from '../runtime'

// A mounted block. It mounts when created and unmounts when removed.
const props = defineProps<{
  block: Record<string, any>
  context: Record<string, unknown>
  caller: ManifestCaller
  errorUri?: ErrorUri
  /** Loads the app's own icon files; without it, only https icons show. */
  loadFile?: ManifestFileLoader
}>()

const controller = reactive(new BlockController(props.block, props.context, props.caller, props.errorUri))
const component = computed(() => controller.component)
const label = computed(() => String(controller.eval(component.value.label) ?? ''))
// An icon is a name from manifestIcons, such as play_arrow; an https URL; or one of the app's
// own PNG files, by its path from the app's directory, loaded from the desktop with loadFile.
// Anything else shows none.
const iconValue = computed(() => {
  const value = controller.eval(component.value.icon)
  return typeof value === 'string' ? value : undefined
})
// The app file shown, and an object URL of its image once loaded.
let iconFile: string | undefined
const iconFileUrl = ref<string>()
function showIconFile(url: string | undefined) {
  if (iconFileUrl.value) URL.revokeObjectURL(iconFileUrl.value)
  iconFileUrl.value = url
}
watch(
  iconValue,
  async (value) => {
    const isFile = value != null && !value.includes('://') && value.endsWith('.png')
    if (!isFile || !props.loadFile) {
      iconFile = undefined
      return showIconFile(undefined)
    }
    if (value === iconFile) return
    iconFile = value
    showIconFile(undefined)
    const data = await props.loadFile(value).catch(() => undefined)
    if (data && iconFile === value) showIconFile(URL.createObjectURL(new Blob([data as BlobPart], { type: 'image/png' })))
  },
  { immediate: true },
)
const namedIcon = computed(() => (iconValue.value == null ? undefined : manifestIcons[iconValue.value]))
const icon = computed(() => (iconValue.value?.startsWith('https://') ? iconValue.value : iconFileUrl.value))
const question = computed(() => {
  const value = controller.eval(component.value.confirm)
  return value == null ? undefined : String(value)
})
// Whether a button with confirm is asking its question.
const confirming = ref(false)
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

const options = computed(() => {
  const list = controller.eval(component.value.options)
  return (Array.isArray(list) ? list : [])
    .filter((option): option is Record<string, unknown> => typeof option === 'object' && option !== null)
    .map((option) => ({ value: option.value, label: String(option.label ?? option.value ?? '') }))
})
// The index picked, held until its change call returns.
const picking = ref<number>()
const selected = computed(
  () => picking.value ?? options.value.findIndex((option) => option.value === controller.eval(component.value.value)),
)

function onSelectChange(event: Event) {
  const index = Number((event.target as HTMLSelectElement).value)
  const option = options.value[index]
  if (!option) return
  picking.value = index
  void controller.change(option.value).finally(() => (picking.value = undefined))
}

function onActivate() {
  if (question.value == null) void controller.activate()
  else confirming.value = true
}

function onConfirm() {
  confirming.value = false
  void controller.activate()
}

onMounted(() => controller.mount())
onUnmounted(() => {
  controller.dispose()
  showIconFile(undefined)
})
</script>

<template>
  <div v-if="component.type === 'button' && confirming" role="alertdialog">
    <span>{{ question }}</span>
    <button type="button" @click="confirming = false">Cancel</button>
    <button type="button" @click="onConfirm">{{ label }}</button>
  </div>
  <button v-else-if="component.type === 'button'" type="button" :disabled="controller.busy" @click="onActivate">
    <span v-if="controller.busy" role="progressbar" />
    <svg v-else-if="namedIcon" viewBox="0 0 24 24" width="40" height="40" fill="currentColor" aria-hidden="true">
      <path v-for="(d, i) in namedIcon" :key="i" :d="d" />
    </svg>
    <img v-else-if="icon" :src="icon" alt="" width="40" height="40" />
    <span>{{ label }}</span>
    <small v-if="error">{{ error }}</small>
  </button>
  <div v-else-if="component.type === 'text'">
    <span v-if="controller.busy && !controller.loaded" role="progressbar" />
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
  <label v-else-if="component.type === 'select'">
    <span>{{ label }}</span>
    <select :value="selected" :disabled="controller.busy" @change="onSelectChange">
      <option v-if="selected < 0" :value="-1" disabled />
      <option v-for="(option, i) in options" :key="i" :value="i">{{ option.label }}</option>
    </select>
    <small v-if="error">{{ error }}</small>
  </label>
  <div v-else>Unsupported component {{ component.type }}</div>
</template>
