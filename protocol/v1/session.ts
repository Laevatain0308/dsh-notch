/**
 * One provider's connection to Notch, and the rules its messages must satisfy.
 *
 * Every rejection here is a rule the OpenSpec record states as behaviour, which
 * is the point of the module: a rule that lives only in prose is a rule that
 * gets re-derived differently in each implementation. Rejections carry a reason
 * because the protocol requires refusals to be reported to the provider rather
 * than silently dropped.
 * @module protocol/v1/session
 */

import {
  CLASSES,
  LIMITS,
  LIFETIMES,
  PROTOCOL_VERSION,
  STATES,
  type CapabilityClass,
  type Entity,
  type Grant,
  type InteractionOutcome,
  type ProviderMessage,
  type Registration,
} from './index.ts'

/** A refusal, with the reason the provider is told. */
export interface Refused {
  ok: false
  reason: string
}

/** An accepted message. */
export interface Accepted {
  ok: true
}

/** The outcome of one message. */
export type Outcome = Accepted | Refused

/** What Notch must report to a provider when a decision is settled. */
export interface Settlement {
  key: string
  interactionId: string
  outcome: InteractionOutcome
}

/** The outcome of the user answering, which carries what to report back. */
export type AnswerOutcome = { ok: true; settlement: Settlement } | Refused

const refused = (reason: string): Refused => ({ ok: false, reason })
const accepted: Accepted = { ok: true }

/** Whether a value is one of the known behaviour classes. */
function isClass(value: unknown): value is CapabilityClass {
  return typeof value === 'string' && (CLASSES as readonly string[]).includes(value)
}

/** Whether a string is present and within a stated limit. */
function withinLimit(value: unknown, limit: number): boolean {
  return typeof value === 'string' && value.length <= limit
}

/**
 * One provider's session.
 *
 * The session owns everything Core needs to judge that provider: what it was
 * granted, whether it has sent the snapshot that begins a subscription, what it
 * currently holds, and when its lease runs out.
 */
export class ProviderSession {
  /** Classes this provider may express. Empty until registration is accepted. */
  granted: CapabilityClass[] = []
  /** Action names the provider undertook to interpret. */
  declaredActions: string[] = []
  /** Entity keys already rejected for exceeding the bound, so refusals are not repeated. */
  private readonly overBound = new Set<string>()
  private readonly held = new Map<string, Entity>()
  /** Keys whose interaction is outstanding; at most one per provider. */
  private readonly outstanding = new Set<string>()
  /** When each outstanding decision must be settled by, keyed by entity. */
  private readonly deadlines = new Map<string, number>()
  private snapshotted = false
  private registered = false
  private leaseExpiresAt = 0

  /**
   * Register the provider.
   * @param registration - what the provider asks for.
   * @param now - current epoch milliseconds.
   * @returns the grant, or a refusal the provider is told.
   */
  register(registration: Registration, now: number): { grant: Grant } | Refused {
    if (registration.protocolVersion !== PROTOCOL_VERSION) {
      return refused(`protocol version ${String(registration.protocolVersion)} is not compatible with ${String(PROTOCOL_VERSION)}`)
    }
    const requested = registration.requestedClasses
    if (!Array.isArray(requested) || requested.length === 0) return refused('no behaviour classes requested')
    for (const value of requested) {
      if (!isClass(value)) return refused(`unknown behaviour class ${JSON.stringify(value)}`)
    }
    const actions = registration.actions ?? []
    if (!actions.every(action => typeof action === 'string' && action.length > 0)) {
      return refused('action names must be non-empty strings')
    }
    if (new Set(actions).size !== actions.length) return refused('action names must be unique')

    this.granted = [...requested]
    this.declaredActions = [...actions]
    this.registered = true
    this.snapshotted = false
    this.leaseExpiresAt = now + LIMITS.leaseExpiryMs
    return {
      grant: { protocolVersion: PROTOCOL_VERSION, grantedClasses: [...this.granted], limits: LIMITS },
    }
  }

  /**
   * Apply one message from the provider.
   * @param message - the message.
   * @param now - current epoch milliseconds, used to extend the lease.
   * @returns whether it was accepted, or why it was refused.
   */
  receive(message: ProviderMessage, now: number): Outcome {
    if (!this.registered) return refused('not registered')
    if (message.type === 'register') return refused('already registered')
    this.leaseExpiresAt = now + LIMITS.leaseExpiryMs

    // Every delta needs the snapshot that opens a subscription. Applying one
    // without it would let a reconnecting provider's partial view overwrite
    // what Core holds.
    const opens = message.type === 'snapshot' || message.type === 'renew' || message.type === 'unregister'
    if (!opens && !this.snapshotted) return refused('delta before snapshot')

    switch (message.type) {
      case 'snapshot': {
        if (!Array.isArray(message.entities)) return refused('snapshot must be a list of entities')
        if (message.entities.length > LIMITS.entitiesPerProvider) {
          return refused(`snapshot holds ${String(message.entities.length)} entities, above the limit of ${String(LIMITS.entitiesPerProvider)}`)
        }
        for (const entity of message.entities) {
          const problem = this.checkEntity(entity)
          if (problem !== undefined) return refused(problem)
        }
        this.held.clear()
        this.outstanding.clear()
        this.deadlines.clear()
        for (const entity of message.entities) this.held.set(entity.key, entity)
        for (const entity of message.entities) {
          if (entity.interaction === undefined) continue
          this.outstanding.add(entity.key)
          this.armDeadline(entity.key, now)
        }
        this.snapshotted = true
        return accepted
      }
      case 'upsert': {
        const problem = this.checkEntity(message.entity)
        if (problem !== undefined) return refused(problem)
        const isNew = !this.held.has(message.entity.key)
        if (isNew && this.held.size >= LIMITS.entitiesPerProvider) {
          this.overBound.add(message.entity.key)
          return refused(`holds ${String(LIMITS.entitiesPerProvider)} entities already, the limit`)
        }
        this.held.set(message.entity.key, message.entity)
        return this.trackInteraction(message.entity, now)
      }
      case 'remove': {
        this.held.delete(message.key)
        this.outstanding.delete(message.key)
        this.deadlines.delete(message.key)
        return accepted
      }
      case 'interaction.request': {
        const held = this.held.get(message.key)
        if (held === undefined) return refused(`no entity ${JSON.stringify(message.key)}`)
        if (held.class !== 'awaiting') return refused('only an awaiting entity may raise an interaction')
        if (this.outstanding.size >= LIMITS.outstandingAwaitingPerProvider) {
          return refused(`already holds ${String(LIMITS.outstandingAwaitingPerProvider)} outstanding interaction`)
        }
        const problem = this.checkInteraction(message.interaction.questions)
        if (problem !== undefined) return refused(problem)
        this.held.set(message.key, { ...held, state: 'pending', interaction: message.interaction })
        this.outstanding.add(message.key)
        this.armDeadline(message.key, now)
        return accepted
      }
      case 'interaction.cancel': {
        this.outstanding.delete(message.key)
        this.deadlines.delete(message.key)
        const held = this.held.get(message.key)
        if (held !== undefined) this.held.set(message.key, { ...held, state: 'cancelled' })
        return accepted
      }
      case 'ack': {
        const held = this.held.get(message.key)
        if (held === undefined) return refused(`no entity ${JSON.stringify(message.key)}`)
        this.held.set(message.key, { ...held, unread: false })
        return accepted
      }
      case 'renew':
        return accepted
      case 'unregister': {
        this.held.clear()
        this.outstanding.clear()
        this.deadlines.clear()
        this.registered = false
        return accepted
      }
      default:
        return refused(`unknown message ${JSON.stringify((message as { type?: unknown }).type)}`)
    }
  }

  /** Whether the lease has lapsed and the held entities must be removed. */
  expired(now: number): boolean {
    return this.leaseExpiresAt <= now
  }

  /** The entities currently held, in insertion order. */
  entities(): Entity[] {
    return [...this.held.values()]
  }

  /**
   * Decisions still waiting on the user, in insertion order.
   *
   * A settled entity keeps its interaction attached — the answer is part of what
   * the provider is told and part of what the user sees — so this is the pending
   * state, not merely the presence of an interaction.
   */
  awaiting(): Entity[] {
    return [...this.held.values()].filter(entity => entity.interaction !== undefined && entity.state === 'pending')
  }

  /** Whether the snapshot that begins a subscription has arrived. */
  get hasSnapshot(): boolean {
    return this.snapshotted
  }

  /** Rule check for one entity, returning the reason it is invalid. */
  private checkEntity(entity: Entity): string | undefined {
    if (typeof entity?.key !== 'string' || entity.key.length === 0) return 'entity key must be a non-empty string'
    if (!isClass(entity.class)) return `unknown behaviour class ${JSON.stringify(entity.class)}`
    if (!this.granted.includes(entity.class)) return `class ${entity.class} was not granted`
    const states: readonly string[] = STATES[entity.class]
    if (!states.includes(entity.state)) return `state ${JSON.stringify(entity.state)} is not a ${entity.class} state`
    if (!(LIFETIMES as readonly string[]).includes(entity.lifetime)) return `unknown lifetime ${JSON.stringify(entity.lifetime)}`
    if (!withinLimit(entity.title ?? '', LIMITS.titleLength)) return `title longer than ${String(LIMITS.titleLength)}`
    if (!withinLimit(entity.body ?? '', LIMITS.bodyLength)) return `body longer than ${String(LIMITS.bodyLength)}`

    // Fields belong to their class: a fraction is progress, unread is a result.
    if (entity.fraction !== undefined) {
      if (entity.class !== 'progress') return 'only a progress entity may carry a fraction'
      if (typeof entity.fraction !== 'number' || !Number.isFinite(entity.fraction) || entity.fraction < 0 || entity.fraction > 1) {
        return 'fraction must be a number between 0 and 1'
      }
    }
    if (entity.unread !== undefined) {
      if (entity.class !== 'result') return 'only a result entity may be unread'
      if (typeof entity.unread !== 'boolean') return 'unread must be a boolean'
    }
    if (entity.interaction !== undefined) {
      if (entity.class !== 'awaiting') return 'only an awaiting entity may carry an interaction'
      if (entity.state !== 'pending') return 'only a pending awaiting entity carries an interaction'
      const problem = this.checkInteraction(entity.interaction.questions)
      if (problem !== undefined) return problem
    }
    if (entity.actions !== undefined) {
      if (!Array.isArray(entity.actions)) return 'actions must be a list'
      for (const action of entity.actions) {
        if (!this.declaredActions.includes(action)) return `action ${JSON.stringify(action)} was not declared at registration`
      }
    }
    return undefined
  }

  /** Rule check for the questions of one interaction. */
  private checkInteraction(questions: unknown): string | undefined {
    if (!Array.isArray(questions) || questions.length === 0) return 'an interaction needs at least one question'
    for (const question of questions as { id?: unknown; question?: unknown; options?: unknown }[]) {
      if (typeof question?.id !== 'string' || question.id.length === 0) return 'question id must be a non-empty string'
      if (typeof question.question !== 'string' || question.question.length === 0) return 'question text must not be empty'
      if (!Array.isArray(question.options) || question.options.length === 0) return 'a question needs at least one option'
      if (question.options.length > LIMITS.optionsPerQuestion) {
        return `a question offers ${String(question.options.length)} options, above the limit of ${String(LIMITS.optionsPerQuestion)}`
      }
    }
    return undefined
  }

  /**
   * Arm a decision's deadline the first time it becomes outstanding.
   *
   * A provider that re-sends the same entity must not be able to push the
   * deadline ahead of itself and hold the adjudicative queue forever, so the
   * deadline is armed once and never extended.
   */
  private armDeadline(key: string, now: number): void {
    if (this.deadlines.has(key)) return
    this.deadlines.set(key, now + LIMITS.interactionDeadlineMs)
  }

  /** Track a newly carried interaction against the outstanding bound. */
  private trackInteraction(entity: Entity, now: number): Outcome {
    if (entity.interaction === undefined) {
      this.outstanding.delete(entity.key)
      this.deadlines.delete(entity.key)
      return accepted
    }
    if (this.outstanding.has(entity.key)) return accepted
    if (this.outstanding.size >= LIMITS.outstandingAwaitingPerProvider) {
      this.held.delete(entity.key)
      return refused(`already holds ${String(LIMITS.outstandingAwaitingPerProvider)} outstanding interaction`)
    }
    this.outstanding.add(entity.key)
    this.armDeadline(entity.key, now)
    return accepted
  }

  /** Mark one decision settled, recording the state the user will see. */
  private settle(key: string, state: string, outcome: InteractionOutcome): Settlement {
    const held = this.held.get(key)
    const interactionId = held?.interaction?.id ?? ''
    if (held !== undefined) this.held.set(key, { ...held, state })
    this.outstanding.delete(key)
    this.deadlines.delete(key)
    return { key, interactionId, outcome }
  }

  /**
   * Remove everything a lapsed lease holds, settling its decisions as abandoned.
   *
   * A user who was about to answer has to be able to tell that their answer did
   * not land, so the decision is settled rather than dropped — and abandoned
   * rather than cancelled, because the provider did not withdraw it, it died.
   * Nothing can be delivered to a provider that is gone; the settlements are
   * returned so Core can hold them until it comes back.
   * @param now - current epoch milliseconds.
   * @returns one settlement per decision that was outstanding.
   */
  expire(now: number): Settlement[] {
    if (!this.expired(now)) return []
    const settlements: Settlement[] = []
    for (const key of [...this.outstanding]) {
      settlements.push(this.settle(key, 'abandoned', { status: 'cancelled', reason: 'the provider stopped responding' }))
    }
    this.held.clear()
    this.deadlines.clear()
    this.registered = false
    return settlements
  }

  /**
   * Settle decisions that have waited past their deadline, so a question nobody
   * answers cannot hold the adjudicative queue forever.
   * @param now - current epoch milliseconds.
   * @returns one settlement per decision that timed out.
   */
  sweep(now: number): Settlement[] {
    const settled: Settlement[] = []
    for (const key of [...this.outstanding]) {
      const deadline = this.deadlines.get(key)
      if (deadline === undefined || deadline > now) continue
      settled.push(this.settle(key, 'cancelled', { status: 'cancelled', reason: 'the decision was not made in time' }))
    }
    return settled
  }

  /**
   * Deliver the user's answer.
   * @param key - the entity holding the decision.
   * @param interactionId - the interaction being answered.
   * @param answers - answer values keyed by question id; every question must appear.
   * @returns the settlement to report, or why the answer was refused.
   */
  answer(key: string, interactionId: string, answers: Record<string, string[]>): AnswerOutcome {
    const held = this.held.get(key)
    if (held === undefined) return refused(`no entity ${JSON.stringify(key)}`)
    if (!this.outstanding.has(key)) return refused('that entity holds no outstanding decision')
    const interaction = held.interaction
    if (interaction === undefined || interaction.id !== interactionId) {
      return refused('the interaction id does not match the outstanding decision')
    }
    if (typeof answers !== 'object' || answers === null) return refused('answers must be an object')
    for (const question of interaction.questions) {
      const given = answers[question.id]
      if (!Array.isArray(given) || given.length === 0) {
        return refused(`no answer given for question ${JSON.stringify(question.id)}`)
      }
    }
    return { ok: true, settlement: this.settle(key, 'answered', { status: 'answered', answers }) }
  }
}
