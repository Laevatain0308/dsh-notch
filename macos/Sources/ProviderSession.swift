//
//  ProviderSession.swift
//  DshNotch
//
//  One provider's connection to Notch, and the rules its messages must satisfy.
//
//  This file is the Swift half of `protocol/v1/session.ts`. Every rejection here
//  is a rule the OpenSpec record states as behaviour, which is the point of the
//  file: a rule that lives only in prose is a rule that gets re-derived
//  differently in each implementation. Rejections carry a reason because the
//  protocol requires refusals to be reported to the provider rather than silently
//  dropped, and a code because a provider has to act on them.
//
//  The session owns everything Core needs to judge one provider: what it was
//  granted, whether it has sent the snapshot that begins a subscription, what it
//  currently holds, and when its lease runs out.
//

import Foundation

/// One provider's session.
final class ProviderSession {
  /// Classes this provider may express. Empty until registration is accepted.
  private(set) var granted: [CapabilityClass] = []
  /// Action names the provider undertook to interpret.
  private(set) var declaredActions: [String] = []

  private var held: [String: Entity] = [:]
  /// The order entities were first held in, so a surface composed from them does
  /// not reshuffle itself whenever one is updated.
  private var order: [String] = []
  /// Keys whose interaction is outstanding; at most one per provider.
  private var outstanding: Set<String> = []
  /// When each outstanding decision must be settled by, keyed by entity.
  private var deadlines: [String: Int] = [:]

  private var snapshotted = false
  private var registered = false
  private var leaseExpiresAt = 0

  /// Whether the provider currently holds a grant.
  ///
  /// A lease that lapsed or a provider that unregistered both end the grant, so
  /// this is not the same question as whether the connection still exists.
  var isRegistered: Bool { registered }

  /// Whether the snapshot that begins a subscription has arrived.
  var hasSnapshot: Bool { snapshotted }

  // MARK: - Registration

  /// Register the provider.
  /// - Parameters:
  ///   - fields: the registration object, unread.
  ///   - now: current epoch milliseconds.
  /// - Returns: the grant, or a refusal the provider is told.
  func register(_ fields: [String: Any], now: Int) -> Result<Grant, Refused> {
    guard let registration = Wire.object(fields["registration"]) else {
      return .failure(Refused(.messageInvalid, "register needs a registration object"))
    }
    // A version that is missing or not a number is not the version this
    // implementation speaks, which is the whole of what the provider needs told.
    let version = Wire.number(registration["protocolVersion"]).map { Int($0) }
    guard version == protocolVersion else {
      return .failure(Refused(.versionIncompatible, "protocol version \(describe(version)) is not compatible with \(protocolVersion)"))
    }

    guard let requested = Wire.array(registration["requestedClasses"]), !requested.isEmpty else {
      return .failure(Refused(.noClassesRequested, "no behaviour classes requested"))
    }
    var classes: [CapabilityClass] = []
    for value in requested {
      let name = Wire.string(value) ?? ""
      guard let behaviour = CapabilityClass(rawValue: name) else {
        return .failure(Refused(.unknownClass, "unknown behaviour class \(json(value))"))
      }
      classes.append(behaviour)
    }

    let actions = registration["actions"]
    var declared: [String] = []
    if actions != nil {
      guard let list = Wire.array(actions) else {
        return .failure(Refused(.actionsInvalid, "actions must be a list"))
      }
      for value in list {
        guard let name = Wire.string(value), !name.isEmpty else {
          return .failure(Refused(.actionNameInvalid, "action names must be non-empty strings"))
        }
        declared.append(name)
      }
      if Set(declared).count != declared.count {
        return .failure(Refused(.actionNameDuplicate, "action names must be unique"))
      }
    }

    granted = classes
    declaredActions = declared
    registered = true
    snapshotted = false
    leaseExpiresAt = now + Limits.leaseExpiryMs
    return .success(Grant(protocolVersion: protocolVersion, grantedClasses: classes))
  }

  // MARK: - Messages

  /// Apply one message from the provider.
  /// - Parameters:
  ///   - message: the message.
  ///   - now: current epoch milliseconds, used to extend the lease.
  /// - Returns: whether it was accepted, or why it was refused.
  func receive(_ message: ProviderMessage, now: Int) -> Outcome {
    if let problem = check(message) { return .refused(problem) }
    return apply(message, now: now)
  }

  /// Whether one message would be accepted, changing nothing.
  ///
  /// Core asks this before it gives the message a place in the adjudicative
  /// queue, so that a message which is simply invalid is refused for being
  /// invalid. Without that order a provider holding one decision would be told
  /// the queue was full however wrong the message was, and would go away to fix
  /// something that was never the problem.
  ///
  /// This is the same validation `receive` performs, not a copy of it: `receive`
  /// calls it and then applies. Nothing here may mutate, and nothing may be added
  /// to `apply` that this does not already allow.
  /// - Parameter message: the message.
  /// - Returns: the refusal the message earns, or nothing if it is acceptable.
  func check(_ message: ProviderMessage) -> Refused? {
    guard registered else { return Refused(.notRegistered, "not registered") }

    switch message {
    case .unknownType(let type):
      return Refused(.unknownMessage, "unknown message \(json(type))")
    case .malformed:
      return Refused(.messageInvalid, "message is not shaped like its type")

    case .register:
      return Refused(.alreadyRegistered, "already registered")
    case .renew, .unregister:
      return nil

    case .snapshot(let fields):
      guard let entities = Wire.array(fields["entities"]) else {
        return Refused(.snapshotInvalid, "snapshot must be a list of entities")
      }
      guard entities.count <= Limits.entitiesPerProvider else {
        return Refused(.entityLimit, "snapshot holds \(entities.count) entities, above the limit of \(Limits.entitiesPerProvider)")
      }
      var decisions = 0
      for raw in entities {
        guard let object = Wire.object(raw) else {
          return Refused(.entityInvalid, "entity key must be a non-empty string")
        }
        if let problem = checkEntity(object) { return problem }
        if object["interaction"] != nil { decisions += 1 }
      }
      // A snapshot is a provider's whole view, so it is also the one message
      // that could smuggle in a second decision past the per-provider bound.
      guard decisions <= Limits.outstandingAwaitingPerProvider else {
        return Refused(.interactionLimit, "snapshot holds \(decisions) decisions, above the limit of \(Limits.outstandingAwaitingPerProvider)")
      }
      return nil

    case .upsert(let fields):
      guard snapshotted else { return Refused(.deltaBeforeSnapshot, "delta before snapshot") }
      guard let object = Wire.object(fields["entity"]) else {
        return Refused(.entityInvalid, "entity key must be a non-empty string")
      }
      if let problem = checkEntity(object) { return problem }
      guard let key = Wire.string(object["key"]) else {
        return Refused(.entityInvalid, "entity key must be a non-empty string")
      }
      let isNew = held[key] == nil
      if isNew && held.count >= Limits.entitiesPerProvider {
        return Refused(.entityLimit, "holds \(Limits.entitiesPerProvider) entities already, the limit")
      }
      if object["interaction"] == nil { return nil }
      if outstanding.contains(key) { return nil }
      if outstanding.count >= Limits.outstandingAwaitingPerProvider {
        return Refused(.interactionLimit, "already holds \(Limits.outstandingAwaitingPerProvider) outstanding interaction")
      }
      return nil

    // Every delta needs the snapshot that opens a subscription. Applying one
    // without it would let a reconnecting provider's partial view overwrite what
    // Core holds. A snapshot is what opens one, so it is never the message this
    // rule refuses.
    case .remove, .interactionCancel:
      guard snapshotted else { return Refused(.deltaBeforeSnapshot, "delta before snapshot") }
      return nil

    case .ack(let fields):
      guard snapshotted else { return Refused(.deltaBeforeSnapshot, "delta before snapshot") }
      let key = Wire.string(fields["key"]) ?? ""
      guard held[key] != nil else { return Refused(.noSuchEntity, "no entity \(json(key))") }
      return nil

    case .interactionRequest(let fields):
      guard snapshotted else { return Refused(.deltaBeforeSnapshot, "delta before snapshot") }
      let key = Wire.string(fields["key"]) ?? ""
      guard let entity = held[key] else { return Refused(.noSuchEntity, "no entity \(json(key))") }
      guard entity.class == .awaiting else {
        return Refused(.notAwaiting, "only an awaiting entity may raise an interaction")
      }
      guard outstanding.count < Limits.outstandingAwaitingPerProvider else {
        return Refused(.interactionLimit, "already holds \(Limits.outstandingAwaitingPerProvider) outstanding interaction")
      }
      let questions = Wire.object(fields["interaction"])?["questions"]
      return checkInteraction(questions)
    }
  }

  /// Carry out a message `check` accepted.
  ///
  /// Nothing here refuses: every rule that can be broken was decided above, so a
  /// mutation that could fail halfway through would be a rule this method forgot
  /// to ask about.
  private func apply(_ message: ProviderMessage, now: Int) -> Outcome {
    leaseExpiresAt = now + Limits.leaseExpiryMs

    switch message {
    case .snapshot(let fields):
      held.removeAll()
      order.removeAll()
      outstanding.removeAll()
      deadlines.removeAll()
      for raw in Wire.array(fields["entities"]) ?? [] {
        guard let object = Wire.object(raw), let entity = try? parseEntity(object) else { continue }
        held[entity.key] = entity
        order.append(entity.key)
        if entity.interaction != nil {
          outstanding.insert(entity.key)
          armDeadline(entity.key, now: now)
        }
      }
      snapshotted = true

    case .upsert(let fields):
      guard let object = Wire.object(fields["entity"]), let entity = try? parseEntity(object) else { break }
      if held[entity.key] == nil { order.append(entity.key) }
      held[entity.key] = entity
      track(entity, now: now)

    case .remove(let fields):
      let key = Wire.string(fields["key"]) ?? ""
      held[key] = nil
      order.removeAll { $0 == key }
      outstanding.remove(key)
      deadlines[key] = nil

    case .interactionRequest(let fields):
      let key = Wire.string(fields["key"]) ?? ""
      if let entity = held[key], let interaction = try? parseInteraction(fields["interaction"]) {
        held[key] = Entity(
          key: entity.key,
          class: entity.class,
          state: "pending",
          lifetime: entity.lifetime,
          title: entity.title,
          body: entity.body,
          fraction: entity.fraction,
          unread: entity.unread,
          actions: entity.actions,
          interaction: interaction
        )
      }
      outstanding.insert(key)
      armDeadline(key, now: now)

    case .interactionCancel(let fields):
      let key = Wire.string(fields["key"]) ?? ""
      outstanding.remove(key)
      deadlines[key] = nil
      if let entity = held[key] {
        held[key] = Entity(
          key: entity.key,
          class: entity.class,
          state: "cancelled",
          lifetime: entity.lifetime,
          title: entity.title,
          body: entity.body,
          fraction: entity.fraction,
          unread: entity.unread,
          actions: entity.actions,
          interaction: entity.interaction
        )
      }

    case .ack(let fields):
      let key = Wire.string(fields["key"]) ?? ""
      if let entity = held[key] {
        held[key] = Entity(
          key: entity.key,
          class: entity.class,
          state: entity.state,
          lifetime: entity.lifetime,
          title: entity.title,
          body: entity.body,
          fraction: entity.fraction,
          unread: false,
          actions: entity.actions,
          interaction: entity.interaction
        )
      }

    case .renew:
      break

    case .unregister:
      granted = []
      declaredActions = []
      held.removeAll()
      order.removeAll()
      outstanding.removeAll()
      deadlines.removeAll()
      registered = false

    case .register, .unknownType, .malformed:
      break
    }
    return .accepted
  }

  // MARK: - What the provider holds

  /// The entities currently held, in the order they were first held.
  func entities() -> [Entity] {
    order.compactMap { held[$0] }
  }

  /// One entity by key.
  func entity(_ key: String) -> Entity? {
    held[key]
  }

  /// Decisions still waiting on the user, in insertion order.
  ///
  /// A settled entity keeps its interaction attached — the answer is part of what
  /// the provider is told and part of what the user sees — so this is the pending
  /// state, not merely the presence of an interaction.
  func awaiting() -> [Entity] {
    order.compactMap { held[$0] }.filter { $0.interaction != nil && $0.state == "pending" }
  }

  /// Whether the lease has lapsed and the held entities must be removed.
  func expired(now: Int) -> Bool {
    leaseExpiresAt <= now
  }

  // MARK: - Decisions

  /// Remove everything a lapsed lease holds, settling its decisions as abandoned.
  ///
  /// A user who was about to answer has to be able to tell that their answer did
  /// not land, so the decision is settled rather than dropped — and abandoned
  /// rather than cancelled, because the provider did not withdraw it, it died.
  /// Nothing can be delivered to a provider that is gone; the settlements are
  /// returned so Core can hold them until it comes back.
  /// - Parameter now: current epoch milliseconds.
  /// - Returns: one settlement per decision that was outstanding.
  func expire(now: Int) -> [Settlement] {
    guard expired(now: now) else { return [] }
    let settlements = outstanding.sorted().map { key in
      settle(key, state: "abandoned", outcome: .cancelled(reason: "the provider stopped responding"))
    }
    granted = []
    declaredActions = []
    held.removeAll()
    order.removeAll()
    deadlines.removeAll()
    registered = false
    return settlements
  }

  /// Settle decisions that have waited past their deadline, so a question nobody
  /// answers cannot hold the adjudicative queue forever.
  /// - Parameter now: current epoch milliseconds.
  /// - Returns: one settlement per decision that timed out.
  func sweep(now: Int) -> [Settlement] {
    outstanding.sorted().compactMap { key in
      guard let deadline = deadlines[key], deadline <= now else { return nil }
      return settle(key, state: "cancelled", outcome: .cancelled(reason: "the decision was not made in time"))
    }
  }

  /// Deliver the user's answer.
  /// - Parameters:
  ///   - key: the entity holding the decision.
  ///   - interactionID: the interaction being answered.
  ///   - answers: answer values keyed by question id; every question must appear.
  /// - Returns: the settlement to report, or why the answer was refused.
  func answer(key: String, interactionID: String, answers: [String: [String]]) -> AnswerOutcome {
    guard let entity = held[key] else { return .refused(Refused(.noSuchEntity, "no entity \(json(key))")) }
    guard outstanding.contains(key) else {
      return .refused(Refused(.noDecision, "that entity holds no outstanding decision"))
    }
    guard let interaction = entity.interaction, interaction.id == interactionID else {
      return .refused(Refused(.decisionMismatch, "the interaction id does not match the outstanding decision"))
    }
    for question in interaction.questions {
      guard let given = answers[question.id], !given.isEmpty else {
        return .refused(Refused(.answerIncomplete, "no answer given for question \(json(question.id))"))
      }
    }
    return .answered(settle(key, state: "answered", outcome: .answered(answers: answers)))
  }

  /// Mark one decision settled, recording the state the user will see.
  private func settle(_ key: String, state: String, outcome: InteractionOutcome) -> Settlement {
    let interactionID = held[key]?.interaction?.id ?? ""
    if let entity = held[key] {
      held[key] = Entity(
        key: entity.key,
        class: entity.class,
        state: state,
        lifetime: entity.lifetime,
        title: entity.title,
        body: entity.body,
        fraction: entity.fraction,
        unread: entity.unread,
        actions: entity.actions,
        interaction: entity.interaction
      )
    }
    outstanding.remove(key)
    deadlines[key] = nil
    return Settlement(key: key, interactionID: interactionID, outcome: outcome)
  }

  /// Record an entity's decision, or that it no longer carries one.
  private func track(_ entity: Entity, now: Int) {
    guard entity.interaction != nil else {
      outstanding.remove(entity.key)
      deadlines[entity.key] = nil
      return
    }
    guard !outstanding.contains(entity.key) else { return }
    outstanding.insert(entity.key)
    armDeadline(entity.key, now: now)
  }

  /// Arm a decision's deadline the first time it becomes outstanding.
  ///
  /// A provider that re-sends the same entity must not be able to push the
  /// deadline ahead of itself and hold the adjudicative queue forever, so the
  /// deadline is armed once and never extended.
  private func armDeadline(_ key: String, now: Int) {
    guard deadlines[key] == nil else { return }
    deadlines[key] = now + Limits.interactionDeadlineMs
  }

  // MARK: - Reading one entity

  /// Read one entity, or the refusal it earns.
  ///
  /// The order of these checks is the contract's, not an implementation detail:
  /// which refusal a provider gets for a message that is wrong in several ways is
  /// something the corpus states, and something a provider acts on.
  private func checkEntity(_ object: [String: Any]) -> Refused? {
    guard let key = Wire.string(object["key"]), !key.isEmpty else {
      return Refused(.entityInvalid, "entity key must be a non-empty string")
    }
    guard let className = Wire.string(object["class"]), let behaviour = CapabilityClass(rawValue: className) else {
      return Refused(.unknownClass, "unknown behaviour class \(json(object["class"]))")
    }
    guard granted.contains(behaviour) else {
      return Refused(.classNotGranted, "class \(behaviour.rawValue) was not granted")
    }
    guard let state = Wire.string(object["state"]), States.of(behaviour).contains(state) else {
      return Refused(.stateInvalid, "state \(json(object["state"])) is not a \(behaviour.rawValue) state")
    }
    guard let lifetimeName = Wire.string(object["lifetime"]), Lifetime(rawValue: lifetimeName) != nil else {
      return Refused(.lifetimeInvalid, "unknown lifetime \(json(object["lifetime"]))")
    }
    // A title that is present and not a string fails the limit rather than the
    // type, which is what the TypeScript implementation answers and therefore
    // what the corpus states; the two must not drift apart on a broken field.
    if let title = object["title"], !(Wire.string(title).map { $0.utf16.count <= Limits.titleLength } ?? false) {
      return Refused(.titleTooLong, "title longer than \(Limits.titleLength)")
    }
    if let body = object["body"], !(Wire.string(body).map { $0.utf16.count <= Limits.bodyLength } ?? false) {
      return Refused(.bodyTooLong, "body longer than \(Limits.bodyLength)")
    }

    // Fields belong to their class: a fraction is progress, unread is a result.
    if object["fraction"] != nil {
      guard behaviour == .progress else {
        return Refused(.fieldNotAllowed, "only a progress entity may carry a fraction")
      }
      guard let fraction = Wire.number(object["fraction"]), fraction >= 0, fraction <= 1 else {
        return Refused(.fractionInvalid, "fraction must be a number between 0 and 1")
      }
    }
    if object["unread"] != nil {
      guard behaviour == .result else {
        return Refused(.fieldNotAllowed, "only a result entity may be unread")
      }
      guard Wire.bool(object["unread"]) != nil else {
        return Refused(.unreadInvalid, "unread must be a boolean")
      }
    }
    if object["interaction"] != nil {
      guard behaviour == .awaiting else {
        return Refused(.notAwaiting, "only an awaiting entity may carry an interaction")
      }
      guard state == "pending" else {
        return Refused(.stateInvalid, "only a pending awaiting entity carries an interaction")
      }
      if let problem = checkInteraction(Wire.object(object["interaction"])?["questions"]) { return problem }
    }
    if object["actions"] != nil {
      guard let actions = Wire.array(object["actions"]) else {
        return Refused(.actionsInvalid, "actions must be a list")
      }
      for action in actions {
        let name = Wire.string(action) ?? ""
        guard declaredActions.contains(name) else {
          return Refused(.actionUndeclared, "action \(json(action)) was not declared at registration")
        }
      }
    }
    return nil
  }

  /// Rule check for the questions of one interaction.
  private func checkInteraction(_ questions: Any?) -> Refused? {
    guard let list = Wire.array(questions), !list.isEmpty else {
      return Refused(.interactionInvalid, "an interaction needs at least one question")
    }
    for raw in list {
      guard let question = Wire.object(raw) else {
        return Refused(.interactionInvalid, "question id must be a non-empty string")
      }
      guard let id = Wire.string(question["id"]), !id.isEmpty else {
        return Refused(.interactionInvalid, "question id must be a non-empty string")
      }
      guard let text = Wire.string(question["question"]), !text.isEmpty else {
        return Refused(.interactionInvalid, "question text must not be empty")
      }
      guard let options = Wire.array(question["options"]), !options.isEmpty else {
        return Refused(.interactionInvalid, "a question needs at least one option")
      }
      guard options.count <= Limits.optionsPerQuestion else {
        return Refused(.interactionInvalid, "a question offers \(options.count) options, above the limit of \(Limits.optionsPerQuestion)")
      }
    }
    return nil
  }

  /// Read one entity that `checkEntity` has already accepted.
  private func parseEntity(_ object: [String: Any]) throws -> Entity {
    guard
      let key = Wire.string(object["key"]),
      let className = Wire.string(object["class"]),
      let behaviour = CapabilityClass(rawValue: className),
      let state = Wire.string(object["state"]),
      let lifetimeName = Wire.string(object["lifetime"]),
      let lifetime = Lifetime(rawValue: lifetimeName)
    else { throw Refused(.entityInvalid, "entity key must be a non-empty string") }

    var interaction: Interaction?
    if object["interaction"] != nil {
      interaction = try parseInteraction(object["interaction"])
    }
    var actions: [String]?
    if let list = Wire.array(object["actions"]) {
      actions = list.compactMap { Wire.string($0) }
    }
    return Entity(
      key: key,
      class: behaviour,
      state: state,
      lifetime: lifetime,
      title: Wire.string(object["title"]),
      body: Wire.string(object["body"]),
      fraction: Wire.number(object["fraction"]),
      unread: Wire.bool(object["unread"]),
      actions: actions,
      interaction: interaction
    )
  }

  /// Read one interaction that `checkInteraction` has already accepted.
  private func parseInteraction(_ raw: Any?) throws -> Interaction {
    let object = Wire.object(raw)
    guard let list = Wire.array(object?["questions"]), !list.isEmpty else {
      throw Refused(.interactionInvalid, "an interaction needs at least one question")
    }
    var parsed: [Question] = []
    for raw in list {
      guard
        let question = Wire.object(raw),
        let id = Wire.string(question["id"]),
        let text = Wire.string(question["question"]),
        let options = Wire.array(question["options"])
      else { throw Refused(.interactionInvalid, "question id must be a non-empty string") }
      let answers = options.compactMap { raw -> AnswerOption? in
        guard let option = Wire.object(raw), let label = Wire.string(option["label"]) else { return nil }
        return AnswerOption(label: label, description: Wire.string(option["description"]))
      }
      parsed.append(
        Question(
          id: id,
          question: text,
          header: Wire.string(question["header"]),
          detail: Wire.string(question["detail"]),
          options: answers,
          multiSelect: Wire.bool(question["multiSelect"])
        )
      )
    }
    // The id is kept as the provider sent it. It is what an answer is addressed
    // by, and a provider that sends none simply gets an answer it can never
    // match — which is its own mistake to notice, not one to correct silently.
    return Interaction(id: Wire.string(object?["id"]) ?? "", questions: parsed)
  }
}

/// A value as it would be written in JSON, for the reasons a provider is told.
///
/// The reasons quote what the provider sent, because "unknown behaviour class
/// "downloads"" says which one; a reason that quoted only the field name would
/// send them looking through their own message.
private func json(_ value: Any?) -> String {
  guard let value else { return "undefined" }
  if let text = value as? String { return "\"\(text)\"" }
  if let number = value as? NSNumber {
    return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
  }
  guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else {
    return String(describing: value)
  }
  return String(data: data, encoding: .utf8) ?? String(describing: value)
}

/// An integer as the protocol would write it, or `undefined` when it was not one.
private func describe(_ value: Int?) -> String {
  value.map(String.init) ?? "undefined"
}
