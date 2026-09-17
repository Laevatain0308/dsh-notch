/**
 * Wire the DSH Host into the provider protocol.
 *
 * The old path — the Host writing a snapshot the overlay polls over HTTP — still
 * runs beside this one, because a rewrite that breaks the surface the user
 * actually uses is not a rewrite worth having. This adapter is fed by the same
 * `Board`, so the two cannot disagree about what DSH is doing: they read the same
 * fold of the same events.
 *
 * @module provider/adapter
 */

import type { Board } from '../board.ts'
import type { NotchRow } from '../types.ts'
import { ADAPTER_CLASSES, NotchProviderClient, endpointPath, type Grant, type Settlement } from './client.ts'
import {
  answersFrom,
  delta,
  entitiesFor,
  isDeciding,
  remember,
  type AdapterContext,
  type ProviderEntity,
  type ProviderQuestion,
} from './entities.ts'

/** What the adapter needs from the Host. */
export interface AdapterOptions {
  board: Board
  /** How long this provider's decisions may wait, in milliseconds. */
  decisionTimeoutMs: number
  /** The actions the adapter declares, so its entities may offer them. */
  actions: string[]
  log: (message: string) => void
}

/**
 * The DSH Host, as a provider.
 *
 * It asks for three classes and no more: progress is something this adapter has
 * never had, and a provider that asks for authority it does not use is asking the
 * user to decide about nothing.
 */
export class DshProvider {
  private readonly client: NotchProviderClient
  private readonly board: Board
  private readonly held = new Map<string, ProviderEntity>()
  private readonly log: (message: string) => void
  private readonly decisionTimeoutMs: number
  private readonly actions: string[]
  private unsubscribe: (() => void) | null = null
  /** Whether the connection has been asked for, which is not the same as made. */
  private connecting = false
  /**
   * Decisions the user has not answered, by the interaction id Notch knows.
   *
   * The questions are kept, not looked up again when the answer arrives: by then
   * the session may have moved on, and the answer belongs to the question that
   * was asked rather than to whatever the session is doing now.
   */
  private readonly outstanding = new Map<string, { sessionId: string; questions: ProviderQuestion[] }>()

  constructor(options: AdapterOptions) {
    this.board = options.board
    this.log = options.log
    this.decisionTimeoutMs = options.decisionTimeoutMs
    this.actions = options.actions
    this.client = new NotchProviderClient(
      {
        path: endpointPath(),
        log: options.log,
        handlers: {
          onGranted: (grant) => { this.onGranted(grant) },
          onRefused: (code, reason) => { this.log(`notch refused (${code}): ${reason}`) },
          onConsentGranted: () => { this.log('the user allowed this program') },
          onConsentDenied: () => { this.log('the user refused this program; it will not be shown') },
          onSettled: (settlement) => { this.onSettled(settlement) },
        },
      },
      {
        displayName: 'DSH Desktop',
        requestedClasses: [...ADAPTER_CLASSES],
        actions: options.actions,
        timeoutMs: options.decisionTimeoutMs,
      }
    )
  }

  /**
   * Begin following the board.
   *
   * Nothing is connected yet. A provider that has nothing to show has no business
   * asking the user for permission to show it, and an idle DSH has nothing: the
   * connection is opened by the first thing worth displaying.
   */
  start(): void {
    this.unsubscribe = this.board.onChange(() => { this.publish() })
    this.publish()
  }

  stop(): void {
    this.unsubscribe?.()
    this.unsubscribe = null
    this.client.stop()
  }

  /** Whether Notch has accepted this provider, which is worth logging once. */
  private onGranted(grant: Grant): void {
    this.log(`notch granted ${grant.grantedClasses.join(', ')}`)
    // The grant is what makes a message sendable, so what the board says now is
    // what this provider states first.
    this.publish()
  }

  /**
   * Tell Notch what DSH is doing, as far as it has changed.
   *
   * A snapshot is sent by `onGranted` rather than here: until the grant arrives
   * there is nothing that may be sent, and the state at that moment is whatever
   * the board says then, not whatever it said when the connection opened.
   */
  private publish(): void {
    const rows = this.rows()

    // The first thing worth showing is what opens the connection, which is also
    // what raises the user's decision about this program.
    if (!this.client.isGranted) {
      if (this.connecting || rows.length === 0) return
      this.connecting = true
      this.log('dsh has something to show; connecting to notch')
      this.client.start()
      return
    }

    const context: AdapterContext = {
      // One decision may be outstanding at a time, so the rest are counted
      // rather than raised: the number is what tells the user that answering
      // this one uncovers another.
      queuedDecisions: Math.max(0, rows.filter(isDeciding).length - 1),
      actions: this.actions,
    }
    const entities = entitiesFor(rows, context, this.decisionTimeoutMs)
    this.rememberDecisions(entities)

    if (this.held.size === 0 && this.client.held().length === 0) {
      this.client.snapshot(entities)
      for (const entity of entities) this.held.set(entity.key, entity)
      return
    }
    const change = delta(this.held, entities)
    remember(this.held, change)
    this.client.apply(change.upsert, change.remove)
  }

  private rows(): NotchRow[] {
    return this.board.snapshot('adapter').rows
  }

  /** Keep the questions of every decision that is on screen, so an answer can be read. */
  private rememberDecisions(entities: ProviderEntity[]): void {
    const present = new Set<string>()
    for (const entity of entities) {
      const interaction = entity.interaction
      if (interaction === undefined) continue
      present.add(interaction.id)
      if (this.outstanding.has(interaction.id)) continue
      this.outstanding.set(interaction.id, {
        sessionId: entity.key.replace(/:ask$/, ''),
        questions: interaction.questions,
      })
    }
    for (const id of [...this.outstanding.keys()]) {
      if (!present.has(id)) this.outstanding.delete(id)
    }
  }

  /**
   * Deliver the user's answer to DSH.
   *
   * The answer is applied to the board, which is the same path the HTTP surface
   * uses, so a decision answered in Notch and a decision answered in DSH are the
   * same decision arriving the same way.
   */
  private onSettled(settlement: Settlement): void {
    const outstanding = this.outstanding.get(settlement.interactionId)
    this.outstanding.delete(settlement.interactionId)
    if (settlement.outcome.status === 'cancelled') {
      this.log(`a decision was ${settlement.outcome.reason}`)
      return
    }

    const [kind, id] = settlement.interactionId.split(':', 2)
    if (id === undefined) return
    const answers = settlement.outcome.answers

    if (kind === 'approval') {
      const outcome = answers[id]?.[0] === '允许' ? 'allowed-once' : 'rejected'
      if (!this.board.decideApproval(id, outcome)) {
        this.log(`the approval ${id} was no longer waiting`)
      }
      return
    }

    const questions = outstanding?.questions ?? []
    const translated = answersFrom({ id: settlement.interactionId, questions }, answers)
    const items = 'items' in translated && translated.items !== undefined ? translated.items : []
    if (!this.board.answerAsk(id, items)) {
      this.log(`the question ${id} was no longer waiting`)
    }
  }
}
