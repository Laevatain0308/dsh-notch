import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LIMITS, PROTOCOL_VERSION } from '../protocol/v1/index.ts'
import { NotchCore } from '../protocol/v1/core.ts'

const NOW = 1_000_000

/** A core holding one registered provider that has sent its opening snapshot. */
function core(providers = ['p1', 'p2']) {
  const notch = new NotchCore()
  for (const provider of providers) {
    notch.connect(provider, provider.toUpperCase())
    const outcome = notch.receive(provider, {
      type: 'register',
      registration: { protocolVersion: PROTOCOL_VERSION, requestedClasses: ['ambient', 'progress', 'activity', 'result', 'awaiting'], actions: [] },
    }, NOW)
    assert.ok(outcome.ok, `registration refused: ${outcome.ok ? '' : outcome.reason}`)
    assert.equal(notch.receive(provider, { type: 'snapshot', entities: [] }, NOW).ok, true)
  }
  return notch
}

/** A valid single-question interaction, addressed by id. */
function ask(id = 'i1') {
  return { id, questions: [{ id: 'q1', question: 'Proceed?', options: [{ label: 'Yes' }, { label: 'No' }] }] }
}

/** An awaiting entity carrying a decision. */
function decision(key, id = 'i1', title = 'Proceed?') {
  return { key, class: 'awaiting', state: 'pending', lifetime: 'held', title, interaction: ask(id) }
}

/** Put one provider's decision in the queue, asserting it was admitted. */
function raise(notch, provider, key, id = 'i1') {
  const outcome = notch.receive(provider, { type: 'upsert', entity: decision(key, id, `Ask ${key}`) }, NOW)
  assert.ok(outcome.ok, `decision refused: ${outcome.ok ? '' : outcome.reason}`)
  return outcome
}

test('a provider that is not connected cannot speak', () => {
  const notch = new NotchCore()
  const outcome = notch.receive('ghost', { type: 'renew' }, NOW)
  assert.equal(outcome.ok, false)
  assert.match(outcome.reason, /unknown provider/)
})

test('unregistered providers are not listed, registered ones are', () => {
  const notch = new NotchCore()
  notch.connect('p1', 'Downloader')
  assert.deepEqual(notch.providers(), [])
  notch.receive('p1', { type: 'register', registration: { protocolVersion: PROTOCOL_VERSION, requestedClasses: ['progress'] } }, NOW)
  assert.deepEqual(notch.providers(), [{ id: 'p1', displayName: 'Downloader', classes: ['progress'], entities: 0 }])
})

test('one decision is on screen and the next waits behind it', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b')

  const { expanded, waiting } = notch.adjudication()
  assert.equal(expanded?.provider, 'p1')
  assert.equal(expanded?.key, 'a')
  assert.equal(expanded?.title, 'Ask a')
  assert.equal(expanded?.interaction.id, 'i1')
  assert.equal(waiting?.provider, 'p2')
  assert.equal(waiting?.key, 'b')
})

test('a third decision is refused and its provider is told why', () => {
  const notch = core(['p1', 'p2', 'p3'])
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b')

  const outcome = notch.receive('p3', { type: 'upsert', entity: decision('c', 'i3') }, NOW)
  assert.equal(outcome.ok, false)
  assert.match(outcome.reason, /already on screen/)
  // The refusal leaves nothing behind: p3 holds no entity and no place.
  assert.equal(notch.adjudication().waiting?.provider, 'p2')
  assert.equal(notch.providers().find(record => record.id === 'p3')?.entities, 0)
})

test('a refused decision is admitted once the queue has room', () => {
  const notch = core(['p1', 'p2', 'p3'])
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b')
  assert.equal(notch.receive('p3', { type: 'upsert', entity: decision('c', 'i3') }, NOW).ok, false)

  assert.ok(notch.answer('i1', { q1: ['Yes'] }).ok)
  // The refusal was about the queue, not about p3, so asking again succeeds.
  raise(notch, 'p3', 'c', 'i3')
  assert.equal(notch.adjudication().expanded?.provider, 'p2', 'the waiting decision promoted')
  assert.equal(notch.adjudication().waiting?.provider, 'p3')
})

test('answering goes to the decision on screen and only to it', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b', 'i2')

  const outcome = notch.answer('i2', { q1: ['No'] })
  assert.equal(outcome.ok, false, 'the user cannot answer a question they have not been shown')
  assert.match(outcome.reason, /no outstanding decision/)

  const answered = notch.answer('i1', { q1: ['Yes'] })
  assert.ok(answered.ok)
  assert.deepEqual(answered.settlement, {
    key: 'a',
    interactionId: 'i1',
    outcome: { status: 'answered', answers: { q1: ['Yes'] } },
  })
  assert.equal(notch.adjudication().expanded?.provider, 'p2', 'b promoted to the screen')
  assert.equal(notch.adjudication().waiting, null)
})

test('withdrawing the decision on screen promotes the one waiting', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b', 'i2')

  assert.equal(notch.receive('p1', { type: 'interaction.cancel', key: 'a', interactionId: 'i1' }, NOW).ok, true)
  assert.equal(notch.adjudication().expanded?.provider, 'p2')
})

test('removing the entity on screen promotes the one waiting', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b', 'i2')

  assert.equal(notch.receive('p1', { type: 'remove', key: 'a' }, NOW).ok, true)
  assert.equal(notch.adjudication().expanded?.key, 'b')
})

test('a re-sent decision keeps the place it already had', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p1', 'a', 'i1')
  assert.equal(notch.adjudication().expanded?.key, 'a')
  assert.equal(notch.adjudication().waiting, null, 'it did not queue behind itself')
  assert.equal(notch.providers().find(record => record.id === 'p1')?.entities, 1)
})

test('a lease lapse gives up the queue and settles the decision as abandoned', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b', 'i2')

  const settled = notch.tick(NOW + LIMITS.leaseExpiryMs)
  assert.equal(settled.length, 2)
  assert.deepEqual(settled.map(entry => entry.provider).sort(), ['p1', 'p2'])
  for (const entry of settled) assert.equal(entry.settlement.outcome.status, 'cancelled')
  assert.deepEqual(notch.adjudication(), { expanded: null, waiting: null })
  assert.deepEqual(notch.providers(), [], 'a lapsed lease leaves nothing registered')
})

test('one provider leaving does not disturb the other', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b', 'i2')

  // p1's lease lapses while p2 keeps renewing.
  notch.receive('p2', { type: 'renew' }, NOW + LIMITS.leaseExpiryMs)
  const settled = notch.tick(NOW + LIMITS.leaseExpiryMs)
  assert.deepEqual(settled.map(entry => entry.provider), ['p1'])
  assert.equal(notch.adjudication().expanded?.provider, 'p2', 'p2 promoted into the free place')
  assert.deepEqual(notch.providers().map(record => record.id), ['p2'])
})

test('a question left too long is settled without taking the provider with it', () => {
  const notch = core(['p1'])
  notch.receive('p1', { type: 'upsert', entity: { key: 'work', class: 'progress', state: 'running', lifetime: 'held', fraction: 0.5 } }, NOW)
  raise(notch, 'p1', 'a')

  // A deadline of half an hour is only ever reached by a provider that is still
  // alive to reach it, so it keeps renewing its lease throughout.
  const deadline = NOW + LIMITS.interactionDeadlineMs
  for (let at = NOW; at < deadline; at += LIMITS.leaseRenewMs) {
    assert.equal(notch.receive('p1', { type: 'renew' }, at).ok, true)
  }
  assert.deepEqual(notch.tick(deadline - 1), [], 'not before the deadline')
  const settled = notch.tick(deadline)
  assert.equal(settled.length, 1)
  assert.equal(settled[0].provider, 'p1')
  assert.match(settled[0].settlement.outcome.reason, /not made in time/)
  assert.deepEqual(notch.adjudication(), { expanded: null, waiting: null })
  // The provider is still registered and still holds both entities: the work,
  // and the question as a settled record of what the user was asked.
  assert.equal(notch.providers().find(record => record.id === 'p1')?.entities, 2)
})

test('a disconnecting provider settles what it left outstanding', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  const settled = notch.disconnect('p1')
  assert.equal(settled.length, 1)
  assert.equal(settled[0].provider, 'p1')
  assert.deepEqual(notch.adjudication(), { expanded: null, waiting: null })
  assert.equal(notch.receive('p1', { type: 'renew' }, NOW).ok, false, 'the session is gone')
  assert.deepEqual(notch.disconnect('p1'), [], 'disconnecting twice is not an error')
})

test('unregistering gives up the queue but keeps the connection', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  assert.equal(notch.receive('p1', { type: 'unregister' }, NOW).ok, true)
  assert.deepEqual(notch.adjudication(), { expanded: null, waiting: null })
  const again = notch.receive('p1', {
    type: 'register',
    registration: { protocolVersion: PROTOCOL_VERSION, requestedClasses: ['awaiting'] },
  }, NOW)
  assert.ok(again.ok, 'a disconnected provider may register again on the same connection')
})

test('the queue is filled in the order decisions arrive, not by provider name', () => {
  const notch = core(['p1', 'p3'])
  raise(notch, 'p3', 'z')
  raise(notch, 'p1', 'a', 'i2')
  assert.equal(notch.adjudication().expanded?.provider, 'p3')
  assert.equal(notch.adjudication().waiting?.provider, 'p1')
})

test('reconnecting keeps the place the provider held', () => {
  const notch = core()
  raise(notch, 'p1', 'a')
  raise(notch, 'p2', 'b', 'i2')
  notch.connect('p1', 'p1 again')
  assert.equal(notch.adjudication().expanded?.provider, 'p1', 'a reconnect is not a new provider')
})

test('a lapsed lease ends the grant, so the provider must register again', () => {
  const notch = core(['p1'])
  raise(notch, 'p1', 'a')
  notch.tick(NOW + LIMITS.leaseExpiryMs)

  const late = notch.receive('p1', { type: 'upsert', entity: decision('b', 'i2') }, NOW + LIMITS.leaseExpiryMs)
  assert.equal(late.ok, false)
  assert.match(late.reason, /not registered/)

  const again = notch.receive('p1', {
    type: 'register',
    registration: { protocolVersion: PROTOCOL_VERSION, requestedClasses: ['awaiting'] },
  }, NOW + LIMITS.leaseExpiryMs)
  assert.ok(again.ok)
  // Registering again opens a new subscription, so the snapshot comes first.
  assert.match(notch.receive('p1', { type: 'upsert', entity: decision('b', 'i2') }, NOW).reason, /delta before snapshot/)
  assert.equal(notch.receive('p1', { type: 'snapshot', entities: [] }, NOW).ok, true)
  raise(notch, 'p1', 'b', 'i2')
  assert.equal(notch.adjudication().expanded?.key, 'b')
})

