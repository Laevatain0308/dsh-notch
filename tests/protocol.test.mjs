import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LIMITS, PROTOCOL_VERSION } from '../protocol/v1/index.ts'
import { ProviderSession } from '../protocol/v1/session.ts'

const NOW = 1_000_000

/** A session that has registered with every class and sent no entities yet. */
function registered(classes = ['ambient', 'progress', 'activity', 'result', 'awaiting']) {
  const session = new ProviderSession()
  const outcome = session.register({ protocolVersion: PROTOCOL_VERSION, requestedClasses: classes, actions: ['open'] }, NOW)
  assert.ok('grant' in outcome, `registration refused: ${'reason' in outcome ? outcome.reason : ''}`)
  return session
}

/** A valid entity of the given class, with the fields that class requires. */
function entity(overrides = {}) {
  return { key: 'k', class: 'activity', state: 'running', lifetime: 'held', ...overrides }
}

/** A valid single-question interaction. */
const ask = {
  id: 'i1',
  questions: [{ id: 'q1', question: 'Proceed?', options: [{ label: 'Yes' }, { label: 'No' }] }],
}

test('registration negotiates the version and refuses an incompatible one', () => {
  const session = new ProviderSession()
  const refused = session.register({ protocolVersion: PROTOCOL_VERSION + 1, requestedClasses: ['activity'] }, NOW)
  assert.ok('reason' in refused)
  assert.match(refused.reason, /not compatible/)
})

test('registration refuses an unknown or empty class set', () => {
  const session = new ProviderSession()
  assert.match(session.register({ protocolVersion: PROTOCOL_VERSION, requestedClasses: [] }, NOW).reason, /no behaviour classes/)
  assert.match(session.register({ protocolVersion: PROTOCOL_VERSION, requestedClasses: ['downloads'] }, NOW).reason, /unknown behaviour class/)
})

test('the grant reports the limits Core will enforce', () => {
  const session = new ProviderSession()
  const outcome = session.register({ protocolVersion: PROTOCOL_VERSION, requestedClasses: ['progress'] }, NOW)
  assert.ok('grant' in outcome)
  assert.deepEqual(outcome.grant.grantedClasses, ['progress'])
  assert.equal(outcome.grant.limits.entitiesPerProvider, 16)
  assert.equal(outcome.grant.limits.capsuleCapacity, 4)
})

test('nothing is accepted before registration', () => {
  const session = new ProviderSession()
  assert.match(session.receive({ type: 'renew' }, NOW).reason, /not registered/)
})

test('a delta before the snapshot is refused', () => {
  const session = registered()
  assert.match(session.receive({ type: 'upsert', entity: entity() }, NOW).reason, /delta before snapshot/)
  assert.match(session.receive({ type: 'remove', key: 'k' }, NOW).reason, /delta before snapshot/)
})

test('a snapshot begins the subscription and bounds the entity count', () => {
  const session = registered()
  assert.equal(session.receive({ type: 'snapshot', entities: [entity()] }, NOW).ok, true)
  assert.equal(session.hasSnapshot, true)

  const many = Array.from({ length: LIMITS.entitiesPerProvider + 1 }, (_, index) => entity({ key: `k${String(index)}` }))
  const other = registered()
  assert.match(other.receive({ type: 'snapshot', entities: many }, NOW).reason, /above the limit/)
})

test('a snapshot may carry an awaiting entity with its interaction', () => {
  const session = registered()
  const awaiting = entity({ key: 'a', class: 'awaiting', state: 'pending', interaction: ask })
  assert.equal(session.receive({ type: 'snapshot', entities: [awaiting] }, NOW).ok, true)
  assert.equal(session.awaiting().length, 1)
})

test('a state outside its class is refused', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [] }, NOW)
  const bad = entity({ class: 'result', state: 'running', lifetime: 'held' })
  assert.match(session.receive({ type: 'upsert', entity: bad }, NOW).reason, /is not a result state/)
})

test('a class that was not granted is refused', () => {
  const session = registered(['activity'])
  session.receive({ type: 'snapshot', entities: [] }, NOW)
  const bad = entity({ class: 'progress', state: 'running' })
  assert.match(session.receive({ type: 'upsert', entity: bad }, NOW).reason, /was not granted/)
})

test('class-specific fields are refused on the wrong class', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [] }, NOW)
  assert.match(session.receive({ type: 'upsert', entity: entity({ fraction: 0.5 }) }, NOW).reason, /only a progress entity/)
  assert.match(session.receive({ type: 'upsert', entity: entity({ unread: true }) }, NOW).reason, /only a result entity/)
  assert.match(session.receive({ type: 'upsert', entity: entity({ interaction: ask }) }, NOW).reason, /only an awaiting entity/)
})

test('a fraction must be within range and an undeclared action is refused', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [] }, NOW)
  const over = entity({ class: 'progress', state: 'running', fraction: 1.5 })
  assert.match(session.receive({ type: 'upsert', entity: over }, NOW).reason, /between 0 and 1/)
  const undeclared = entity({ actions: ['delete'] })
  assert.match(session.receive({ type: 'upsert', entity: undeclared }, NOW).reason, /was not declared/)
})

test('over-long text is refused', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [] }, NOW)
  const long = entity({ title: 'x'.repeat(LIMITS.titleLength + 1) })
  assert.match(session.receive({ type: 'upsert', entity: long }, NOW).reason, /title longer than/)
})

test('a provider holds one outstanding interaction at a time', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [] }, NOW)
  const first = entity({ key: 'a', class: 'awaiting', state: 'pending', interaction: ask })
  assert.equal(session.receive({ type: 'upsert', entity: first }, NOW).ok, true)

  const second = entity({ key: 'b', class: 'awaiting', state: 'pending', interaction: { ...ask, id: 'i2' } })
  assert.match(session.receive({ type: 'upsert', entity: second }, NOW).reason, /outstanding interaction/)
  assert.equal(session.awaiting().length, 1)
})

test('an interaction on an entity that is not awaiting is refused', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [] }, NOW)
  const outcome = session.receive({ type: 'interaction.request', key: 'k', interaction: ask }, NOW)
  assert.match(outcome.reason, /no entity/)
})

test('acknowledging clears unread and unknown keys are refused', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [entity({ class: 'result', state: 'succeeded', unread: true })] }, NOW)
  assert.equal(session.entities()[0].unread, true)
  assert.equal(session.receive({ type: 'ack', key: 'k' }, NOW).ok, true)
  assert.equal(session.entities()[0].unread, false)
  assert.match(session.receive({ type: 'ack', key: 'absent' }, NOW).reason, /no entity/)
})

test('the lease expires unless it is renewed', () => {
  const session = registered()
  assert.equal(session.expired(NOW + LIMITS.leaseExpiryMs - 1), false)
  assert.equal(session.expired(NOW + LIMITS.leaseExpiryMs), true)

  session.receive({ type: 'renew' }, NOW + LIMITS.leaseRenewMs)
  assert.equal(session.expired(NOW + LIMITS.leaseExpiryMs), false)
})

test('unregistering drops the entities', () => {
  const session = registered()
  session.receive({ type: 'snapshot', entities: [entity()] }, NOW)
  assert.equal(session.entities().length, 1)
  assert.equal(session.receive({ type: 'unregister' }, NOW).ok, true)
  assert.equal(session.entities().length, 0)
})

test('the protocol carries the decided limits', () => {
  assert.equal(PROTOCOL_VERSION, 1)
  assert.equal(LIMITS.capsuleCapacity, 4)
  assert.equal(LIMITS.adjudicativeQueueDepth, 1)
  assert.equal(LIMITS.outstandingAwaitingPerProvider, 1)
  assert.equal(LIMITS.leaseRenewMs, 2_000)
  assert.equal(LIMITS.leaseExpiryMs, 6_000)
  assert.equal(LIMITS.consentRateLimitMs, 30_000)
  assert.equal(LIMITS.reRequestFloorMs, 600_000)
})
