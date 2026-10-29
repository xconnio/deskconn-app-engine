<script setup lang="ts">
import { computed } from 'vue'
import { isVisible, type ErrorUri, type ManifestCaller } from '../runtime'
import ManifestBlock from './ManifestBlock.vue'

// Renders a manifest app's screen: its layout, and a block for each visible child.
const props = defineProps<{
  screen: Record<string, any>
  /** What `context.*` bindings read, e.g. `capabilities`. */
  context: Record<string, unknown>
  caller: ManifestCaller
  errorUri?: ErrorUri
}>()

const layout = computed(() => props.screen.layout ?? {})
const columns = computed(() => Math.min(Math.max(Number(layout.value.columns) || 2, 1), 6))
const children = computed(() =>
  ((layout.value.children ?? []) as Record<string, any>[]).filter((child) => isVisible(child.visible, props.context)),
)
</script>

<template>
  <div
    v-if="layout.type === 'grid'"
    :style="{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: '12px', padding: '16px' }"
  >
    <!-- Keyed by id so a block keeps its state while others show or hide. -->
    <ManifestBlock
      v-for="child in children"
      :key="child.id"
      :block="child.block ?? {}"
      :context="context"
      :caller="caller"
      :error-uri="errorUri"
    />
  </div>
  <div v-else>Unsupported layout {{ layout.type }}</div>
</template>
