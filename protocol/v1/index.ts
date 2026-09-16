/**
 * The Notch provider protocol, version 1: vocabulary, limits, and message types.
 *
 * This is the only thing a provider and Notch share. It is deliberately
 * provider-agnostic: nothing here names DSH, a browser, or any other source,
 * because Core must be able to serve a provider it has never heard of. The
 * capability classes below are grouped by behaviour pattern rather than by
 * domain, and that grouping is the permission model — a provider is granted
 * classes, and a class is what the user consents to.
 *
 * Behaviour is specified in `openspec/changes/standalone-notch-ecosystem`;
 * this module is that specification made executable. Where the two disagree,
 * the spec is wrong or this is, and the disagreement is the bug.
 * @module protocol/v1
 */

/** Protocol version. An incompatible major is refused, never partially applied. */
export const PROTOCOL_VERSION = 1

/**
 * The behaviour classes, grouped by the pattern they serve.
 *
 * Failure is a state of `result` rather than a class of its own: a failure and
 * a success share a lifecycle and unread semantics and differ only in how
 * Notch draws them, which is Notch's business.
 */
export const CLASSES = ['ambient', 'progress', 'activity', 'result', 'awaiting'] as const

/** One behaviour class. */
export type CapabilityClass = (typeof CLASSES)[number]

/** The tier a class belongs to. `awaiting` is the only class that may ask the user to decide. */
export const TIERS = {
  ambient: 'informational',
  progress: 'informational',
  activity: 'informational',
  result: 'terminal',
  awaiting: 'adjudicative',
} as const satisfies Record<CapabilityClass, string>

/** One behaviour tier. */
export type Tier = (typeof TIERS)[CapabilityClass]

/** The states each class may carry. A state outside its class is rejected. */
export const STATES = {
  /** A read-only state with no lifecycle of its own. */
  ambient: ['present'],
  /** Advance that may be determinate (`fraction`) or not. */
  progress: ['running', 'paused'],
  /** Present or not; concurrency is the count of entities, not a field. */
  activity: ['running'],
  /** A terminal outcome. */
  result: ['succeeded', 'failed', 'interrupted', 'abandoned'],
  /** Work is blocked until the user decides. */
  awaiting: ['pending', 'answered', 'cancelled'],
} as const satisfies Record<CapabilityClass, readonly string[]>

/**
 * Whether a persist entity is removed on its own (transient), waits for the
 * user to acknowledge it, or is held until its provider says otherwise.
 */
export const LIFETIMES = ['transient', 'held', 'acknowledged'] as const

/** One lifetime semantic. */
export type Lifetime = (typeof LIFETIMES)[number]

/**
 * Every numeric bound the protocol enforces.
 *
 * The specs state these as behaviour, so they live here as data rather than as
 * literals scattered through the code: a bound that cannot be read in one place
 * cannot be reviewed, and the OpenSpec record indexes exactly these.
 */
export const LIMITS = {
  /** Entities one provider may hold at once. */
  entitiesPerProvider: 16,
  /** Entities the capsule represents individually before aggregating the rest. */
  capsuleCapacity: 4,
  /** Adjudicative entities allowed to wait behind the one on screen. */
  adjudicativeQueueDepth: 1,
  /** Outstanding `awaiting` interactions one provider may hold. */
  outstandingAwaitingPerProvider: 1,
  /** How often a provider renews its lease. */
  leaseRenewMs: 2_000,
  /** When an unrenewed lease expires and its entities are removed. */
  leaseExpiryMs: 6_000,
  /** Shortest interval between consent prompts for one identity. */
  consentRateLimitMs: 30_000,
  /** How long after a denial before the user may be asked to reconsider. */
  reRequestFloorMs: 10 * 60_000,
  /** Longest title a provider may present. */
  titleLength: 200,
  /** Longest body a provider may present. */
  bodyLength: 2_000,
  /** Options one question may offer. */
  optionsPerQuestion: 12,
} as const

/** One selectable answer. */
export interface Option {
  label: string
  description?: string
}

/** One question in an interaction. */
export interface Question {
  id: string
  question: string
  header?: string
  detail?: string
  options: Option[]
  multiSelect?: boolean
}

/**
 * A request for a decision. The provider supplies the question; Notch supplies
 * the presentation, and never accepts markup or animation from the provider.
 */
export interface Interaction {
  id: string
  questions: Question[]
}

/** One entity a provider owns. Identity is `key`, which must survive updates. */
export interface Entity {
  /** Provider-scoped, stable across updates. A new key is an appearance. */
  key: string
  class: CapabilityClass
  state: string
  lifetime: Lifetime
  title?: string
  body?: string
  /** Present only for `progress`; 0..1, absent means indeterminate. */
  fraction?: number
  /** Present only for `result`; a result the user has not acknowledged. */
  unread?: boolean
  /** Names of this provider's declared actions that this entity offers. */
  actions?: string[]
  /** Present only for `awaiting`. */
  interaction?: Interaction
}

/** What a provider asks for, and what it undertakes to interpret. */
export interface Registration {
  protocolVersion: number
  /** Observed by Notch, not taken from here; this field is only a display hint. */
  displayName?: string
  requestedClasses: CapabilityClass[]
  /** Action names Notch may invoke, which the provider interprets itself. */
  actions?: string[]
}

/** What Notch grants, and the bounds it will enforce. */
export interface Grant {
  protocolVersion: number
  grantedClasses: CapabilityClass[]
  limits: typeof LIMITS
}

/** Notch's answer to an interaction. */
export type InteractionOutcome =
  | { status: 'answered'; answers: Record<string, string[]> }
  | { status: 'cancelled'; reason: string }

/** Provider → Notch. */
export type ProviderMessage =
  | { type: 'register'; registration: Registration }
  | { type: 'snapshot'; entities: Entity[] }
  | { type: 'upsert'; entity: Entity }
  | { type: 'remove'; key: string }
  | { type: 'interaction.request'; key: string; interaction: Interaction }
  | { type: 'interaction.cancel'; key: string; interactionId: string }
  | { type: 'ack'; key: string }
  | { type: 'renew' }
  | { type: 'unregister' }

/** Notch → provider. */
export type NotchMessage =
  | { type: 'granted'; grant: Grant }
  | { type: 'refused'; reason: string }
  | { type: 'snapshot.required' }
  | { type: 'action.invoke'; name: string; key?: string; args?: unknown }
  | { type: 'interaction.settled'; key: string; interactionId: string; outcome: InteractionOutcome }
