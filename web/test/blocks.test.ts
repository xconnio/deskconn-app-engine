import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, test } from 'vitest'
import { ManifestApp } from '../src'
import { predefinedBlocks } from '../src/blocks'
import { exampleManifest } from './exampleApp'

/** A test app as written, including app-engine's blocks. */
function exampleWithIncludes() {
  const app = exampleManifest()
  app.screens.home.layout.children = [
    {
      id: 'ping',
      visible: { bind: 'context.capabilities.ping' },
      include: 'app-engine/blocks/button.yaml',
      label: 'Ping',
      icon: 'https://example.com/icons/ping.png',
      call: 'com.example.ping',
    },
    {
      id: 'light',
      visible: { bind: 'context.capabilities.light' },
      include: 'app-engine/blocks/toggle.yaml',
      label: { on: 'Turn off', off: 'Turn on' },
      icon: { on: 'https://example.com/icons/light-on.png', off: 'https://example.com/icons/light-off.png' },
      read: 'com.example.light.ison',
      toggle: 'com.example.light.toggle',
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
    const app = new ManifestApp(exampleWithIncludes())
    expect(children(app.data)).toEqual(children(exampleManifest()))
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
    const input = exampleWithIncludes()
    children(input)[0].include = 'app-engine/blocks/unknown.yaml'
    const app = new ManifestApp(input)
    expect(children(app.data)[0].include).toBe('app-engine/blocks/unknown.yaml')
    expect(children(app.data)[0]).not.toHaveProperty('block')
    expect(children(input)[1]).toHaveProperty('include')
  })
})
