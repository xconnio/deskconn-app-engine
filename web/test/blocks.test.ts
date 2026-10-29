import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, test } from 'vitest'
import { ManifestApp } from '../src'
import { predefinedBlocks } from '../src/blocks'
import { remoteControlManifest } from './remoteControl'

/** The Remote Control app as written, including app-engine's blocks. */
function remoteControlWithIncludes() {
  const app = remoteControlManifest()
  app.screens.home.layout.children = [
    {
      id: 'lock',
      visible: { bind: 'context.capabilities.screen' },
      include: 'app-engine/blocks/button.yaml',
      label: 'Lock screen',
      icon: 'https://example.com/icons/lock.png',
      call: 'io.xconn.deskconn.deskconnd.screen.lock',
    },
    {
      id: 'mute',
      visible: { bind: 'context.capabilities.audio' },
      include: 'app-engine/blocks/toggle.yaml',
      label: { on: 'Unmute', off: 'Mute' },
      icon: { on: 'https://example.com/icons/volume-off.png', off: 'https://example.com/icons/volume-on.png' },
      read: 'io.xconn.deskconn.deskconnd.audio.ismuted',
      toggle: 'io.xconn.deskconn.deskconnd.audio.togglemute',
    },
  ] as any
  return app
}

const children = (app: Record<string, any>) => app.screens.home.layout.children

describe('blocks', () => {
  test("the predefined blocks are the repository's", () => {
    // Tests run in web/.
    const directory = join(process.cwd(), '..', 'blocks')
    for (const [name, yaml] of Object.entries(predefinedBlocks)) {
      expect(yaml, name).toBe(readFileSync(join(directory, `${name}.yaml`), 'utf8'))
    }
    expect(readdirSync(directory)).toHaveLength(Object.keys(predefinedBlocks).length)
  })

  test('expands included blocks from their fields', () => {
    const app = new ManifestApp(remoteControlWithIncludes())
    expect(children(app.data)).toEqual(children(remoteControlManifest()))
  })

  test('leaves out unset fields', () => {
    const app = new ManifestApp({
      screens: {
        home: { layout: { children: [{ id: 'hello', include: 'app-engine/blocks/text.yaml', label: 'Hello, world!' }] } },
      },
    })
    expect(children(app.data)).toEqual([
      {
        id: 'hello',
        block: {
          state: { value: 'Hello, world!' },
          on_mount: { on_result: { set: { value: { bind: 'result' } } } },
          component: { type: 'text', label: { bind: 'state.value' } },
        },
      },
    ])
  })

  test("leaves unknown blocks and doesn't change its input", () => {
    const input = remoteControlWithIncludes()
    children(input)[0].include = 'app-engine/blocks/slider.yaml'
    const app = new ManifestApp(input)
    expect(children(app.data)[0].include).toBe('app-engine/blocks/slider.yaml')
    expect(children(app.data)[0]).not.toHaveProperty('block')
    expect(children(input)[1]).toHaveProperty('include')
  })
})
