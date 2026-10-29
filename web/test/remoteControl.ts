/** The Remote Control app as deskconn-userd's manifest.get returns it, with the button and
 * toggle blocks filled in. */
export const remoteControlManifest = () => ({
  schema_version: '1',
  app: {
    id: 'remote-control',
    name: 'Remote Control',
    description: 'Lock your computer and control audio',
    icon: 'https://example.com/icons/remote-control.png',
  },
  api: { key_exchange: 'io.xconn.deskconn.deskconnd.remotecontrol.key.exchange' },
  entry_screen: 'home',
  screens: {
    home: {
      id: 'home',
      title: 'Remote Control',
      layout: {
        type: 'grid',
        columns: 2,
        children: [
          {
            id: 'lock',
            visible: { bind: 'context.capabilities.screen' },
            block: {
              component: {
                type: 'button',
                label: 'Lock screen',
                icon: 'https://example.com/icons/lock.png',
                on_activate: { call: 'io.xconn.deskconn.deskconnd.screen.lock' },
              },
            },
          },
          {
            id: 'mute',
            visible: { bind: 'context.capabilities.audio' },
            block: {
              state: { on: false },
              on_mount: {
                call: 'io.xconn.deskconn.deskconnd.audio.ismuted',
                on_result: { set: { on: { bind: 'result' } } },
              },
              component: {
                type: 'button',
                label: { when: { bind: 'state.on' }, then: 'Unmute', else: 'Mute' },
                icon: {
                  when: { bind: 'state.on' },
                  then: 'https://example.com/icons/volume-off.png',
                  else: 'https://example.com/icons/volume-on.png',
                },
                on_activate: {
                  call: 'io.xconn.deskconn.deskconnd.audio.togglemute',
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
