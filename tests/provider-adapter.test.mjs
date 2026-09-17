import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:net'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

/**
 * The adapter's wiring, which is the part that has never been tested.
 *
 * `entities.ts` is a pure function and is covered on its own; what kept going
 * wrong is everything around it — when the connection opens, what is published
 * once it is granted, and what happens to an answer on the way back. Those are
 * the joints between two tested parts, so they need testing as a whole, against a
 * stub endpoint and a board that does nothing but what a test tells it to.
 *
 * The socket is chosen by environment, so the stub is installed before the
 * adapter is imported: `endpointPath()` reads it when the client is built.
 */
const directory = mkdtempSync(join(tmpdir(), 'notch-adapter-'))
const socketPath = join(directory, 'notch.sock')
process.env.DSH_NOTCH_SOCKET = socketPath

const { DshProvider } = await import('../src/provider/adapter.ts')

/** Every message the adapter sends, in order. */
const received = []
let socket = null
let server = null
let buffer = ''

/** Send one message to the adapter, as Notch would. */
function send(message) {
  socket?.write(`${JSON.stringify(message)}\n`)
}

/** Wait for a message the adapter sends. */
async function waitFor(type, count = 1, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const matching = received.filter((message) => message.type === type)
    if (matching.length >= count) return matching[count - 1]
    await new Promise((resolve) => setTimeout(resolve, 5))
  }
  throw new Error(`no ${type} arrived; the adapter sent ${received.map((m) => String(m.type)).join(', ') || 'nothing'}`)
}

/** A board that says what it is told to, and records what it is asked to do. */
function fakeBoard(rows) {
  const listeners = new Set()
  return {
    rows,
    approved: [],
    answered: [],
    focused: [],
    snapshot: () => ({ ok: true, generatedAt: 0, origin: 'stub', rows: [...rows] }),
    onChange: (fn) => { listeners.add(fn); return () => listeners.delete(fn) },
    /** Change what the board says, and tell whoever is listening. */
    becomes(next) { rows.splice(0, rows.length, ...next); for (const fn of listeners) fn() },
    decideApproval(id, outcome) { this.approved.push([id, outcome]); return true },
    answerAsk(id, items) { this.answered.push([id, items]); return true },
    requestFocus(sessionId) { this.focused.push(sessionId); return true },
  }
}

/** Start a stub endpoint and an adapter following the given board. */
async function connected(rows) {
  // Each case gets the socket to itself: a server from the last one still holds
  // the address, and a connection still open keeps its server from closing.
  socket?.destroy()
  socket = null
  if (server !== null) await new Promise((resolve) => { server.close(resolve) })
  rmSync(socketPath, { force: true })

  received.length = 0
  buffer = ''
  server = createServer((accepted) => {
    socket = accepted
    accepted.on('data', (chunk) => {
      buffer += chunk.toString('utf8')
      let newline = buffer.indexOf('\n')
      while (newline !== -1) {
        const line = buffer.slice(0, newline)
        buffer = buffer.slice(newline + 1)
        if (line.trim() !== '') received.push(JSON.parse(line))
        newline = buffer.indexOf('\n')
      }
    })
  })
  await new Promise((resolve) => { server.listen(socketPath, resolve) })

  const board = fakeBoard(rows)
  const provider = new DshProvider({ board, decisionTimeoutMs: 900_000, actions: ['open'], log: () => {} })
  provider.start()
  return { board, provider }
}

test('nothing is connected while there is nothing to show', async () => {
  const { provider } = await connected([])
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.deepEqual(received, [], 'a program with nothing to show does not ask to be allowed to show it')
  provider.stop()
})

test('the first thing worth showing opens the connection', async () => {
  const { provider } = await connected([{ id: 's1', title: '会话', child: false, busy: true, unread: false }])
  const register = await waitFor('register')
  assert.equal(register.registration.protocolVersion, 1, 'and it states the version it speaks')
  assert.deepEqual(register.registration.requestedClasses, ['activity', 'result', 'awaiting'])
  provider.stop()
})

test('the grant is what makes it publish, and the snapshot states what it has', async () => {
  const { provider } = await connected([{ id: 's1', title: '会话', child: false, busy: true, unread: false }])
  await waitFor('register')
  send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity'], limits: {} } })
  const snapshot = await waitFor('snapshot')
  assert.equal(snapshot.entities.length, 1)
  assert.equal(snapshot.entities[0].key, 's1:run')
  assert.equal(snapshot.entities[0].class, 'activity')
  assert.equal(snapshot.entities[0].title, '会话')
  provider.stop()
})

test('a change on the board reaches Notch without being asked', async () => {
  const rows = [{ id: 's1', title: '会话', child: false, busy: true, unread: false }]
  const { board, provider } = await connected(rows)
  await waitFor('register')
  send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity', 'result'], limits: {} } })
  await waitFor('snapshot')

  // The session finishes: work in progress becomes something to read.
  board.becomes([{ id: 's1', title: '会话', child: false, busy: false, unread: true, lastTurn: { at: 1, kind: 'success', failed: false } }])
  const upsert = await waitFor('upsert')
  assert.equal(upsert.entity.class, 'result')
  assert.equal(upsert.entity.unread, true)
  const remove = await waitFor('remove')
  assert.equal(remove.key, 's1:run', 'the work in progress it no longer is gets removed')
  provider.stop()
})

test('a board that reports nothing is still read, so the surface is not blind', async () => {
  // One thing already shown, so the change below travels as a delta rather than
  // as the snapshot that states everything for the first time.
  const rows = [{ id: 's1', title: '会话', child: false, busy: true, unread: false }]
  const { board, provider } = await connected(rows)
  await waitFor('register')
  send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity'], limits: {} } })
  await waitFor('snapshot')

  // The board changes and says nothing about it, which is the state the live Host
  // turned out to be in. The adapter has to notice anyway.
  board.rows.splice(0, board.rows.length, { id: 's1', title: '改名了', child: false, busy: true, unread: false })
  const upsert = await waitFor('upsert', 1, 4000)
  assert.equal(upsert.entity.title, '改名了')
  provider.stop()
})

test('a decision the user answers is applied to the board', async () => {
  const rows = [
    { id: 's1', title: '会话', child: false, busy: false, unread: false, approval: { id: 'a1', toolName: 'bash' } },
  ]
  const { board, provider } = await connected(rows)
  await waitFor('register')
  send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['awaiting'], limits: {} } })
  const snapshot = await waitFor('snapshot')
  assert.equal(snapshot.entities[0].interaction.id, 'approval:a1')

  send({
    type: 'interaction.settled',
    key: 's1:ask',
    interactionId: 'approval:a1',
    outcome: { status: 'answered', answers: { a1: ['允许'] } },
  })
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.deepEqual(board.approved, [['a1', 'allowed-once']], 'a tap on 允许 is what DSH is told')
  provider.stop()
})

test('a question the user answers is applied to the board', async () => {
  const rows = [
    {
      id: 's1',
      title: '会话',
      child: false,
      busy: false,
      unread: false,
      ask: { id: 'q1', questions: [{ id: 'q1', question: '选哪个？', options: [{ label: 'A' }, { label: 'B' }] }] },
    },
  ]
  const { board, provider } = await connected(rows)
  await waitFor('register')
  send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['awaiting'], limits: {} } })
  const snapshot = await waitFor('snapshot')
  assert.equal(snapshot.entities[0].interaction.id, 'ask:q1')

  send({
    type: 'interaction.settled',
    key: 's1:ask',
    interactionId: 'ask:q1',
    outcome: { status: 'answered', answers: { q1: ['B'] } },
  })
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.deepEqual(board.answered, [['q1', [{ id: 'q1', selected: ['B'] }]]], 'the chosen option is what DSH is told')
  provider.stop()
})

test('an action the user activated is routed to the board', async () => {
  const { board, provider } = await connected([{ id: 's1', title: '会话', child: false, busy: true, unread: false }])
  await waitFor('register')
  send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity'], limits: {} } })
  await waitFor('snapshot')

  send({ type: 'action.invoke', name: 'open', key: 's1:run' })
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.deepEqual(board.focused, ['s1'], 'an action on a session brings that session forward')
  provider.stop()
})

test.after(() => {
  server?.close()
  rmSync(directory, { recursive: true, force: true })
})
