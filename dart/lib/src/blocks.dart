// app-engine's predefined blocks, the same as the repository's blocks/ (blocks_test.dart
// checks they match): packages can't ship files outside their directory.

/// Each predefined block's YAML by name, as apps include it: `app-engine/blocks/<name>.yaml`.
const predefinedBlocks = <String, String>{
  'button': r'''
# Calls a procedure when activated.
# Fields: label, icon (optional: a Material icon name from icons/names.txt, a PNG file in the app, or an https URL), call, arg (optional).
component:
  type: button
  label: { param: label }
  icon: { param: icon }
  on_activate:
    call: { param: call }
    arg: { param: arg }
''',
  'confirm': r'''
# Calls a procedure when activated, once the user confirms, e.g. shut down or log out.
# Fields: label, icon (optional: a Material icon name from icons/names.txt, a PNG file in the app, or an https URL), confirm (the question to confirm), call, arg (optional).
component:
  type: button
  label: { param: label }
  icon: { param: icon }
  confirm: { param: confirm }
  on_activate:
    call: { param: call }
    arg: { param: arg }
''',
  'poll': r'''
# Shows the result of a procedure and reads it again every few seconds, e.g. CPU or battery.
# Fields: label (optional, shown until the first read), read, every (seconds).
state:
  value: { param: label }

on_mount:
  call: { param: read }
  on_result:
    set:
      value: { bind: result }

refresh: { param: every }

component:
  type: text
  label: { bind: state.value }
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
# Fields: label (on, off), icon (on, off; optional: Material icon names from icons/names.txt, PNG files in the app, or https URLs), read, toggle.
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
  'select': r'''
# Reads a choice and sets it when another is picked, e.g. audio output or power mode.
# Fields: label, options (a list of value and label), read, set.
# read and set return the chosen value.
state:
  value: null

on_mount:
  call: { param: read }
  on_result:
    set:
      value: { bind: result }

component:
  type: select
  label: { param: label }
  options: { param: options }
  value: { bind: state.value }
  on_change:
    call: { param: set }
    arg: { bind: value }
    on_result:
      set:
        value: { bind: result }
''',
  'slider': r'''
# Reads a value and sets it when dragged, e.g. volume or brightness.
# Fields: label, min (optional, 0), max (optional, 100), step (optional), read, set.
# read and set return the value.
state:
  value: null

on_mount:
  call: { param: read }
  on_result:
    set:
      value: { bind: result }

component:
  type: slider
  label: { param: label }
  min: { param: min }
  max: { param: max }
  step: { param: step }
  value: { bind: state.value }
  on_change:
    call: { param: set }
    arg: { bind: value }
    on_result:
      set:
        value: { bind: result }
''',
};
