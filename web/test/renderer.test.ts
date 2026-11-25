import { flushPromises, mount } from '@vue/test-utils'
import { describe, expect, test, vi } from 'vitest'
import { nextTick } from 'vue'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { ManifestApp, ManifestBlock, ManifestScreen, manifestIcons } from '../src'
import { FakeCaller } from './fakeCaller'
import { exampleManifest } from './exampleApp'

describe('renderer', () => {
  const app = new ManifestApp(exampleManifest())
  const render = (caller: FakeCaller, capabilities: Record<string, boolean>) =>
    mount(ManifestScreen, { props: { screen: app.entryScreen!, context: { capabilities }, caller: caller.call } })

  test('hidden blocks neither show nor call', () => {
    const caller = new FakeCaller()
    const screen = render(caller, { ping: true, light: false })

    expect(screen.text()).toContain('Ping')
    expect(screen.text()).not.toContain('Turn on')
    expect(caller.calls).toHaveLength(0)
  })

  test('buttons call their procedures and show their state', async () => {
    const caller = new FakeCaller()
    const screen = render(caller, { ping: true, light: true })

    await nextTick()
    expect(screen.find('[role=progressbar]').exists()).toBe(true)
    await caller.respond('com.example.light.ison', { result: false })
    expect(screen.find('[role=progressbar]').exists()).toBe(false)
    const [ping, light] = screen.findAll('button')
    expect(light.text()).toBe('Turn on')

    await light.trigger('click')
    await caller.respond('com.example.light.toggle', { result: true })
    expect(light.text()).toBe('Turn off')

    await ping.trigger('click')
    expect(caller.calls.at(-1)!.procedure).toBe('com.example.ping')
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
    const shutdown = 'com.example.power.shutdown'
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
      const read = 'com.example.cpu.usage'
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
    const set = 'com.example.level.set'
    const block = mount(ManifestBlock, {
      props: {
        block: {
          state: { value: 20 },
          component: {
            type: 'slider',
            label: 'Level',
            step: 10,
            value: { bind: 'state.value' },
            on_change: { call: set, arg: { bind: 'value' }, on_result: { set: { value: { bind: 'result' } } } },
          },
        },
        context: {},
        caller: caller.call,
      },
    })
    expect(block.text()).toContain('Level')
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
    const set = 'com.example.power.setmode'
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

  test('buttons show named icons, the app\'s own icon files from the desktop, or https icons', async () => {
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47])
    const loaded: string[] = []
    const loadFile = async (path: string) => {
      loaded.push(path)
      if (path !== 'icons/ping.png') throw new Error(`no file ${path}`)
      return png
    }
    const src = async (icon: string) => {
      const block = mount(ManifestBlock, {
        props: {
          block: { component: { type: 'button', label: 'Ping', icon } },
          context: {},
          caller: new FakeCaller().call,
          loadFile,
        },
      })
      await flushPromises()
      const img = block.find('img')
      return img.exists() ? img.attributes('src') : undefined
    }

    const named = mount(ManifestBlock, {
      props: {
        block: { component: { type: 'button', label: 'Star', icon: 'star' } },
        context: {},
        caller: new FakeCaller().call,
        loadFile,
      },
    })
    expect(named.findAll('svg path').map((path) => path.attributes('d'))).toEqual(manifestIcons.star)
    expect(named.find('img').exists()).toBe(false)
    expect(loaded).toEqual([])

    expect(await src('icons/ping.png')).toMatch(/^blob:/)
    expect(loaded).toEqual(['icons/ping.png'])
    expect(await src('https://example.com/ping.png')).toBe('https://example.com/ping.png')

    loaded.length = 0
    for (const icon of ['icons/missing.png', 'http://example.com/ping.png', 'javascript:alert(1)', 'icons/ping.svg']) {
      expect(await src(icon), icon).toBeUndefined()
    }
    expect(loaded).toEqual(['icons/missing.png'])
  })

  test('named icons are exactly icons/names.txt', () => {
    const names = readFileSync(resolve(__dirname, '../../icons/names.txt'), 'utf8')
      .split('\n')
      .filter((line) => !line.startsWith('#'))
      .flatMap((line) => line.split(' '))
      .filter(Boolean)
    expect(Object.keys(manifestIcons)).toEqual(names)
  })
})
