/**
 * Replay the conformance corpus against the TypeScript implementation.
 *
 * The corpus is the contract: it is written as wire-level messages and
 * observable outcomes, not as calls into this module's internals, so a second
 * implementation in another language can be held to exactly the same file. This
 * runner therefore has two jobs — to prove the corpus is consistent, and to
 * prove the implementation still satisfies it.
 *
 * A failure here means one of the two is wrong, and the interesting work is
 * deciding which. That is the point: it is the only place where the rules are
 * written down in a form two implementations must agree on.
 */

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { LIMITS, PROTOCOL_VERSION } from '../protocol/v1/index.ts'
import { NotchCore } from '../protocol/v1/core.ts'

const corpus = JSON.parse(readFileSync(fileURLToPath(new URL('../protocol/v1/conformance.json', import.meta.url)), 'utf8'))

/** Sort by a key, so a corpus expectation cannot depend on iteration order. */
const sorted = (items, key) => [...items].sort((left, right) => (key(left) < key(right) ? -1 : 1))

/** Only the fields a corpus expectation states are compared. */
function project(actual, expected) {
  if (Array.isArray(expected)) return expected.map((item, index) => project(actual[index], item))
  if (expected !== null && typeof expected === 'object') {
    return Object.fromEntries(Object.entries(expected).map(([key, value]) => [key, project(actual?.[key], value)]))
  }
  return actual
}

/** The observable state of one entity: what it is, not what it carries. */
function observable(entity) {
  const shown = { key: entity.key, class: entity.class, state: entity.state }
  if (entity.unread !== undefined) shown.unread = entity.unread
  return shown
}

/** A settlement as the corpus states it, without the prose the user is told. */
function settlement(entry) {
  const outcome = { status: entry.settlement.outcome.status }
  if (entry.settlement.outcome.answers !== undefined) outcome.answers = entry.settlement.outcome.answers
  return { provider: entry.provider, key: entry.settlement.key, interactionId: entry.settlement.interactionId, outcome }
}

/** A decision as the corpus states it, without the question text. */
function decision(shown) {
  if (shown === null) return null
  return { provider: shown.provider, key: shown.key, interactionId: shown.interaction.id }
}

test('the corpus states the protocol version and every limit', () => {
  assert.equal(corpus.protocolVersion, PROTOCOL_VERSION)
  assert.deepEqual(corpus.limits, LIMITS)
  assert.equal(corpus.clock.start, 1000000)
  assert.ok(corpus.cases.length > 0)
})

for (const entry of corpus.cases) {
  test(`conformance: ${entry.name}`, () => {
    const notch = new NotchCore()
    for (const [index, step] of entry.steps.entries()) {
      const where = `step ${String(index + 1)} (${step.op})`
      switch (step.op) {
        case 'connect':
          notch.connect(step.provider, step.displayName)
          break
        case 'receive': {
          const outcome = notch.receive(step.provider, step.message, step.at)
          assert.equal(outcome.ok, step.expect.ok, `${where}: ${outcome.ok ? '' : outcome.reason}`)
          if (!step.expect.ok) assert.equal(outcome.code, step.expect.code)
          if (step.expect.grant !== undefined) {
            assert.deepEqual(project(outcome.grant, step.expect.grant), step.expect.grant)
          }
          break
        }
        case 'tick': {
          const settled = sorted(notch.tick(step.at).map(settlement), item => `${item.provider}/${item.key}`)
          assert.deepEqual(settled, step.expect)
          break
        }
        case 'disconnect': {
          const settled = sorted(notch.disconnect(step.provider).map(settlement), item => `${item.provider}/${item.key}`)
          assert.deepEqual(settled, step.expect)
          break
        }
        case 'answer': {
          const outcome = notch.answer(step.interactionId, step.answers)
          assert.equal(outcome.ok, step.expect.ok, `${where}: ${outcome.ok ? '' : outcome.reason}`)
          if (!step.expect.ok) assert.equal(outcome.code, step.expect.code)
          if (step.expect.settlement !== undefined) {
            const settled = {
              key: outcome.settlement.key,
              interactionId: outcome.settlement.interactionId,
              outcome: outcome.settlement.outcome,
            }
            assert.deepEqual(settled, step.expect.settlement)
          }
          break
        }
        case 'decision': {
          const { expanded, waiting } = notch.adjudication()
          assert.deepEqual({ expanded: decision(expanded), waiting: decision(waiting) }, step.expect)
          break
        }
        case 'entities':
          assert.deepEqual(notch.held(step.provider).map(observable), step.expect, where)
          break
        case 'providers': {
          const records = sorted(notch.providers(), record => record.id)
          assert.deepEqual(records, step.expect)
          break
        }
        default:
          assert.fail(`${where}: unknown operation ${JSON.stringify(step.op)}`)
      }
    }
  })
}
