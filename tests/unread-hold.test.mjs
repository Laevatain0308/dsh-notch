import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import os from 'node:os'
import { mkdtempSync, rmSync } from 'node:fs'
import { syncBuiltinESMExports } from 'node:module'

const testDir = mkdtempSync(os.tmpdir() + '/notch-unread-')
const realHomedir = os.homedir
os.homedir = () => testDir
syncBuiltinESMExports()
const { Board } = await import('../src/board.ts')
os.homedir = realHomedir
syncBuiltinESMExports()
after(() => rmSync(testDir, { recursive: true, force: true }))

test('a single running task becomes a green unread lamp instead of vanishing', () => {
  let running = true
  const events = [{ type: 'turn/start', time: 1 }]
  const session = {
    id: 'session-one',
    header: {},
    snapshotEvents: () => events,
  }
  const ctx = {
    sessions: { list: () => [session] },
    agents: { get: () => ({ status: running ? 'running' : 'idle' }) },
    get: () => undefined,
    logger: { warn() {} },
  }
  const board = new Board(ctx)
  assert.equal(board.snapshot('').rows[0].busy, true)

  running = false
  events.push({ type: 'turn/end', time: 2, data: { reason: { kind: 'completed' } } })
  const done = board.snapshot('').rows[0]
  assert.equal(done.busy, false)
  assert.equal(done.unread, true)
  assert.equal(board.snapshot('').rows[0].unread, true)

  board.markSeen(session.id)
  assert.equal(board.snapshot('').rows.length, 0)
})

test('a completion marker stands until it is dismissed', () => {
  let running = true
  const events = [{ type: 'turn/start', time: 1 }]
  const session = {
    id: 'session-stands',
    header: {},
    snapshotEvents: () => events,
  }
  const ctx = {
    sessions: { list: () => [session] },
    agents: { get: () => ({ status: running ? 'running' : 'idle' }) },
    get: () => undefined,
    logger: { warn() {} },
  }
  const board = new Board(ctx)
  board.snapshot('')
  running = false
  events.push({ type: 'turn/end', time: 2, data: { reason: { kind: 'completed' } } })

  // Nothing outside the plugin feeds this: the completion is its own
  // observation, and it stays lit across as many polls as it takes.
  assert.equal(board.snapshot('').rows[0].unread, true)
  assert.equal(board.snapshot('').rows[0].unread, true)

  board.markSeen(session.id)
  assert.equal(board.snapshot('').rows.length, 0)
})

test('cold completed history is not replayed as green', () => {
  const session = {
    id: 'session-old',
    header: {},
    snapshotEvents: () => [
      { type: 'turn/start', time: 1 },
      { type: 'turn/end', time: 2, data: { reason: { kind: 'completed' } } },
    ],
  }
  const ctx = {
    sessions: { list: () => [session] },
    agents: { get: () => ({ status: 'idle' }) },
    get: () => undefined,
    logger: { warn() {} },
  }
  const board = new Board(ctx)
  assert.equal(board.snapshot('').rows.length, 0)
})
