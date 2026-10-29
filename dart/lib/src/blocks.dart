// app-engine's predefined blocks, the same as the repository's blocks/ (blocks_test.dart
// checks they match): packages can't ship files outside their directory.

/// Each predefined block's YAML by name, as apps include it: `app-engine/blocks/<name>.yaml`.
const predefinedBlocks = <String, String>{
  'button': r'''
# Calls a procedure when activated.
# Fields: label, icon (optional), call, arg (optional).
component:
  type: button
  label: { param: label }
  icon: { param: icon }
  on_activate:
    call: { param: call }
    arg: { param: arg }
''',
  'text': r'''
# Shows a label, or the result of a procedure once it returns.
# Fields: label (optional), read (optional).
state:
  value: { param: label }

on_mount:
  call: { param: read }
  on_result:
    set:
      value: { bind: result }

component:
  type: text
  label: { bind: state.value }
''',
  'toggle': r'''
# Reads whether something is on and flips it when activated.
# Fields: label (on, off), icon (on, off; optional), read, toggle.
# read and toggle return whether it is on.
state:
  on: false

on_mount:
  call: { param: read }
  on_result:
    set:
      on: { bind: result }

component:
  type: button
  label:
    when: { bind: state.on }
    then: { param: label.on }
    else: { param: label.off }
  icon:
    when: { bind: state.on }
    then: { param: icon.on }
    else: { param: icon.off }
  on_activate:
    call: { param: toggle }
    on_result:
      set:
        on: { bind: result }
''',
};
