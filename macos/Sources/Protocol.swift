//
//  Protocol.swift
//  DshNotch
//
//  The provider protocol's vocabulary and its reading of the wire.
//
//  This file is the Swift half of `protocol/v1/index.ts`, and the rules that
//  judge a message live next to it in `ProviderSession.swift`. The two
//  implementations are held together by `protocol/v1/conformance.json`, which
//  replays message sequences against both, so a disagreement is a bug in one of
//  them rather than a difference of opinion.
//
//  Every message is read from raw JSON rather than decoded into typed structs.
//  That is deliberate: a decoder that refuses a field because it does not fit the
//  type becomes a second rule engine, and it answers with its own opinions —
//  `message-invalid` where the contract says `fraction-invalid`. So the wire is
//  read the way a JavaScript object is read, field by field, and the refusals
//  come from the rules alone.
//

import Foundation

/// One behaviour class. The closed set a provider is granted from.
enum CapabilityClass: String, CaseIterable, Sendable {
  case ambient
  case progress
  case activity
  case result
  case awaiting
}

/// How long a provider's entity is meant to live.
enum Lifetime: String, Sendable {
  /// Appears, then is replaced; the provider will not remove it.
  case transient
  /// Lives until the provider removes it or its lease lapses.
  case held
  /// Lives until the user acknowledges it, and is then removed.
  case acknowledged
}

/// The states each class may carry. A state outside its class is rejected.
enum States {
  static func of(_ class: CapabilityClass) -> [String] {
    switch `class` {
    /// A read-only state with no lifecycle of its own.
    case .ambient: return ["present"]
    /// Advance that may be determinate (`fraction`) or not.
    case .progress: return ["running", "paused"]
    /// Present or not; concurrency is the count of entities, not a field.
    case .activity: return ["running"]
    /// A terminal outcome.
    case .result: return ["succeeded", "failed", "interrupted", "abandoned"]
    /// Work is blocked until the user decides. `cancelled` is a question the
    /// provider withdrew; `abandoned` is one whose provider disappeared, which
    /// the user needs told apart — a withdrawn question is answered by doing
    /// nothing, an abandoned one was never answered at all.
    case .awaiting: return ["pending", "answered", "cancelled", "abandoned"]
    }
  }
}

/// One selectable answer.
struct AnswerOption: Equatable, Sendable {
  let label: String
  let description: String?
}

/// One question in an interaction.
struct Question: Equatable, Sendable {
  let id: String
  let question: String
  let header: String?
  let detail: String?
  let options: [AnswerOption]
  let multiSelect: Bool?
}

/// A request for a decision. The provider supplies the question; Notch supplies
/// the presentation, and never accepts markup or animation from the provider.
struct Interaction: Equatable, Sendable {
  let id: String
  let questions: [Question]
}

/// One entity a provider owns, once it has been accepted. Identity is `key`,
/// which must survive updates.
struct Entity: Equatable, Sendable {
  /// Provider-scoped, stable across updates. A new key is an appearance.
  let key: String
  let `class`: CapabilityClass
  let state: String
  let lifetime: Lifetime
  let title: String?
  let body: String?
  /// Present only for `progress`; 0..1, absent means indeterminate.
  let fraction: Double?
  /// Present only for `result`; a result the user has not acknowledged.
  let unread: Bool?
  /// Names of this provider's declared actions that this entity offers.
  let actions: [String]?
  /// Present only for `awaiting`.
  let interaction: Interaction?
}

/// What a provider asks for, and what it undertakes to interpret.
struct Registration: Sendable {
  let protocolVersion: Int
  /// Observed by Notch, not taken from here; this field is only a display hint.
  let displayName: String?
  let requestedClasses: [CapabilityClass]
  /// Action names Notch may invoke, which the provider interprets itself.
  let actions: [String]?
}

/// What Notch grants, and the bounds it will enforce.
struct Grant: Sendable {
  let protocolVersion: Int
  let grantedClasses: [CapabilityClass]
}

/// The protocol version this implementation speaks.
let protocolVersion = 1

/// Every numeric bound the protocol enforces.
///
/// The specs state these as behaviour, so they live here as data rather than as
/// literals scattered through the code. The conformance corpus compares this list
/// against the others, so a bound changed in one implementation and not the other
/// is a failing test rather than a surprise in the field.
enum Limits {
  /// Entities one provider may hold at once.
  static let entitiesPerProvider = 16
  /// Entities the capsule represents individually before aggregating the rest.
  static let capsuleCapacity = 4
  /// Adjudicative entities allowed to wait behind the one on screen.
  static let adjudicativeQueueDepth = 1
  /// Outstanding `awaiting` interactions one provider may hold.
  static let outstandingAwaitingPerProvider = 1
  /// How often a provider renews its lease.
  static let leaseRenewMs = 2000
  /// When an unrenewed lease expires and its entities are removed.
  static let leaseExpiryMs = 6000
  /// Shortest interval between consent prompts for one identity.
  static let consentRateLimitMs = 30_000
  /// How long after a denial before the user may be asked to reconsider.
  static let reRequestFloorMs = 10 * 60_000
  /// Longest title a provider may present.
  static let titleLength = 200
  /// Longest body a provider may present.
  static let bodyLength = 2000
  /// Options one question may offer.
  static let optionsPerQuestion = 12
  /// How long a decision may wait before Notch settles it. Long enough that a
  /// user who steps away still finds the question, bounded because the
  /// adjudicative queue is one deep and a forgotten question would hold it.
  static let interactionDeadlineMs = 30 * 60_000

  /// The bounds as the corpus states them, for the runner to compare.
  static var asJSON: [String: Int] {
    [
      "entitiesPerProvider": entitiesPerProvider,
      "capsuleCapacity": capsuleCapacity,
      "adjudicativeQueueDepth": adjudicativeQueueDepth,
      "outstandingAwaitingPerProvider": outstandingAwaitingPerProvider,
      "leaseRenewMs": leaseRenewMs,
      "leaseExpiryMs": leaseExpiryMs,
      "consentRateLimitMs": consentRateLimitMs,
      "reRequestFloorMs": reRequestFloorMs,
      "titleLength": titleLength,
      "bodyLength": bodyLength,
      "optionsPerQuestion": optionsPerQuestion,
      "interactionDeadlineMs": interactionDeadlineMs,
    ]
  }
}

/// Why Notch refused a message.
///
/// The reason a provider is told is prose for a person; this is the same answer
/// for a program, so a provider can tell "fix the request" from "ask again later"
/// without parsing English. The spelling of each case is part of the wire
/// contract and is matched by the conformance corpus.
enum RefusalCode: String, Sendable, CaseIterable {
  /// No session exists for the identity the transport observed.
  case unknownProvider = "unknown-provider"
  /// The provider has not registered, or its lease lapsed and ended the grant.
  case notRegistered = "not-registered"
  case alreadyRegistered = "already-registered"
  case versionIncompatible = "version-incompatible"
  case noClassesRequested = "no-classes-requested"
  case unknownClass = "unknown-class"
  /// A valid class the provider did not ask for at registration.
  case classNotGranted = "class-not-granted"
  case actionsInvalid = "actions-invalid"
  case actionNameInvalid = "action-name-invalid"
  case actionNameDuplicate = "action-name-duplicate"
  /// An action named by an entity but not declared at registration.
  case actionUndeclared = "action-undeclared"
  case deltaBeforeSnapshot = "delta-before-snapshot"
  case snapshotInvalid = "snapshot-invalid"
  /// Above the entity bound, in a snapshot or an update.
  case entityLimit = "entity-limit"
  /// Above the outstanding-decision bound for one provider.
  case interactionLimit = "interaction-limit"
  /// Above the bound on decisions across all providers.
  case decisionQueueFull = "decision-queue-full"
  case entityInvalid = "entity-invalid"
  case stateInvalid = "state-invalid"
  case lifetimeInvalid = "lifetime-invalid"
  /// A field carried by a class that does not allow it.
  case fieldNotAllowed = "field-not-allowed"
  case titleTooLong = "title-too-long"
  case bodyTooLong = "body-too-long"
  case fractionInvalid = "fraction-invalid"
  case unreadInvalid = "unread-invalid"
  /// An interaction on an entity that is not an awaiting one.
  case notAwaiting = "not-awaiting"
  case interactionInvalid = "interaction-invalid"
  case noSuchEntity = "no-such-entity"
  /// Nothing is outstanding to answer.
  case noDecision = "no-decision"
  /// Something is outstanding, but not what the answer addressed.
  case decisionMismatch = "decision-mismatch"
  case answerInvalid = "answer-invalid"
  /// A question the answer leaves unanswered.
  case answerIncomplete = "answer-incomplete"
  case unknownMessage = "unknown-message"
  /// The message is not shaped like its type.
  case messageInvalid = "message-invalid"
}

/// A refusal: a code for a program, and the reason a person is told.
struct Refused: Error, Equatable, Sendable {
  let code: RefusalCode
  let reason: String

  init(_ code: RefusalCode, _ reason: String) {
    self.code = code
    self.reason = reason
  }
}

/// Whether a message was accepted, or why it was not.
enum Outcome: Equatable, Sendable {
  case accepted
  case refused(Refused)

  var ok: Bool {
    if case .accepted = self { return true }
    return false
  }
}

/// Notch's answer to an interaction.
enum InteractionOutcome: Equatable, Sendable {
  case answered(answers: [String: [String]])
  case cancelled(reason: String)
}

/// What Notch must report to a provider when a decision is settled.
struct Settlement: Equatable, Sendable {
  let key: String
  let interactionID: String
  let outcome: InteractionOutcome
}

/// The outcome of the user answering, which carries what to report back.
enum AnswerOutcome: Sendable {
  case answered(Settlement)
  case refused(Refused)

  var ok: Bool {
    if case .answered = self { return true }
    return false
  }
}

/// Provider → Notch, as it arrived.
///
/// Reading stops at the envelope. Each case carries the object's fields unread,
/// because which fields a message needs and whether they are the right shape is
/// decided where every other rule is decided — in the session. Reading further
/// here would put a second rule engine in the parser, and it would answer with
/// its own opinions: `message-invalid` where the contract says `fraction-invalid`.
///
/// A type this version does not know and a payload it cannot read are kept apart
/// because the contract answers them differently — `unknown-message` for the
/// first, `message-invalid` for the second.
///
/// This is the one type here that is not `Sendable`: JSON arrives as `Any`-typed
/// Foundation containers, and a message is read and applied on the connection
/// that received it rather than passed between them.
enum ProviderMessage {
  /// The fields of whatever type arrived.
  case register([String: Any])
  case snapshot([String: Any])
  case upsert([String: Any])
  case remove([String: Any])
  case interactionRequest([String: Any])
  case interactionCancel([String: Any])
  case ack([String: Any])
  case renew
  case unregister
  /// A type this version does not know.
  case unknownType(type: String)
  /// Not a JSON object with a type this version can read.
  case malformed
}

/// JSON, read the way the rules expect to read it.
///
/// Each reader answers whether the value was there *and* was the thing asked
/// for, because the rules need the difference: a fraction that is absent is an
/// indeterminate progress, and a fraction that is a string is a mistake.
enum Wire {
  static func string(_ value: Any?) -> String? {
    value as? String
  }

  /// A JSON number, never a boolean — `JSONSerialization` bridges both to
  /// `NSNumber`, and a rule that accepts `true` as a number would accept a
  /// fraction no provider meant to send.
  static func number(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
    return value.doubleValue
  }

  static func bool(_ value: Any?) -> Bool? {
    guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
    return value.boolValue
  }

  static func object(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
  }

  static func array(_ value: Any?) -> [Any]? {
    value as? [Any]
  }
}

extension ProviderMessage {
  /// Read one message from the bytes of a single JSON frame.
  /// - Parameter data: one JSON object, as the transport framed it.
  /// - Returns: the message's fields, or a shape this version cannot read.
  static func decode(from data: Data) -> ProviderMessage {
    guard let object = try? JSONSerialization.jsonObject(with: data), let fields = Wire.object(object) else {
      return .malformed
    }
    guard let type = Wire.string(fields["type"]) else { return .malformed }

    switch type {
    case "register": return .register(fields)
    case "snapshot": return .snapshot(fields)
    case "upsert": return .upsert(fields)
    case "remove": return .remove(fields)
    case "interaction.request": return .interactionRequest(fields)
    case "interaction.cancel": return .interactionCancel(fields)
    case "ack": return .ack(fields)
    case "renew": return .renew
    case "unregister": return .unregister
    default: return .unknownType(type: type)
    }
  }
}
