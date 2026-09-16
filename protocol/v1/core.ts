/**
 * Core: everything Notch owns across all providers at once.
 *
 * A `ProviderSession` judges one provider against the rules its messages must
 * satisfy. Core owns the rules that no single provider can: how many providers
 * exist, which one holds the adjudicative queue, and what the user is being
 * asked right now. Those limits are global by definition, so a provider cannot
 * be allowed to enforce them on itself — and a rule that spans providers is
 * also the rule an attacker would exploit, which is why refusals here are
 * reported rather than dropped.
 *
 * Nothing in this module knows what a provider is for. An identity arrives from
 * the transport, entities arrive as behaviour classes, and the only thing Core
 * does with them is bound them, order them, and hand them to the user.
 * @module protocol/v1/core
 */

import {
  LIMITS,
  type CapabilityClass,
  type Grant,
  type Interaction,
  type ProviderMessage,
} from './index.ts'
import { ProviderSession, type AnswerOutcome, type Refused, type Settlement } from './session.ts'

/**
 * A provider's identity, derived from the transport.
 *
 * Core never reads identity out of a provider's own messages: a provider that
 * could name itself could claim another's grants.
 */
export type ProviderId = string

/** A decision occupying the adjudicative queue. */
export interface Decision {
  provider: ProviderId
  key: string
  title?: string
  interaction: Interaction
}

/** What the user is being asked, and what waits behind it. */
export interface Adjudication {
  /** The decision on screen, which the user can answer. */
  expanded: Decision | null
  /** The one decision queued behind it, which the user cannot answer yet. */
  waiting: Decision | null
}

/** What one provider message produced. */
export type CoreOutcome = { ok: true; grant?: Grant } | Refused

/** A settlement, named by the provider it must be reported to. */
export interface Settled {
  provider: ProviderId
  settlement: Settlement
}

/** One registered provider, as the management surface lists it. */
export interface ProviderRecord {
  id: ProviderId
  displayName?: string
  classes: CapabilityClass[]
  entities: number
}

/** One seat in the adjudicative queue. */
interface Seat {
  provider: ProviderId
  key: string
}

const refused = (reason: string): Refused => ({ ok: false, reason })

/**
 * The adjudicative queue is one on screen plus the depth stated in the limits.
 *
 * Beyond that a decision is refused rather than queued, because a queue nobody
 * can see is indistinguishable from a provider being ignored, and the provider
 * is entitled to know it must ask again later.
 */
const QUEUE_CAPACITY = 1 + LIMITS.adjudicativeQueueDepth

/**
 * Core: the owner of every session, and of the limits that span them.
 */
export class NotchCore {
  private readonly sessions = new Map<ProviderId, ProviderSession>()
  private readonly displayNames = new Map<ProviderId, string>()
  /** The adjudicative queue, in arrival order. Index 0 is the decision on screen. */
  private readonly queue: Seat[] = []

  /**
   * Open a session for a provider identity.
   *
   * Called when the transport accepts a connection, before any message arrives:
   * identity comes from the peer, so the connection *is* the session. A second
   * connection from the same identity keeps the session it already had, so a
   * provider that reconnects mid-decision does not lose its place in the queue
   * or hand the user a duplicate of a question they are already reading.
   * @param provider - the identity the transport observed.
   * @param displayName - a hint for the user interface, never used for identity.
   */
  connect(provider: ProviderId, displayName?: string): void {
    if (!this.sessions.has(provider)) this.sessions.set(provider, new ProviderSession())
    if (displayName !== undefined) this.displayNames.set(provider, displayName)
  }

  /**
   * Apply one message from a connected provider.
   * @param provider - the identity the transport observed.
   * @param message - the message.
   * @param now - current epoch milliseconds.
   * @returns whether it was accepted, what the provider must be told, and why.
   */
  receive(provider: ProviderId, message: ProviderMessage, now: number): CoreOutcome {
    const session = this.sessions.get(provider)
    if (session === undefined) return refused(`unknown provider ${JSON.stringify(provider)}`)

    if (message.type === 'register') {
      const outcome = session.register(message.registration, now)
      if ('reason' in outcome) return outcome
      if (message.registration.displayName !== undefined) {
        this.displayNames.set(provider, message.registration.displayName)
      }
      return { ok: true, grant: outcome.grant }
    }

    // The adjudicative queue is the one bound a provider must not be able to
    // grant itself, so admission happens here, before the session applies it.
    const admission = this.admit(provider, message)
    if (admission !== undefined) return admission

    const outcome = session.receive(message, now)
    // A message the session refused must not leave a seat behind, and one that
    // settled a decision must give its seat up.
    this.reconcile(provider)
    return outcome
  }

  /**
   * Deliver the user's answer to the decision it belongs to.
   *
   * The user answers what they are looking at, not a provider, so the
   * interaction id is the whole address — and an id that is not on screen is
   * refused rather than searched for, so an answer can never land on a question
   * the user has not been shown.
   * @param interactionId - the id of the decision on screen.
   * @param answers - the chosen option labels, keyed by question id.
   * @returns the settlement to report, or why the answer was refused.
   */
  answer(interactionId: string, answers: Record<string, string[]>): AnswerOutcome {
    const seat = this.queue[0]
    if (seat === undefined) return refused('nothing is awaiting a decision')
    const session = this.sessions.get(seat.provider)
    const decision = session === undefined ? null : this.decisionFor(seat, session)
    if (decision === null || decision.interaction.id !== interactionId) {
      return refused(`no outstanding decision ${JSON.stringify(interactionId)}`)
    }
    const outcome = session.answer(seat.key, interactionId, answers)
    if (outcome.ok) this.reconcile(seat.provider)
    return outcome
  }

  /**
   * Advance the clock: expiring leases and settling decisions that timed out.
   *
   * Called on a timer rather than in response to a message, because both things
   * it does are consequences of a provider *not* acting.
   * @param now - current epoch milliseconds.
   * @returns what must be reported back, per provider.
   */
  tick(now: number): Settled[] {
    const settled: Settled[] = []
    for (const [provider, session] of this.sessions) {
      // A lapsed lease takes everything the provider held, so its seats go with
      // it; a live provider that merely left a question too long keeps its
      // other entities and only gives up the seat for that question.
      const outcomes = session.expired(now) ? session.expire(now) : session.sweep(now)
      for (const settlement of outcomes) settled.push({ provider, settlement })
      if (outcomes.length > 0) this.reconcile(provider)
    }
    return settled
  }

  /**
   * Drop a provider whose connection ended.
   *
   * Nothing can be delivered to a provider that is gone, so the settlements are
   * returned rather than sent: Core records that the user's answer, or their
   * unanswered question, ended this way.
   * @param provider - the identity whose connection ended.
   * @returns the decisions that were left outstanding.
   */
  disconnect(provider: ProviderId): Settled[] {
    const session = this.sessions.get(provider)
    if (session === undefined) return []
    const settled: Settled[] = []
    // Every lease has lapsed by now, so everything the provider held is settled
    // as abandoned: a connection that ended did not withdraw its questions.
    for (const settlement of session.expire(Number.POSITIVE_INFINITY)) {
      settled.push({ provider, settlement })
    }
    this.sessions.delete(provider)
    this.displayNames.delete(provider)
    this.release(provider)
    return settled
  }

  /** What the user is being asked, and what waits behind it. */
  adjudication(): Adjudication {
    const decision = (index: number): Decision | null => {
      const seat = this.queue[index]
      if (seat === undefined) return null
      const session = this.sessions.get(seat.provider)
      return session === undefined ? null : this.decisionFor(seat, session)
    }
    return { expanded: decision(0), waiting: decision(1) }
  }

  /** The providers currently registered, for the management surface. */
  providers(): ProviderRecord[] {
    const records: ProviderRecord[] = []
    for (const [id, session] of this.sessions) {
      if (!session.isRegistered) continue
      const record: ProviderRecord = { id, classes: [...session.granted], entities: session.entities().length }
      const displayName = this.displayNames.get(id)
      if (displayName !== undefined) record.displayName = displayName
      records.push(record)
    }
    return records
  }

  /**
   * Take a seat in the adjudicative queue, if the message asks for one.
   *
   * Admission is decided before the session applies the message so that a
   * refused decision leaves nothing behind: a provider that is told "no" must
   * not also find that the user is looking at it.
   * @returns a refusal, or `undefined` when the message may proceed.
   */
  private admit(provider: ProviderId, message: ProviderMessage): Refused | undefined {
    for (const asked of seatsAskedFor(message)) {
      if (this.seated(provider, asked)) continue
      if (this.queue.length >= QUEUE_CAPACITY) {
        return refused(`a decision is already on screen and ${String(LIMITS.adjudicativeQueueDepth)} waits behind it`)
      }
      this.queue.push({ provider, key: asked })
    }
    return undefined
  }

  /** Whether this provider already holds a seat for this entity. */
  private seated(provider: ProviderId, key: string): boolean {
    return this.queue.some(seat => seat.provider === provider && seat.key === key)
  }

  /** Give up every seat one provider holds. */
  private release(provider: ProviderId): void {
    for (let index = this.queue.length - 1; index >= 0; index--) {
      if (this.queue[index]?.provider === provider) this.queue.splice(index, 1)
    }
  }

  /**
   * Drop the seats whose decisions are no longer outstanding.
   *
   * Reconciling against the session rather than tracking settlements keeps one
   * source of truth: however a decision ended — answered, withdrawn, abandoned,
   * timed out, or removed with its entity — the session stops reporting it as
   * pending, and the seat follows.
   */
  private reconcile(provider: ProviderId): void {
    const session = this.sessions.get(provider)
    if (session === undefined) return
    const pending = new Set(session.awaiting().map(entity => entity.key))
    for (let index = this.queue.length - 1; index >= 0; index--) {
      const seat = this.queue[index]
      if (seat === undefined || seat.provider !== provider) continue
      if (!pending.has(seat.key)) this.queue.splice(index, 1)
    }
  }

  /** The decision one seat stands for, or null if the session no longer holds it. */
  private decisionFor(seat: Seat, session: ProviderSession): Decision | null {
    const entity = session.entities().find(held => held.key === seat.key)
    if (entity?.interaction === undefined) return null
    const decision: Decision = { provider: seat.provider, key: seat.key, interaction: entity.interaction }
    if (entity.title !== undefined) decision.title = entity.title
    return decision
  }
}

/**
 * The entity keys one message asks to put in the adjudicative queue.
 *
 * A snapshot asks for every decision it carries, which is how a provider that
 * restarts announces a question the user was already reading.
 * @param message - the provider message.
 * @returns the keys the message asks a seat for, in the order it names them.
 */
function seatsAskedFor(message: ProviderMessage): string[] {
  switch (message.type) {
    case 'snapshot':
      return message.entities.filter(entity => entity.interaction !== undefined).map(entity => entity.key)
    case 'upsert':
      return message.entity.interaction === undefined ? [] : [message.entity.key]
    case 'interaction.request':
      return [message.key]
    default:
      return []
  }
}
