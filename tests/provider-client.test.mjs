import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:net'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { NotchProviderClient } from '../src/provider/client.ts'

/**
 * A stub endpoint, speaking the protocol by hand.
 *
 * The client's job is the wire: framing, the lease, and what it does about each
 * kind of answer. A stub is the only way to test that deterministically — against
 * a real Notch the test would depend on the user's decisions, and against no
 * Notch it would depend on a timeout.
 */
class StubEndpoint {
  /** Every message the client has sent, in order. */
  received = []
  /** What has arrived that is not yet a whole line. */
  buffer = ''
  server = null
  socket = null

  constructor() {
    this.directory = mkdtempSync(join(tmpdir(), 'notch-stub-'))
    this.path = join(this.directory, 'notch.sock')
  }

  listen() {
    const server = createServer((socket) => {
      this.socket = socket
      socket.on('data', (chunk) => {
        this.buffer += chunk.toString('utf8')
        let newline = this.buffer.indexOf('\n')
        while (newline !== -1) {
          const line = this.buffer.slice(0, newline)
          this.buffer = this.buffer.slice(newline + 1)
          if (line.trim() === '') continue
          try {
            this.received.push(JSON.parse(line))
          } catch {
            throw new Error(`the client sent something that is not a JSON frame: ${JSON.stringify(line)}`)
          }
          newline = this.buffer.indexOf('\n')
        }
      })
    })
    this.server = server
    return new Promise((resolve) => { server.listen(this.path, resolve) })
  }

  /** Send one message to the client, as Notch would. */
  send(message) {
    this.socket?.write(`${JSON.stringify(message)}\n`)
  }

  /** Whether the connection is open. */
  get connected() {
    return this.socket !== null && !this.socket.destroyed
  }

  /** Wait for a message the client sends, so a test does not sleep on a guess. */
  async waitFor(type, count = 1, timeoutMs = 2000) {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
      const matching = this.received.filter((message) => message.type === type)
      if (matching.length >= count) return matching[count - 1]
      await new Promise((resolve) => setTimeout(resolve, 5))
    }
    throw new Error(`no ${type} arrived; the client sent ${this.received.map((m) => String(m.type)).join(', ')}`)
  }

  close() {
    this.socket?.destroy()
    this.server?.close()
    rmSync(this.directory, { recursive: true, force: true })
  }
}

/** A client, and the endpoint it is talking to. */
async function connected(handlers = {}) {
  const endpoint = new StubEndpoint()
  await endpoint.listen()
  const client = new NotchProviderClient(
    { path: endpoint.path, handlers },
    { displayName: 'Test', requestedClasses: ['activity', 'result', 'awaiting'], actions: ['open'] }
  )
  client.start()
  const register = await endpoint.waitFor('register')
  return { endpoint, client, register }
}

const entity = (key) => ({ key, class: 'activity', state: 'running', lifetime: 'held' })

test('a provider registers with what it wants and what it interprets', async () => {
  const { endpoint, client, register } = await connected()
  const registration = register.registration
  assert.equal(registration.displayName, 'Test')
  assert.deepEqual(registration.requestedClasses, ['activity', 'result', 'awaiting'])
  assert.deepEqual(registration.actions, ['open'])
  client.stop()
  endpoint.close()
})

test('nothing is written before the grant, and nothing is believed either', async () => {
  const { endpoint, client } = await connected()
  client.snapshot([entity('a')])
  client.apply([entity('b')], [])
  client.acknowledge('a')
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.deepEqual(endpoint.received.map((message) => message.type), ['register'])
  // A provider that recorded what it could not say would believe Notch holds
  // something it has never been told.
  assert.deepEqual(client.held(), [])
  client.stop()
  endpoint.close()
})

test('the grant is reported, and state may be stated once it arrives', async () => {
  let granted = null
  const { endpoint, client } = await connected({ onGranted: (value) => { granted = value } })
  endpoint.send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity'], limits: {} } })
  await endpoint.waitFor('renew', 1, 4000)
  client.snapshot([entity('a')])
  const snapshot = await endpoint.waitFor('snapshot')
  assert.deepEqual(snapshot.entities, [entity('a')])
  assert.deepEqual(granted, { protocolVersion: 1, grantedClasses: ['activity'], limits: {} })
  client.stop()
  endpoint.close()
})

test('deltas go out one message each, and a removal says what to remove', async () => {
  const { endpoint, client } = await connected()
  endpoint.send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity'], limits: {} } })
  await endpoint.waitFor('granted').catch(() => undefined)
  client.apply([entity('a'), entity('b')], ['gone'])
  await endpoint.waitFor('upsert')
  await endpoint.waitFor('upsert', 2)
  assert.deepEqual(await endpoint.waitFor('remove'), { type: 'remove', key: 'gone' })
  client.stop()
  endpoint.close()
})

test('the unread flag is cleared through an acknowledgement, and only once', async () => {
  const { endpoint, client } = await connected()
  endpoint.send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['result'], limits: {} } })
  await endpoint.waitFor('granted').catch(() => undefined)
  client.apply([{ key: 'r', class: 'result', state: 'succeeded', lifetime: 'held', unread: true }], [])
  await endpoint.waitFor('upsert')
  client.acknowledge('r')
  await endpoint.waitFor('ack')
  // A second acknowledgement would be a state statement with nothing in it.
  client.acknowledge('r')
  await new Promise((resolve) => setTimeout(resolve, 30))
  assert.equal(endpoint.received.filter((message) => message.type === 'ack').length, 1)
  client.stop()
  endpoint.close()
})

test('the lease is renewed on the protocol interval', async () => {
  const { endpoint, client } = await connected()
  endpoint.send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity'], limits: {} } })
  await endpoint.waitFor('renew', 1, 4000)
  client.stop()
  endpoint.close()
})

test('a refusal is reported with its code, which is what a provider branches on', async () => {
  const refusals = []
  const { endpoint, client } = await connected({ onRefused: (code, reason) => { refusals.push([code, reason]) } })
  endpoint.send({ type: 'refused', code: 'not-consented', reason: 'the user has not allowed this program yet' })
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.deepEqual(refusals, [['not-consented', 'the user has not allowed this program yet']])
  client.stop()
  endpoint.close()
})

test('the user allowing a program is reported, and it registers again', async () => {
  let allowed = 0
  const { endpoint, client } = await connected({ onConsentGranted: () => { allowed += 1 } })
  endpoint.send({ type: 'consent.granted' })
  // Registering again is the point of being told: a provider that had to poll for
  // the answer would be asking the user a second time in everything but name.
  const second = await endpoint.waitFor('register', 2)
  assert.equal(second.type, 'register')
  assert.equal(allowed, 1)
  client.stop()
  endpoint.close()
})

test('a settlement is delivered with its answers', async () => {
  const settled = []
  const { endpoint, client } = await connected({ onSettled: (settlement) => { settled.push(settlement) } })
  endpoint.send({
    type: 'interaction.settled',
    key: 's1:ask',
    interactionId: 'ask:q1',
    outcome: { status: 'answered', answers: { q1: ['A'] } },
  })
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.deepEqual(settled, [
    { type: 'interaction.settled', key: 's1:ask', interactionId: 'ask:q1', outcome: { status: 'answered', answers: { q1: ['A'] } } },
  ])
  client.stop()
  endpoint.close()
})

test('an action the user activated is reported with what it was for', async () => {
  const actions = []
  const { endpoint, client } = await connected({ onAction: (...args) => { actions.push(args) } })
  endpoint.send({ type: 'action.invoke', name: 'open', key: 's1:result', args: { at: 1 } })
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.deepEqual(actions, [['open', 's1:result', { at: 1 }]])
  client.stop()
  endpoint.close()
})

test('a connection that ends is reported, and the provider tries again', async () => {
  const closed = []
  const { endpoint, client } = await connected({ onClosed: (reason) => { closed.push(reason) } })
  endpoint.close()
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.equal(closed.length, 1)
  client.stop()
})

test('what the provider believes is held is what it last said', async () => {
  const { endpoint, client } = await connected()
  endpoint.send({ type: 'granted', grant: { protocolVersion: 1, grantedClasses: ['activity'], limits: {} } })
  await endpoint.waitFor('granted').catch(() => undefined)
  client.apply([entity('a')], [])
  await endpoint.waitFor('upsert')
  assert.deepEqual(client.held().map((held) => held.key), ['a'])
  client.stop()
  endpoint.close()
})
