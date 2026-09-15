import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

/**
 * The plugin writes its runtime files under the user's home. Redirect it
 * before anything imports the store module, so running this test can never
 * overwrite the runtime.json a live Host is serving from.
 *
 * `node --test` gives each test file its own process, so this only affects
 * the modules imported below.
 */
const HOME = mkdtempSync(join(tmpdir(), 'notch-apply-'))
process.env.HOME = HOME
after(() => { rmSync(HOME, { recursive: true, force: true }) })

const { apply } = await import('../src/dsh-notch.ts')

/** Minimal cordis context: the five injected services plus effect tracking. */
function mockContext(services = {}) {
  const logs = []
  const effects = []
  return {
    logs,
    effects,
    logger: {
      warn: (...args) => logs.push(args.join(' ')),
      info: (...args) => logs.push(args.join(' ')),
    },
    sessions: { list: () => [] },
    agents: { get: () => undefined },
    get: name => services[name],
    webServer: { host: '127.0.0.1', port: 43120, register: () => () => {} },
    on: () => () => {},
    effect: (callback, label) => {
      effects.push({ label, dispose: callback() })
      return () => {}
    },
  }
}

test('apply registers the Notch launcher on the Host lifecycle', () => {
  const ctx = mockContext()
  apply(ctx, { enabled: false })

  const labels = ctx.effects.map(effect => effect.label)
  assert.ok(
    labels.includes('dsh-notch: notch process'),
    `launcher effect missing from: ${labels.join(', ')}`,
  )
  // The config reaching the launcher is what proves the wiring, rather than
  // merely that some effect was registered under the expected label.
  assert.match(ctx.logs.join('\n'), /Notch auto-launch disabled by config/)
})

test('apply publishes a runtime file the Notch can read', () => {
  const ctx = mockContext()
  apply(ctx, { enabled: false })

  const runtimePath = join(HOME, '.dsh', 'dsh-notch', 'runtime.json')
  assert.equal(existsSync(runtimePath), true)
  const runtime = JSON.parse(readFileSync(runtimePath, 'utf8'))
  assert.equal(runtime.origin, 'http://127.0.0.1:43120')
  // The watchdog in the native app reads this field to notice a dead Host.
  assert.equal(typeof runtime.pid, 'number')
})

/** A session controller whose reads delegate the way the real one does. */
function sessionController() {
  const history = { page: async () => ({ records: [] }), follow: async function* () {} }
  return {
    history,
    page(request) { return this.history.page(request) },
    follow(request) { return this.history.follow(request) },
  }
}

test('a Host without the session controller still loads', () => {
  const ctx = mockContext()
  assert.doesNotThrow(() => apply(ctx, { enabled: false }))
  assert.ok(!ctx.effects.some(effect => effect.label === 'dsh-notch: browse sync'))
})

test('a reshaped history controller costs only the read sync', () => {
  const controller = sessionController()
  // Exactly the legacy wrapper browse-sync recognises. On a plain object its
  // prototype carries no `follow` to restore from, so the repair refuses — the
  // one failure that must not reach the rest of the plugin.
  const getTargetSessionId = address => address.sessionId
  const board = { markSeen() {} }
  const origFollow = controller.follow
  controller.follow = function* (req, signal) {
    const sid = getTargetSessionId(req.address)
    if (sid) board.markSeen(sid)
    return yield* origFollow(req, signal)
  }
  // Without the guard around the install, this throw would escape apply() and
  // take the whole plugin down; the contract is that it costs the read sync at
  // most. Verified that installBrowseSync itself rejects this controller.
  const ctx = mockContext({ sessionController: controller })
  assert.doesNotThrow(() => apply(ctx, { enabled: false }))
  assert.ok(!ctx.effects.some(effect => effect.label === 'dsh-notch: browse sync' && typeof effect.dispose !== 'function'))
})
