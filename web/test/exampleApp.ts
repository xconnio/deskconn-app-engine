/** A test app as deskconn-userd's manifest.get returns it, with the button and
 * toggle blocks filled in. */
export const exampleManifest = () => ({
  schema_version: '1',
  app: {
    id: 'example',
    name: 'Example',
    description: 'A test app with a button and a toggle',
    icon: 'https://example.com/icons/example.png',
  },
  api: { key_exchange: 'com.example.key.exchange' },
  entry_screen: 'home',
  screens: {
    home: {
      id: 'home',
      title: 'Example',
      layout: {
        type: 'grid',
        columns: 2,
        children: [
          {
            id: 'ping',
            visible: { bind: 'context.capabilities.ping' },
            block: {
              component: {
                type: 'button',
                label: 'Ping',
                icon: 'https://example.com/icons/ping.png',
                on_activate: { call: 'com.example.ping' },
              },
            },
          },
          {
            id: 'light',
            visible: { bind: 'context.capabilities.light' },
            block: {
              state: { on: false },
              on_mount: {
                call: 'com.example.light.ison',
                on_result: { set: { on: { bind: 'result' } } },
              },
              component: {
                type: 'button',
                label: { when: { bind: 'state.on' }, then: 'Turn off', else: 'Turn on' },
                icon: {
                  when: { bind: 'state.on' },
                  then: 'https://example.com/icons/light-on.png',
                  else: 'https://example.com/icons/light-off.png',
                },
                on_activate: {
                  call: 'com.example.light.toggle',
                  on_result: { set: { on: { bind: 'result' } } },
                },
              },
            },
          },
        ],
      },
    },
  },
})
