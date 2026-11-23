import { mount } from '@vue/test-utils'
import { describe, expect, test, vi } from 'vitest'
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

  test('buttons with confirm call only once confirmed', async () => {
    const caller = new FakeCaller()
    const shutdown = 'io.xconn.deskconn.deskconnd.power.shutdown'
    const block = mount(ManifestBlock, {
      props: {
        block: {
          component: {
            type: 'button',
            label: 'Shut down',
            confirm: 'Shut down the desktop?',
            on_activate: { call: shutdown },
          },
        },
        context: {},
        caller: caller.call,
      },
    })

    await block.find('button').trigger('click')
    expect(block.find('[role=alertdialog]').text()).toContain('Shut down the desktop?')
    const cancel = block.findAll('[role=alertdialog] button').find((b) => b.text() === 'Cancel')!
    await cancel.trigger('click')
    expect(block.find('[role=alertdialog]').exists()).toBe(false)
    expect(caller.calls).toHaveLength(0)

    await block.find('button').trigger('click')
    const confirm = block.findAll('[role=alertdialog] button').find((b) => b.text() === 'Shut down')!
    await confirm.trigger('click')
    expect(caller.calls[0].procedure).toBe(shutdown)
  })

  test('polls read again every few seconds without showing loading', async () => {
    vi.useFakeTimers()
    try {
      const caller = new FakeCaller()
      const read = 'io.xconn.deskconn.deskconnd.cpu.usage'
      const block = mount(ManifestBlock, {
        props: {
          block: {
            state: { value: 'CPU' },
            on_mount: { call: read, on_result: { set: { value: { bind: 'result' } } } },
            refresh: 5,
            component: { type: 'text', label: { bind: 'state.value' } },
          },
          context: {},
          caller: caller.call,
        },
      })
      await nextTick()
      expect(block.find('[role=progressbar]').exists()).toBe(true)
      await caller.respond(read, { result: '12%' })
      expect(block.text()).toBe('12%')

      await vi.advanceTimersByTimeAsync(5000)
      expect(caller.calls).toHaveLength(2)
      // The last value shows while it reads again.
      expect(block.find('[role=progressbar]').exists()).toBe(false)
      expect(block.text()).toBe('12%')
      await caller.respond(read, { result: '30%' })
      expect(block.text()).toBe('30%')

      // It stops reading once removed.
      block.unmount()
      await vi.advanceTimersByTimeAsync(10000)
      expect(caller.calls).toHaveLength(2)
    } finally {
      vi.useRealTimers()
    }
  })

  test('sliders show their value and set where they are dropped', async () => {
    const caller = new FakeCaller()
    const set = 'io.xconn.deskconn.deskconnd.audio.setvolume'
    const block = mount(ManifestBlock, {
      props: {
        block: {
          state: { value: 20 },
          component: {
            type: 'slider',
            label: 'Volume',
            step: 10,
            value: { bind: 'state.value' },
            on_change: { call: set, arg: { bind: 'value' }, on_result: { set: { value: { bind: 'result' } } } },
          },
        },
        context: {},
        caller: caller.call,
      },
    })
    expect(block.text()).toContain('Volume')
    expect(block.find('output').text()).toBe('20')

    const slider = block.find('input[type=range]')
    await slider.setValue('50')
    expect(caller.calls[0].procedure).toBe(set)
    expect(caller.calls[0].arg).toBe(50)
    // The dropped value shows while the call is in flight.
    expect(block.find('output').text()).toBe('50')

    await caller.respond(set, { result: 40 })
    expect(block.find('output').text()).toBe('40')
  })

  test('selects show their choice and set what is picked', async () => {
    const caller = new FakeCaller()
    const set = 'io.xconn.deskconn.deskconnd.power.setmode'
    const block = mount(ManifestBlock, {
      props: {
        block: {
          state: { value: 'balanced' },
          component: {
            type: 'select',
            label: 'Power mode',
            options: [
              { value: 'saver', label: 'Power saver' },
              { value: 'balanced', label: 'Balanced' },
              { value: 'performance', label: 'Performance' },
            ],
            value: { bind: 'state.value' },
            on_change: { call: set, arg: { bind: 'value' }, on_result: { set: { value: { bind: 'result' } } } },
          },
        },
        context: {},
        caller: caller.call,
      },
    })
    const select = block.find('select')
    const chosen = () => (select.element as HTMLSelectElement).selectedOptions[0].text
    expect(block.text()).toContain('Power mode')
    expect(chosen()).toBe('Balanced')

    await select.setValue('2')
    expect(caller.calls[0].procedure).toBe(set)
    expect(caller.calls[0].arg).toBe('performance')
    // The picked choice shows while the call is in flight.
    expect(chosen()).toBe('Performance')

    await caller.respond(set, { result: 'saver' })
    expect(chosen()).toBe('Power saver')
  })
})
