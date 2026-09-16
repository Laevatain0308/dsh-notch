//
//  NotchCore.swift
//  DshNotch
//
//  Everything Notch owns across all providers at once.
//
//  This file is the Swift half of `protocol/v1/core.ts`. A `ProviderSession`
//  judges one provider against the rules its messages must satisfy; Core owns the
//  rules that no single provider can: how many providers exist, which one holds
//  the adjudicative queue, and what the user is being asked right now. Those
//  limits are global by definition, so a provider cannot be allowed to enforce
//  them on itself — and a rule that spans providers is also the rule an attacker
//  would exploit, which is why refusals here are reported rather than dropped.
//
//  Nothing here knows what a provider is for. An identity arrives from the
//  transport, entities arrive as behaviour classes, and the only thing Core does
//  with them is bound them, order them, and hand them to the user.
//

import Foundation

/// A provider's identity, derived from the transport.
///
/// Core never reads identity out of a provider's own messages: a provider that
/// could name itself could claim another's grants.
typealias ProviderID = String

/// A decision occupying the adjudicative queue.
struct Decision: Equatable, Sendable {
  let provider: ProviderID
  let key: String
  let title: String?
  let interaction: Interaction

  static func == (left: Decision, right: Decision) -> Bool {
    left.provider == right.provider && left.key == right.key && left.interaction.id == right.interaction.id
  }
}

/// What the user is being asked, and what waits behind it.
struct Adjudication: Equatable, Sendable {
  /// The decision on screen, which the user can answer.
  let expanded: Decision?
  /// The one decision queued behind it, which the user cannot answer yet.
  let waiting: Decision?
}

/// What one provider message produced.
enum CoreOutcome: Sendable {
  case accepted(grant: Grant?)
  case refused(Refused)

  var ok: Bool {
    if case .accepted = self { return true }
    return false
  }
}

/// A settlement, named by the provider it must be reported to.
struct Settled: Equatable, Sendable {
  let provider: ProviderID
  let settlement: Settlement
}

/// One registered provider, as the management surface lists it.
struct ProviderRecord: Equatable, Sendable {
  let id: ProviderID
  let displayName: String?
  let classes: [CapabilityClass]
  let entities: Int
}

/// One seat in the adjudicative queue.
private struct Seat: Equatable {
  let provider: ProviderID
  let key: String
}

/// The adjudicative queue is one on screen plus the depth stated in the limits.
///
/// Beyond that a decision is refused rather than queued, because a queue nobody
/// can see is indistinguishable from a provider being ignored, and the provider
/// is entitled to know it must ask again later.
private let queueCapacity = 1 + Limits.adjudicativeQueueDepth

/// Core: the owner of every session, and of the limits that span them.
final class NotchCore {
  private var sessions: [ProviderID: ProviderSession] = [:]
  private var displayNames: [ProviderID: String] = [:]
  /// The adjudicative queue, in arrival order. Index 0 is the decision on screen.
  private var queue: [Seat] = []

  /// Open a session for a provider identity.
  ///
  /// Called when the transport accepts a connection, before any message arrives:
  /// identity comes from the peer, so the connection *is* the session. A second
  /// connection from the same identity keeps the session it already had, so a
  /// provider that reconnects mid-decision does not lose its place in the queue
  /// or hand the user a duplicate of a question they are already reading.
  /// - Parameters:
  ///   - provider: the identity the transport observed.
  ///   - displayName: a hint for the user interface, never used for identity.
  func connect(_ provider: ProviderID, displayName: String? = nil) {
    if sessions[provider] == nil { sessions[provider] = ProviderSession() }
    if let displayName { displayNames[provider] = displayName }
  }

  /// Apply one message from a connected provider.
  /// - Parameters:
  ///   - provider: the identity the transport observed.
  ///   - message: the message.
  ///   - now: current epoch milliseconds.
  /// - Returns: whether it was accepted, what the provider must be told, and why.
  func receive(_ provider: ProviderID, _ message: ProviderMessage, now: Int) -> CoreOutcome {
    guard let session = sessions[provider] else {
      return .refused(Refused(.unknownProvider, "unknown provider \(quoted(provider))"))
    }

    // A provider registering again is not the same as one talking out of turn:
    // its lease may have lapsed, and registering is the only way back.
    if case .register(let fields) = message {
      switch session.register(fields, now: now) {
      case .failure(let refusal):
        return .refused(refusal)
      case .success(let grant):
        if let name = Wire.string(Wire.object(fields["registration"])?["displayName"]) {
          displayNames[provider] = name
        }
        return .accepted(grant: grant)
      }
    }

    // Order matters twice over. The message is judged on its own terms before
    // the queue is consulted, so a provider is never told the queue is full when
    // the real problem is the message. And the queue is consulted before the
    // session applies anything, so a refused decision leaves nothing behind: a
    // provider that is told "no" must not also find the user looking at it.
    if let invalid = session.check(message) { return .refused(invalid) }
    if let full = admit(provider, message) { return .refused(full) }

    let outcome = session.receive(message, now: now)
    // A message the session refused must not leave a seat behind, and one that
    // settled a decision must give its seat up.
    reconcile(provider)
    return outcome.ok ? .accepted(grant: nil) : .refused(refusalOf(outcome))
  }

  /// Deliver the user's answer to the decision it belongs to.
  ///
  /// The user answers what they are looking at, not a provider, so the
  /// interaction id is the whole address — and an id that is not on screen is
  /// refused rather than searched for, so an answer can never land on a question
  /// the user has not been shown.
  /// - Parameters:
  ///   - interactionID: the id of the decision on screen.
  ///   - answers: the chosen option labels, keyed by question id.
  /// - Returns: the settlement to report, or why the answer was refused.
  func answer(interactionID: String, answers: [String: [String]]) -> AnswerOutcome {
    guard let seat = queue.first, let session = sessions[seat.provider] else {
      return .refused(Refused(.noDecision, "nothing is awaiting a decision"))
    }
    guard let decision = decision(for: seat, in: session), decision.interaction.id == interactionID else {
      return .refused(Refused(.decisionMismatch, "no outstanding decision \(quoted(interactionID))"))
    }
    let outcome = session.answer(key: seat.key, interactionID: interactionID, answers: answers)
    if outcome.ok { reconcile(seat.provider) }
    return outcome
  }

  /// Advance the clock: expiring leases and settling decisions that timed out.
  ///
  /// Called on a timer rather than in response to a message, because both things
  /// it does are consequences of a provider *not* acting.
  /// - Parameter now: current epoch milliseconds.
  /// - Returns: what must be reported back, per provider.
  func tick(now: Int) -> [Settled] {
    var settled: [Settled] = []
    for (provider, session) in sessions {
      // A lapsed lease takes everything the provider held, so its seats go with
      // it; a live provider that merely left a question too long keeps its other
      // entities and only gives up the seat for that question.
      let outcomes = session.expired(now: now) ? session.expire(now: now) : session.sweep(now: now)
      for settlement in outcomes { settled.append(Settled(provider: provider, settlement: settlement)) }
      if !outcomes.isEmpty { reconcile(provider) }
    }
    return settled
  }

  /// Drop a provider whose connection ended.
  ///
  /// Nothing can be delivered to a provider that is gone, so the settlements are
  /// returned rather than sent: Core records that the user's answer, or their
  /// unanswered question, ended this way.
  /// - Parameter provider: the identity whose connection ended.
  /// - Returns: the decisions that were left outstanding.
  func disconnect(_ provider: ProviderID) -> [Settled] {
    guard let session = sessions[provider] else { return [] }
    let settled = session.expire(now: Int.max).map { Settled(provider: provider, settlement: $0) }
    sessions[provider] = nil
    displayNames[provider] = nil
    release(provider)
    return settled
  }

  /// The entities one provider holds, in the order it first held them.
  ///
  /// The presentation composes its surface from these, and the conformance
  /// corpus reads them to observe what a provider's messages did.
  /// - Parameter provider: the identity the transport observed.
  /// - Returns: the entities, or nothing for a provider with no session.
  func held(_ provider: ProviderID) -> [Entity] {
    sessions[provider]?.entities() ?? []
  }

  /// Every entity every provider holds, with where it came from and when it last
  /// changed — which is what the surface is composed from.
  func inventory() -> [HeldEntity] {
    sessions.flatMap { provider, session in
      session.entities().map { entity in
        HeldEntity(provider: provider, entity: entity, updatedAt: session.updatedAt(entity.key) ?? 0)
      }
    }
  }

  /// What the user is being asked, and what waits behind it.
  func adjudication() -> Adjudication {
    func seat(at index: Int) -> Decision? {
      guard queue.indices.contains(index), let session = sessions[queue[index].provider] else { return nil }
      return decision(for: queue[index], in: session)
    }
    return Adjudication(expanded: seat(at: 0), waiting: seat(at: 1))
  }

  /// The providers currently registered, for the management surface.
  func providers() -> [ProviderRecord] {
    sessions
      .filter { $0.value.isRegistered }
      .map { provider, session in
        ProviderRecord(
          id: provider,
          displayName: displayNames[provider],
          classes: session.granted,
          entities: session.entities().count
        )
      }
      .sorted { $0.id < $1.id }
  }

  // MARK: - The adjudicative queue

  /// Take a seat in the adjudicative queue, if the message asks for one.
  ///
  /// The per-provider bound is checked here as well as in the session so that the
  /// refusal names the bound that actually blocks the provider: being told the
  /// queue is full, when the queue would still have room for one more, sends a
  /// provider away to retry something that will never fit.
  ///
  /// Nothing is admitted unless everything the message asks for fits, because a
  /// message refused halfway would leave a seat standing for an entity the
  /// session never accepted — and an empty seat still blocks the provider that
  /// would have filled it.
  /// - Returns: a refusal, or nothing when the message may proceed.
  private func admit(_ provider: ProviderID, _ message: ProviderMessage) -> Refused? {
    let asked = seatsAskedFor(message).filter { !seated(provider, $0) }
    guard !asked.isEmpty else { return nil }

    let holds = queue.reduce(0) { $0 + ($1.provider == provider ? 1 : 0) }
    guard holds + asked.count <= Limits.outstandingAwaitingPerProvider else {
      return Refused(.interactionLimit, "already holds \(Limits.outstandingAwaitingPerProvider) outstanding interaction")
    }
    guard queue.count + asked.count <= queueCapacity else {
      return Refused(.decisionQueueFull, "a decision is already on screen and \(Limits.adjudicativeQueueDepth) waits behind it")
    }
    for key in asked { queue.append(Seat(provider: provider, key: key)) }
    return nil
  }

  /// Whether this provider already holds a seat for this entity.
  private func seated(_ provider: ProviderID, _ key: String) -> Bool {
    queue.contains { $0.provider == provider && $0.key == key }
  }

  /// Give up every seat one provider holds.
  private func release(_ provider: ProviderID) {
    queue.removeAll { $0.provider == provider }
  }

  /// Drop the seats whose decisions are no longer outstanding.
  ///
  /// Reconciling against the session rather than tracking settlements keeps one
  /// source of truth: however a decision ended — answered, withdrawn, abandoned,
  /// timed out, or removed with its entity — the session stops reporting it as
  /// pending, and the seat follows.
  private func reconcile(_ provider: ProviderID) {
    guard let session = sessions[provider] else { return }
    let pending = Set(session.awaiting().map(\.key))
    queue.removeAll { $0.provider == provider && !pending.contains($0.key) }
  }

  /// The decision one seat stands for, or nothing if the session no longer holds it.
  private func decision(for seat: Seat, in session: ProviderSession) -> Decision? {
    guard let entity = session.entity(seat.key), let interaction = entity.interaction else { return nil }
    return Decision(provider: seat.provider, key: seat.key, title: entity.title, interaction: interaction)
  }
}

/// The entity keys one message asks to put in the adjudicative queue.
///
/// A snapshot asks for every decision it carries, which is how a provider that
/// restarts announces a question the user was already reading.
/// - Parameter message: the provider message.
/// - Returns: the keys the message asks a seat for, in the order it names them.
private func seatsAskedFor(_ message: ProviderMessage) -> [String] {
  switch message {
  case .snapshot(let fields):
    guard let entities = Wire.array(fields["entities"]) else { return [] }
    return entities.compactMap { raw in
      guard let object = Wire.object(raw), object["interaction"] != nil else { return nil }
      return Wire.string(object["key"])
    }
  case .upsert(let fields):
    guard let object = Wire.object(fields["entity"]), object["interaction"] != nil else { return [] }
    return Wire.string(object["key"]).map { [$0] } ?? []
  case .interactionRequest(let fields):
    // An interaction request addressed to an entity whose key is not even a
    // string is refused by the session; asking for a seat under the empty key
    // would put a seat in the queue that no entity can ever fill.
    guard let key = Wire.string(fields["key"]) else { return [] }
    return [key]
  default:
    return []
  }
}

/// A string as the reasons quote it.
private func quoted(_ value: String) -> String {
  "\"\(value)\""
}

/// The refusal an outcome carries, which `check` has already ruled out.
private func refusalOf(_ outcome: Outcome) -> Refused {
  if case .refused(let refusal) = outcome { return refusal }
  return Refused(.messageInvalid, "message is not shaped like its type")
}
