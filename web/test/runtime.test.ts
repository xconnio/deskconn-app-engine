import { beforeEach, describe, expect, test } from 'vitest'
import { BlockController, ManifestApp, evaluate, isVisible } from '../src'
import { CallError, FakeCaller } from './fakeCaller'
import { exampleManifest } from './exampleApp'

const isOn = 'com.example.light.ison'
const toggleLight = 'com.example.light.toggle'

describe('runtime', () => {
  const app = new ManifestApp(exampleManifest())
  const block = (id: string) => app.entryScreen!.layout.children.find((c: any) => c.id === id).block

  let caller: FakeCaller
  const controller = (id: string) => new BlockController(block(id), {}, caller.call)

  beforeEach(() => {
    caller = new FakeCaller()
  })

  test('reads the app', () => {
    expect(app.id).toBe('example')
    expect(app.name).toBe('Example')
    expect(app.keyExchange).toBe('com.example.key.exchange')
    expect(app.entryScreen!.title).toBe('Example')
  })

  test('bindings, conditionals and visibility', () => {
    const scope = { state: { lit: true } }
    expect(evaluate({ bind: 'state.lit' }, scope)).toBe(true)
    expect(evaluate({ bind: 'state.missing.deeper' }, scope)).toBeUndefined()
    expect(evaluate({ when: { bind: 'state.lit' }, then: 'a', else: 'b' }, scope)).toBe('a')
    expect(evaluate({ when: { bind: 'state.missing' }, then: 'a', else: 'b' }, scope)).toBe('b')
    expect(evaluate('literal', scope)).toBe('literal')

    const context = { capabilities: { ping: true, light: false } }
    expect(isVisible(undefined, context)).toBe(true)
    expect(isVisible({ bind: 'context.capabilities.ping' }, context)).toBe(true)
    expect(isVisible({ bind: 'context.capabilities.light' }, context)).toBe(false)
    expect(isVisible({ bind: 'context.capabilities.printer' }, context)).toBe(false)
  })

  test('light loads its state, then toggles', async () => {
    const light = controller('light')
    expect(light.eval(light.component.label)).toBe('Turn on')

    void light.mount()
    expect(light.busy).toBe(true)
    expect(caller.calls.map((c) => c.procedure)).toEqual([isOn])
    await caller.respond(isOn, { result: false })
    expect(light.busy).toBe(false)
    expect(light.eval(light.component.label)).toBe('Turn on')
    expect(light.eval(light.component.icon)).toBe('https://example.com/icons/light-off.png')

    void light.activate()
    expect(light.busy).toBe(true)
    // Pressing again while the call is in flight does nothing.
    await light.activate()
    expect(caller.calls.filter((c) => c.procedure === toggleLight)).toHaveLength(1)
    await caller.respond(toggleLight, { result: true })
    expect(light.state.on).toBe(true)
    expect(light.eval(light.component.label)).toBe('Turn off')
    expect(light.eval(light.component.icon)).toBe('https://example.com/icons/light-on.png')
  })

  test('a failed call keeps the state and shows the error', async () => {
    const light = controller('light')
    void light.mount()
    await caller.respond(isOn, { result: true })

    void light.activate()
    await caller.respond(toggleLight, { error: new CallError('wamp.error.operation_failed') })
    expect(light.busy).toBe(false)
    expect(light.state.on).toBe(true)
    expect(light.error).toBeInstanceOf(CallError)
  })

  test('on_error gets the error uri', async () => {
    const b = new BlockController(
      {
        state: { failure: null },
        on_mount: { call: isOn, on_error: { set: { failure: { bind: 'error.uri' } } } },
        component: { type: 'button', label: 'x' },
      },
      {},
      caller.call,
      (e) => (e as CallError).uri,
    )
    void b.mount()
    await caller.respond(isOn, { error: new CallError('wamp.error.no_such_procedure') })
    expect(b.state.failure).toBe('wamp.error.no_such_procedure')
    expect(b.error).toBeNull()
  })

  test('a text block shows its label without calling', async () => {
    const hello = new BlockController(
      { state: { value: 'Hello, world!' }, component: { type: 'text', label: { bind: 'state.value' } } },
      {},
      caller.call,
    )
    await hello.mount()
    expect(hello.eval(hello.component.label)).toBe('Hello, world!')
    expect(caller.calls).toHaveLength(0)
  })

  test('a text block shows what it reads', async () => {
    const host = new BlockController(
      {
        state: { value: null },
        on_mount: { call: 'com.example.hostname', on_result: { set: { value: { bind: 'result' } } } },
        component: { type: 'text', label: { bind: 'state.value' } },
      },
      {},
      caller.call,
    )
    void host.mount()
    await caller.respond('com.example.hostname', { result: 'office-pc' })
    expect(host.eval(host.component.label)).toBe('office-pc')
  })

  test('a slider sets what it is changed to', async () => {
    const read = 'com.example.level.get'
    const set = 'com.example.level.set'
    const level = new BlockController(
      {
        state: { value: null },
        on_mount: { call: read, on_result: { set: { value: { bind: 'result' } } } },
        component: {
          type: 'slider',
          value: { bind: 'state.value' },
          on_change: { call: set, arg: { bind: 'value' }, on_result: { set: { value: { bind: 'result' } } } },
        },
      },
      {},
      caller.call,
    )
    void level.mount()
    await caller.respond(read, { result: 30 })
    expect(level.eval(level.component.value)).toBe(30)

    void level.change(55)
    expect(caller.calls.at(-1)!.procedure).toBe(set)
    expect(caller.calls.at(-1)!.arg).toBe(55)
    // Changing again while the call is in flight does nothing.
    await level.change(70)
    expect(caller.calls.filter((c) => c.procedure === set)).toHaveLength(1)
    await caller.respond(set, { result: 55 })
    expect(level.state.value).toBe(55)
  })

  test('ignores responses after unmount', async () => {
    const light = controller('light')
    void light.mount()
    light.dispose()
    await caller.respond(isOn, { result: true })
    expect(light.state.on).toBe(false)
  })
})
