import { beforeEach, describe, expect, test } from 'vitest'
import { BlockController, ManifestApp, evaluate, isVisible } from '../src'
import { CallError, FakeCaller } from './fakeCaller'
import { remoteControlManifest } from './remoteControl'

const isMuted = 'io.xconn.deskconn.deskconnd.audio.ismuted'
const toggleMute = 'io.xconn.deskconn.deskconnd.audio.togglemute'

describe('runtime', () => {
  const app = new ManifestApp(remoteControlManifest())
  const block = (id: string) => app.entryScreen!.layout.children.find((c: any) => c.id === id).block

  let caller: FakeCaller
  const controller = (id: string) => new BlockController(block(id), {}, caller.call)

  beforeEach(() => {
    caller = new FakeCaller()
  })

  test('reads the app', () => {
    expect(app.id).toBe('remote-control')
    expect(app.name).toBe('Remote Control')
    expect(app.keyExchange).toBe('io.xconn.deskconn.deskconnd.remotecontrol.key.exchange')
    expect(app.entryScreen!.title).toBe('Remote Control')
  })

  test('bindings, conditionals and visibility', () => {
    const scope = { state: { muted: true } }
    expect(evaluate({ bind: 'state.muted' }, scope)).toBe(true)
    expect(evaluate({ bind: 'state.missing.deeper' }, scope)).toBeUndefined()
    expect(evaluate({ when: { bind: 'state.muted' }, then: 'a', else: 'b' }, scope)).toBe('a')
    expect(evaluate({ when: { bind: 'state.missing' }, then: 'a', else: 'b' }, scope)).toBe('b')
    expect(evaluate('literal', scope)).toBe('literal')

    const context = { capabilities: { screen: true, audio: false } }
    expect(isVisible(undefined, context)).toBe(true)
    expect(isVisible({ bind: 'context.capabilities.screen' }, context)).toBe(true)
    expect(isVisible({ bind: 'context.capabilities.audio' }, context)).toBe(false)
    expect(isVisible({ bind: 'context.capabilities.printer' }, context)).toBe(false)
  })

  test('mute loads its state, then toggles', async () => {
    const mute = controller('mute')
    expect(mute.eval(mute.component.label)).toBe('Mute')

    void mute.mount()
    expect(mute.busy).toBe(true)
    expect(caller.calls.map((c) => c.procedure)).toEqual([isMuted])
    await caller.respond(isMuted, { result: false })
    expect(mute.busy).toBe(false)
    expect(mute.eval(mute.component.label)).toBe('Mute')
    expect(mute.eval(mute.component.icon)).toBe('https://example.com/icons/volume-on.png')

    void mute.activate()
    expect(mute.busy).toBe(true)
    // Pressing again while the call is in flight does nothing.
    await mute.activate()
    expect(caller.calls.filter((c) => c.procedure === toggleMute)).toHaveLength(1)
    await caller.respond(toggleMute, { result: true })
    expect(mute.state.on).toBe(true)
    expect(mute.eval(mute.component.label)).toBe('Unmute')
    expect(mute.eval(mute.component.icon)).toBe('https://example.com/icons/volume-off.png')
  })

  test('a failed call keeps the state and shows the error', async () => {
    const mute = controller('mute')
    void mute.mount()
    await caller.respond(isMuted, { result: true })

    void mute.activate()
    await caller.respond(toggleMute, { error: new CallError('wamp.error.operation_failed') })
    expect(mute.busy).toBe(false)
    expect(mute.state.on).toBe(true)
    expect(mute.error).toBeInstanceOf(CallError)
  })

  test('on_error gets the error uri', async () => {
    const b = new BlockController(
      {
        state: { failure: null },
        on_mount: { call: isMuted, on_error: { set: { failure: { bind: 'error.uri' } } } },
        component: { type: 'button', label: 'x' },
      },
      {},
      caller.call,
      (e) => (e as CallError).uri,
    )
    void b.mount()
    await caller.respond(isMuted, { error: new CallError('wamp.error.no_such_procedure') })
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
        on_mount: { call: 'io.xconn.deskconn.deskconnd.hostname', on_result: { set: { value: { bind: 'result' } } } },
        component: { type: 'text', label: { bind: 'state.value' } },
      },
      {},
      caller.call,
    )
    void host.mount()
    await caller.respond('io.xconn.deskconn.deskconnd.hostname', { result: 'office-pc' })
    expect(host.eval(host.component.label)).toBe('office-pc')
  })

  test('ignores responses after unmount', async () => {
    const mute = controller('mute')
    void mute.mount()
    mute.dispose()
    await caller.respond(isMuted, { result: true })
    expect(mute.state.on).toBe(false)
  })
})
