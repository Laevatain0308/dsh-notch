import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  answersFrom,
  delta,
  entitiesFor,
  isDeciding,
  remember,
  resultKey,
  runKey,
  askKey,
} from '../src/provider/entities.ts'

const context = { queuedDecisions: 0, actions: ['open'] }
const TIMEOUT = 900_000

/** A session row, with only what the case is about. */
function row(overrides = {}) {
  return { id: 's1', title: '会话一', child: false, busy: false, unread: false, ...overrides }
}

/** The entities one row produces. */
function shown(overrides = {}, adapterContext = context) {
  return entitiesFor([row(overrides)], adapterContext, TIMEOUT)
}

test('a running session is activity, which aggregates with every other provider', () => {
  const entities = shown({ busy: true })
  assert.equal(entities.length, 1)
  assert.deepEqual(
    { key: entities[0].key, class: entities[0].class, state: entities[0].state },
    { key: runKey('s1'), class: 'activity', state: 'running' }
  )
})

test('an unread completion is a result, and its outcome is in the state', () => {
  const succeeded = shown({ unread: true, lastTurn: { at: 1, kind: 'success', failed: false } })
  assert.equal(succeeded[0].class, 'result')
  assert.equal(succeeded[0].state, 'succeeded')
  assert.equal(succeeded[0].unread, true)

  const failed = shown({ unread: true, lastTurn: { at: 1, kind: 'failure', failed: true } })
  assert.equal(failed[0].state, 'failed')
})

test('a session that is running and unread is two entities, not one', () => {
  const entities = shown({ busy: true, unread: true, lastTurn: { at: 1, kind: 'success', failed: false } })
  assert.deepEqual(entities.map((entity) => entity.class).sort(), ['activity', 'result'])
  assert.equal(new Set(entities.map((entity) => entity.key)).size, 2, 'two entities need two identities')
})

test('a session waiting on the user is a decision, and nothing else', () => {
  const entities = shown({ busy: true, approval: { id: 'a1', toolName: 'bash' } })
  assert.equal(entities.length, 1, 'a question is not shown beside a running lamp')
  assert.equal(entities[0].class, 'awaiting')
  assert.equal(entities[0].state, 'pending')
  assert.equal(entities[0].interaction.id, 'approval:a1')
  assert.equal(entities[0].interaction.questions[0].question, '允许运行 bash？')
  assert.deepEqual(entities[0].interaction.questions[0].options.map((option) => option.label), ['允许', '拒绝'])
})

test('a question keeps what the user has to read', () => {
  const entities = shown({
    ask: {
      id: 'q1',
      questions: [
        { id: 'q1', question: '选哪个？', header: '选择', detail: '说明', options: [{ label: 'A' }, { label: 'B' }], multiSelect: true },
      ],
    },
  })
  const question = entities[0].interaction.questions[0]
  assert.equal(entities[0].interaction.id, 'ask:q1')
  assert.deepEqual(question, {
    id: 'q1',
    question: '选哪个？',
    header: '选择',
    detail: '说明',
    options: [{ label: 'A' }, { label: 'B' }],
    multiSelect: true,
  })
})

test('a decision is only raised while one is asked at a time', () => {
  const rows = [
    row({ id: 's1', approval: { id: 'a1', toolName: 'bash' } }),
    row({ id: 's2', approval: { id: 'a2', toolName: 'read' } }),
  ]
  const entities = entitiesFor(rows, { queuedDecisions: 1, actions: [] }, TIMEOUT)
  assert.equal(entities.length, 2, 'one decision per session, and one of them is the decision Notch holds')
  const raised = entities.filter((entity) => entity.class === 'awaiting')
  assert.equal(raised.length, 2, 'the adapter raises what it has; the queue is Core\'s to bound')
  assert.ok(raised.some((entity) => entity.body === '还有 1 个会话在等待处理'), 'the ones behind are counted')
})

test('the timeout a decision may wait is the one the adapter asked for', () => {
  const entities = entitiesFor([row({ ask: { id: 'q1', questions: [] } })], context, 60_000)
  assert.equal(entities[0].interaction.timeoutMs, 60_000)
})

test('an approval is answered as one of the two outcomes DSH understands', () => {
  const interaction = { id: 'approval:a1', questions: [{ id: 'a1', question: 'x', options: [] }] }
  assert.deepEqual(answersFrom(interaction, { a1: ['允许'] }), { kind: 'approval', outcome: 'allowed-once' })
  assert.deepEqual(answersFrom(interaction, { a1: ['拒绝'] }), { kind: 'approval', outcome: 'rejected' })
  // Nothing selected is a refusal, not a silence: DSH waits for a decision.
  assert.deepEqual(answersFrom(interaction, {}), { kind: 'approval', outcome: 'rejected' })
})

test('a question is answered as the items DSH expects', () => {
  const interaction = {
    id: 'ask:q1',
    questions: [
      { id: 'q1', question: 'a', options: [] },
      { id: 'q2', question: 'b', options: [] },
    ],
  }
  assert.deepEqual(answersFrom(interaction, { q1: ['A'], q2: ['B', 'C'] }), {
    kind: 'ask',
    items: [
      { id: 'q1', selected: ['A'] },
      { id: 'q2', selected: ['B', 'C'] },
    ],
  })
})

test('nothing is sent when nothing changed', () => {
  const previous = new Map()
  const entities = entitiesFor([row({ busy: true })], context, TIMEOUT)
  const first = delta(previous, entities)
  assert.equal(first.upsert.length, 1)
  remember(previous, first)

  const again = delta(previous, entities)
  assert.deepEqual(again, { upsert: [], remove: [] }, 'a re-stated entity looks like a change the surface orders by')
})

test('a change is sent, and only the change', () => {
  const previous = new Map()
  const before = entitiesFor([row({ busy: true }), row({ id: 's2', busy: true })], context, TIMEOUT)
  remember(previous, delta(previous, before))

  const after = entitiesFor([row({ busy: true, title: '改名了' }), row({ id: 's2', busy: true })], context, TIMEOUT)
  const change = delta(previous, after)
  assert.equal(change.upsert.length, 1)
  assert.equal(change.upsert[0].key, runKey('s1'))
  assert.equal(change.upsert[0].title, '改名了')
  assert.deepEqual(change.remove, [])
})

test('a session that stops running has its entity removed', () => {
  const previous = new Map()
  remember(previous, delta(previous, entitiesFor([row({ busy: true })], context, TIMEOUT)))
  const change = delta(previous, entitiesFor([row({ busy: false })], context, TIMEOUT))
  assert.deepEqual(change.remove, [runKey('s1')])
  assert.deepEqual(change.upsert, [])
})

test('the kinds are told apart by the interaction id, not by its wording', () => {
  assert.equal(isDeciding(row({ ask: { id: 'q1', questions: [] } })), true)
  assert.equal(isDeciding(row()), false)
  // The ids the adapter builds are what the answer is routed by.
  assert.equal(askKey('s1'), 's1:ask')
  assert.equal(resultKey('s1'), 's1:result')
})
