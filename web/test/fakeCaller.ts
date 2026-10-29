import { flushPromises } from '@vue/test-utils'

type Call = { procedure: string; arg: unknown; resolve: (result: unknown) => void; reject: (error: unknown) => void; done: boolean }

/** A caller whose calls stay pending until the test answers them. */
export class FakeCaller {
  readonly calls: Call[] = []

  call = (procedure: string, arg?: unknown): Promise<unknown> =>
    new Promise((resolve, reject) => this.calls.push({ procedure, arg, resolve, reject, done: false }))

  /** Answers the oldest unanswered call to `procedure` with `result`, or fails it with `error`,
   * then lets the caller handle the response. */
  async respond(procedure: string, { result, error }: { result?: unknown; error?: unknown } = {}): Promise<void> {
    const call = this.calls.find((c) => c.procedure === procedure && !c.done)
    if (!call) throw new Error(`no pending call to ${procedure}`)
    call.done = true
    error === undefined ? call.resolve(result) : call.reject(error)
    await flushPromises()
  }
}

/** A failed call, as a transport would report it. */
export class CallError extends Error {
  constructor(readonly uri: string) {
    super(uri)
  }
}
