import { parse } from 'yaml'

import { predefinedBlocks } from './blocks'

/** Calls `procedure` on the desktop with an optional `arg` and returns its decoded result. */
export type ManifestCaller = (procedure: string, arg?: unknown) => Promise<unknown>

/** Returns the error URI of a failed call, which `on_error` reads as `error.uri`. */
export type ErrorUri = (error: unknown) => string

type Scope = Record<string, unknown>
type Json = Record<string, any>

const isMap = (value: unknown): value is Json => typeof value === 'object' && value !== null && !Array.isArray(value)

/** A manifest app as deskconn-userd's manifest.get returns it: app.yaml with its screens
 * resolved to a map by id, and each include of the app's own files replaced by the included
 * block under `block`. Includes of app-engine's blocks are expanded here (see expandBlocks). */
export class ManifestApp {
  readonly data: Json

  constructor(data: Json) {
    this.data = expandBlocks(data)
  }

  private get app(): Json {
    return isMap(this.data.app) ? this.data.app : {}
  }

  get id(): string {
    return this.app.id?.toString() ?? ''
  }

  get name(): string {
    return this.app.name?.toString() ?? this.id
  }

  get keyExchange(): string {
    return this.data.api?.key_exchange?.toString() ?? ''
  }

  screen(id: string): Json | undefined {
    return this.data.screens?.[id]
  }

  get entryScreen(): Json | undefined {
    return this.screen(this.data.entry_screen?.toString() ?? '')
  }
}

const blocksDirectory = 'app-engine/blocks/'

/** Returns `app` with each `include: app-engine/blocks/<name>.yaml` replaced by that block
 * under `block`, filled in from the including map's other fields: each `{param: <field>}` in
 * the block takes the field's value at that dotted path, and is left out where it isn't set.
 * The including map keeps only its `id` and `visible`. Unknown blocks are left as they are,
 * for the renderer to show as unsupported. */
export function expandBlocks(app: Json): Json {
  const copy = structuredClone(app)
  expand(copy)
  return copy
}

function expand(node: unknown): void {
  if (Array.isArray(node)) {
    node.forEach(expand)
    return
  }
  if (!isMap(node)) return

  const include = node.include
  const name =
    typeof include === 'string' && include.startsWith(blocksDirectory)
      ? include.slice(blocksDirectory.length).replace(/\.yaml$/, '')
      : undefined
  const template = name === undefined ? undefined : predefinedBlocks[name]
  if (template !== undefined) {
    const fields: Json = {}
    for (const [key, value] of Object.entries(node)) {
      if (key === 'id' || key === 'visible') continue
      if (key !== 'include') fields[key] = value
      delete node[key]
    }
    node.block = fill(parse(template), fields).value
    return
  }
  Object.values(node).forEach(expand)
}

/** Fills `node`'s `{param: <field>}`s from `fields`, returning whether to keep it. */
function fill(node: unknown, fields: Json): { value: unknown; keep: boolean } {
  if (isMap(node)) {
    const field = node.param
    if (Object.keys(node).length === 1 && typeof field === 'string') {
      let value: unknown = fields
      for (const part of field.split('.')) {
        if (!isMap(value) || !(part in value)) return { value: undefined, keep: false }
        value = value[part]
      }
      return { value, keep: true }
    }
    for (const key of Object.keys(node)) {
      const filled = fill(node[key], fields)
      if (filled.keep) node[key] = filled.value
      else delete node[key]
    }
  } else if (Array.isArray(node)) {
    node.forEach((child, i) => {
      node[i] = fill(child, fields).value
    })
  }
  return { value: node, keep: true }
}

/** Reads a dotted `path` such as `state.muted` from `scope`. Missing paths read undefined. */
export function readPath(scope: Scope, path: string): unknown {
  let node: unknown = scope
  for (const part of path.split('.')) {
    if (!isMap(node)) return undefined
    node = node[part]
  }
  return node
}

/** Evaluates a manifest value: `{bind: path}` reads `scope`, `{when, then, else}` picks a
 * branch (anything but true selects else), and anything else is a literal. */
export function evaluate(value: unknown, scope: Scope): unknown {
  if (isMap(value)) {
    if ('bind' in value) return readPath(scope, String(value.bind))
    if ('when' in value) return evaluate(evaluate(value.when, scope) === true ? value.then : value.else, scope)
  }
  return value
}

/** Whether a child with `visible` shows, given the renderer's `context`. */
export function isVisible(visible: unknown, context: Scope): boolean {
  return visible === undefined || visible === null || evaluate(visible, { context }) === true
}

/** A mounted block: its state, and the actions of its `on_mount` and component. Wrap it in
 * Vue's `reactive` to render it. */
export class BlockController {
  readonly state: Json

  /** Whether a call is in flight. The renderer shows loading and disables the block. */
  busy = false

  /** The last failed call that had no on_error, shown by the renderer. */
  error: unknown = null

  private disposed = false

  constructor(
    private readonly block: Json,
    readonly context: Scope,
    private readonly caller: ManifestCaller,
    private readonly errorUri: ErrorUri = (error) => String(error),
  ) {
    this.state = { ...(isMap(block.state) ? block.state : {}) }
  }

  get component(): Json {
    return isMap(this.block.component) ? this.block.component : {}
  }

  private get scope(): Scope {
    return { state: this.state, context: this.context }
  }

  /** Evaluates `value` against the block's state and context. */
  eval(value: unknown): unknown {
    return evaluate(value, this.scope)
  }

  /** Runs `on_mount`, if any. */
  mount(): Promise<void> {
    return this.run(this.block.on_mount, this.scope)
  }

  /** Runs the component's `on_activate`, unless a call is already in flight. */
  async activate(): Promise<void> {
    if (this.busy) return
    await this.run(this.component.on_activate, this.scope)
  }

  dispose(): void {
    this.disposed = true
  }

  private async run(action: unknown, scope: Scope): Promise<void> {
    if (!isMap(action) || this.disposed) return

    if (isMap(action.set)) {
      for (const [key, value] of Object.entries(action.set)) this.state[key] = evaluate(value, scope)
    }

    const procedure = action.call
    if (typeof procedure !== 'string') return

    this.busy = true
    this.error = null
    try {
      const result = await this.caller(procedure, 'arg' in action ? evaluate(action.arg, scope) : undefined)
      if (this.disposed) return
      this.busy = false
      await this.run(action.on_result, { ...scope, result })
    } catch (e) {
      if (this.disposed) return
      this.busy = false
      if (isMap(action.on_error)) {
        await this.run(action.on_error, { ...scope, error: { uri: this.errorUri(e) } })
      } else {
        this.error = e
      }
    }
  }
}
