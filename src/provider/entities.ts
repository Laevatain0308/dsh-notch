/**
 * DSH's sessions, expressed as behaviour classes.
 *
 * This is the adapter's whole job, and it is a pure function on purpose: what a
 * session *is* in DSH and what it *shows* in Notch are different questions, and
 * the second one should be readable without a socket, a lease or a timer in the
 * way.
 *
 * The mapping is not one row to one entity. A session that is running while an
 * earlier turn's result is still unread is two things at once — work in progress
 * and something to read — and the classes exist so that the surface can show them
 * as what they are: activity aggregates with every other provider's activity,
 * while a result is one thing the user reads and acknowledges.
 *
 * @module provider/entities
 */

import type { NotchRow } from '../types.ts'

/** One entity, as the protocol states it. */
export interface ProviderEntity {
  key: string
  class: 'ambient' | 'progress' | 'activity' | 'result' | 'awaiting'
  state: string
  lifetime: 'transient' | 'held' | 'acknowledged'
  title?: string
  body?: string
  fraction?: number
  unread?: boolean
  actions?: string[]
  interaction?: { id: string; questions: ProviderQuestion[]; timeoutMs?: number }
}

/** One question, as the protocol states it. */
export interface ProviderQuestion {
  id: string
  question: string
  header?: string
  detail?: string
  options: { label: string; description?: string }[]
  multiSelect?: boolean
}

/** What the adapter needs to know besides the rows. */
export interface AdapterContext {
  /** How many sessions are waiting for the user beyond the one being asked. */
  queuedDecisions: number
  /** Action names this provider declares, which its entities may offer. */
  actions: string[]
}

/**
 * The keys the adapter owns, derived from a session id.
 *
 * A session is two entities when it is both running and unread, so the key is
 * not the session id alone: identity has to survive an update, and a result that
 * inherited a running session's key would look like the same thing changing
 * class rather than two different things.
 */
export const runKey = (sessionId: string): string => `${sessionId}:run`
export const resultKey = (sessionId: string): string => `${sessionId}:result`
export const askKey = (sessionId: string): string => `${sessionId}:ask`

/** The question an approval becomes: the tool it wants to run, and the two answers. */
function approvalInteraction(row: NotchRow, timeoutMs: number): ProviderEntity['interaction'] {
  const approval = row.approval
  if (approval === undefined) return undefined
  return {
    id: `approval:${approval.id}`,
    timeoutMs,
    questions: [
      {
        id: approval.id,
        header: '工具许可',
        question: `允许运行 ${approval.toolName}？`,
        ...(approval.reason === undefined ? {} : { detail: approval.reason }),
        options: [{ label: '允许' }, { label: '拒绝' }],
      },
    ],
  }
}

/** The questions a session is asking, as the protocol states them. */
function askInteraction(row: NotchRow, timeoutMs: number): ProviderEntity['interaction'] {
  const ask = row.ask
  if (ask === undefined) return undefined
  return {
    id: `ask:${ask.id}`,
    timeoutMs,
    questions: ask.questions.map((question) => ({
      id: question.id,
      question: question.question,
      ...(question.header === undefined ? {} : { header: question.header }),
      ...(question.detail === undefined ? {} : { detail: question.detail }),
      options: question.options ?? [],
      ...(question.multiSelect === undefined ? {} : { multiSelect: question.multiSelect }),
    })),
  }
}

/** The decision a row is waiting on, if it is waiting on one. */
function decision(row: NotchRow, timeoutMs: number): ProviderEntity['interaction'] {
  return approvalInteraction(row, timeoutMs) ?? askInteraction(row, timeoutMs)
}

/** Whether a row is waiting for the user to decide something. */
export function isDeciding(row: NotchRow): boolean {
  return row.approval !== undefined || row.ask !== undefined
}

/**
 * The entities one session should be showing.
 *
 * A row that is deciding shows the decision and nothing else: the user is being
 * asked something, and leaving the running lamp up beside the question would say
 * the work is proceeding when it is in fact waiting on them.
 */
export function entitiesForRow(row: NotchRow, context: AdapterContext, timeoutMs: number): ProviderEntity[] {
  const title = row.title
  const deciding = decision(row, timeoutMs)
  if (deciding !== undefined) {
    // Only one decision can be outstanding at a time, so the ones behind it are
    // counted rather than raised — the count is the honest thing to show, since
    // the alternative is silence about a session that is stuck.
    const waiting = context.queuedDecisions
    return [
      {
        key: askKey(row.id),
        class: 'awaiting',
        state: 'pending',
        lifetime: 'held',
        title,
        ...(waiting === 0 ? {} : { body: `还有 ${String(waiting)} 个会话在等待处理` }),
        interaction: deciding,
      },
    ]
  }

  const entities: ProviderEntity[] = []
  if (row.busy) {
    entities.push({
      key: runKey(row.id),
      class: 'activity',
      state: 'running',
      lifetime: 'held',
      title,
      actions: context.actions,
    })
  }
  if (row.unread && row.lastTurn !== undefined) {
    entities.push({
      key: resultKey(row.id),
      class: 'result',
      state: row.lastTurn.failed ? 'failed' : 'succeeded',
      lifetime: 'held',
      title,
      unread: true,
      actions: context.actions,
    })
  }
  return entities
}

/**
 * The entities every row should be showing, in a stable order.
 *
 * Rows arrive sorted by DSH's own idea of importance, but the surface does its
 * own ordering, so this only has to be deterministic: the same rows must produce
 * the same list, or every poll would look like a change.
 */
export function entitiesFor(rows: NotchRow[], context: AdapterContext, timeoutMs: number): ProviderEntity[] {
  const entities: ProviderEntity[] = []
  for (const row of rows) entities.push(...entitiesForRow(row, context, timeoutMs))
  return entities.sort((left, right) => (left.key < right.key ? -1 : 1))
}

/** What changed between two states of the same sessions. */
export interface EntityDelta {
  upsert: ProviderEntity[]
  remove: string[]
}

/** Whether two entities say the same thing, field for field. */
function same(left: ProviderEntity, right: ProviderEntity): boolean {
  return JSON.stringify(left) === JSON.stringify(right)
}

/**
 * The difference between what was sent and what should be.
 *
 * Sending only what changed is not an optimisation here: every message is a
 * lease renewal and a state statement, and a provider that re-states everything
 * on every poll is a provider whose entities look like they keep changing, which
 * is what the surface orders by.
 */
export function delta(previous: Map<string, ProviderEntity>, next: ProviderEntity[]): EntityDelta {
  const upsert: ProviderEntity[] = []
  const wanted = new Set<string>()
  for (const entity of next) {
    wanted.add(entity.key)
    const before = previous.get(entity.key)
    if (before === undefined || !same(before, entity)) upsert.push(entity)
  }
  const remove = [...previous.keys()].filter((key) => !wanted.has(key))
  return { upsert, remove }
}

/** Remember what has been sent, so the next delta can be computed. */
export function remember(previous: Map<string, ProviderEntity>, change: EntityDelta): void {
  for (const entity of change.upsert) previous.set(entity.key, entity)
  for (const key of change.remove) previous.delete(key)
}

/**
 * The answer the user gave, as DSH wants it.
 *
 * A refusal is not the absence of an answer: DSH has to be told the user said no,
 * or the session waits for a decision that has already been made.
 */
export function answersFrom(interaction: { id: string; questions: ProviderQuestion[] }, answers: Record<string, string[]>): {
  kind: 'approval' | 'ask'
  outcome?: 'allowed-once' | 'rejected'
  items?: { id: string; selected: string[] }[]
} {
  // The kind is carried by the interaction's id rather than read back out of a
  // question's wording: a label is what the user reads, and matching on one is a
  // behaviour that changes when a translation does.
  if (interaction.id.startsWith('approval:')) {
    const first = interaction.questions[0]
    const selected = first === undefined ? [] : answers[first.id] ?? []
    return { kind: 'approval', outcome: selected.includes('允许') ? 'allowed-once' : 'rejected' }
  }
  return {
    kind: 'ask',
    items: interaction.questions.map((question) => ({
      id: question.id,
      selected: answers[question.id] ?? [],
    })),
  }
}
