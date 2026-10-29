import { mount } from '@vue/test-utils'
import { describe, expect, test } from 'vitest'
import { nextTick } from 'vue'
import { ManifestApp, ManifestBlock, ManifestScreen } from '../src'
import { FakeCaller } from './fakeCaller'
import { remoteControlManifest } from './remoteControl'

describe('renderer', () => {
  const app = new ManifestApp(remoteControlManifest())
  const render = (caller: FakeCaller, capabilities: Record<string, boolean>) =>
    mount(ManifestScreen, { props: { screen: app.entryScreen!, context: { capabilities }, caller: caller.call } })

  test('hidden blocks neither show nor call', () => {
    const caller = new FakeCaller()
    const screen = render(caller, { screen: true, audio: false })

    expect(screen.text()).toContain('Lock screen')
    expect(screen.text()).not.toContain('Mute')
    expect(caller.calls).toHaveLength(0)
  })

  test('buttons call their procedures and show their state', async () => {
    const caller = new FakeCaller()
    const screen = render(caller, { screen: true, audio: true })

    await nextTick()
    expect(screen.find('[role=progressbar]').exists()).toBe(true)
    await caller.respond('io.xconn.deskconn.deskconnd.audio.ismuted', { result: false })
    expect(screen.find('[role=progressbar]').exists()).toBe(false)
    const [lock, mute] = screen.findAll('button')
    expect(mute.text()).toBe('Mute')

    await mute.trigger('click')
    await caller.respond('io.xconn.deskconn.deskconnd.audio.togglemute', { result: true })
    expect(mute.text()).toBe('Unmute')

    await lock.trigger('click')
    expect(caller.calls.at(-1)!.procedure).toBe('io.xconn.deskconn.deskconnd.screen.lock')
  })

  test('text blocks show their label', () => {
    const block = mount(ManifestBlock, {
      props: {
        block: { state: { value: 'Hello, world!' }, component: { type: 'text', label: { bind: 'state.value' } } },
        context: {},
        caller: new FakeCaller().call,
      },
    })
    expect(block.text()).toBe('Hello, world!')
  })
})
