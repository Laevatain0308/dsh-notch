import Foundation

/// Replay `protocol/v1/conformance.json` against the Swift implementation.
///
/// The corpus is the contract, and it is the same file the TypeScript
/// implementation is tested against. A failure here means Core and the contract
/// disagree — either this implementation is wrong, or the corpus is, and the
/// interesting work is deciding which. That is the point: it is the only place
/// where the rules are written down in a form two implementations must agree on.
///
/// Usage: `dsh-notch <path to conformance.json>`
@main enum ConformanceProbe {
  static func main() {
    let arguments = CommandLine.arguments
    guard arguments.count > 1 else {
      print("usage: dsh-notch <path to conformance.json>")
      exit(2)
    }
    let url = URL(fileURLWithPath: arguments[1])
    guard let data = try? Data(contentsOf: url), let corpus = Wire.object(try? JSONSerialization.jsonObject(with: data)) else {
      print("FAIL could not read the corpus at \(url.path)")
      exit(2)
    }

    var failures = 0
    var checks = 0
    func check(_ value: Bool, _ label: String) {
      checks += 1
      if !value {
        failures += 1
        print("FAIL \(label)")
      }
    }

    // The corpus states the version, the bounds and the clock, so an
    // implementation that has drifted on any of them fails before it replays a
    // single message.
    check(integer(corpus["protocolVersion"]) == protocolVersion, "protocol version matches the corpus")
    if let limits = Wire.object(corpus["limits"]) {
      check((Wire.object(from: limits, as: [String: Int].self)) == Limits.asJSON, "limits match the corpus")
    } else {
      check(false, "the corpus states its limits")
    }
    if let clock = Wire.object(corpus["clock"]) {
      check(integer(clock["start"]) == 1_000_000, "the corpus clock starts where the cases assume")
    }

    guard let cases = Wire.array(corpus["cases"]) else {
      print("FAIL the corpus states its cases")
      exit(1)
    }

    for raw in cases {
      guard let entry = Wire.object(raw), let name = Wire.string(entry["name"]), let steps = Wire.array(entry["steps"]) else {
        check(false, "every case has a name and steps")
        continue
      }
      let core = NotchCore()
      for (index, rawStep) in steps.enumerated() {
        guard let step = Wire.object(rawStep), let op = Wire.string(step["op"]) else {
          check(false, "\(name): step \(index + 1) has an operation")
          continue
        }
        let where_ = "\(name): step \(index + 1) (\(op))"
        switch op {
        case "connect":
          guard let provider = Wire.string(step["provider"]) else { check(false, "\(where_): names a provider"); continue }
          core.connect(provider, displayName: Wire.string(step["displayName"]))

        case "receive":
          guard
            let provider = Wire.string(step["provider"]),
            let at = integer(step["at"]),
            let message = Wire.object(step["message"]),
            let expect = Wire.object(step["expect"])
          else { check(false, "\(where_): is well formed"); continue }
          let data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
          let outcome = core.receive(provider, ProviderMessage.decode(from: data), now: at)
          let wanted = expect["ok"] as? Bool ?? false
          check(outcome.ok == wanted, "\(where_): \(describe(outcome))")
          if !wanted, let code = Wire.string(expect["code"]) {
            check(refusalCode(of: outcome)?.rawValue == code, "\(where_): expected \(code), got \(refusalCode(of: outcome)?.rawValue ?? "none")")
          }
          if let grant = Wire.object(expect["grant"]), let outcomeGrant = grantOf(outcome) {
            check(objection(grant, against: outcomeGrant, at: where_), "\(where_): grant")
          }

        case "tick":
          guard let at = integer(step["at"]) else { check(false, "\(where_): states a time"); continue }
          let settled = core.tick(now: at).map(settlement)
          check(matches(settled, expect: step["expect"]), "\(where_): \(render(settled)) != \(render(step["expect"]))")

        case "disconnect":
          guard let provider = Wire.string(step["provider"]) else { check(false, "\(where_): names a provider"); continue }
          let settled = core.disconnect(provider).map(settlement)
          check(matches(settled, expect: step["expect"]), "\(where_): \(render(settled)) != \(render(step["expect"]))")

        case "answer":
          guard
            let interactionID = Wire.string(step["interactionId"]),
            let answers = Wire.object(step["answers"]).flatMap({ Wire.object(from: $0, as: [String: [String]].self) }),
            let expect = Wire.object(step["expect"])
          else { check(false, "\(where_): is well formed"); continue }
          let answering = core.adjudication().expanded?.provider ?? ""
          let outcome = core.answer(interactionID: interactionID, answers: answers)
          let wanted = expect["ok"] as? Bool ?? false
          check(outcome.ok == wanted, "\(where_): \(describe(outcome))")
          if !wanted, let code = Wire.string(expect["code"]) {
            let actual: String?
            if case .refused(let refusal) = outcome { actual = refusal.code.rawValue } else { actual = nil }
            check(actual == code, "\(where_): expected \(code), got \(actual ?? "none")")
          }
          if let stated = Wire.object(expect["settlement"]), case .answered(let answered) = outcome {
            let entry = settlement(Settled(provider: answering, settlement: answered))
            check(matches([entry], expect: [stated]), "\(where_): settlement \(entry) != \(stated)")
          }

        case "decision":
          let adjudication = core.adjudication()
          let actual: [String: Any] = [
            "expanded": shown(adjudication.expanded),
            "waiting": shown(adjudication.waiting),
          ]
          check(objection(step["expect"], against: actual, at: where_), "\(where_): \(actual)")

        case "entities":
          guard let provider = Wire.string(step["provider"]) else { check(false, "\(where_): names a provider"); continue }
          let actual = core.held(provider).map(shown)
          check(objection(step["expect"], against: actual, at: where_), "\(where_): \(actual)")

        case "providers":
          let actual = core.providers().map { record -> [String: Any] in
            var fields: [String: Any] = ["id": record.id, "entities": record.entities]
            if let name = record.displayName { fields["displayName"] = name }
            fields["classes"] = record.classes.map(\.rawValue)
            return fields
          }
          check(objection(step["expect"], against: actual, at: where_), "\(where_): \(actual)")

        default:
          check(false, "\(where_): unknown operation")
        }
      }
      if failures == 0 { print("CHECKED \(name)") }
    }

    print("FAILURES=\(failures) CHECKS=\(checks)")
    exit(failures == 0 ? 0 : 1)
  }
}

// MARK: - Reading the corpus

/// An integer as the corpus writes it.
private func integer(_ value: Any?) -> Int? {
  Wire.number(value).map { Int($0) }
}

/// One entity as the corpus observes it: what it is, not what it carries.
private func shown(_ entity: Entity) -> [String: Any] {
  var fields: [String: Any] = ["key": entity.key, "class": entity.class.rawValue, "state": entity.state]
  if let unread = entity.unread { fields["unread"] = unread }
  return fields
}

/// One decision as the corpus states it, without the question text.
private func shown(_ decision: Decision?) -> Any {
  guard let decision else { return NSNull() }
  return ["provider": decision.provider, "key": decision.key, "interactionId": decision.interaction.id]
}

/// A settlement as the corpus states it, without the prose the user is told.
private func settlement(_ entry: Settled) -> [String: Any] {
  var outcome: [String: Any] = [:]
  switch entry.settlement.outcome {
  case .answered(let answers):
    outcome["status"] = "answered"
    outcome["answers"] = answers
  case .cancelled:
    outcome["status"] = "cancelled"
  }
  return [
    "provider": entry.provider,
    "key": entry.settlement.key,
    "interactionId": entry.settlement.interactionID,
    "outcome": outcome,
  ]
}

private func refusalCode(of outcome: CoreOutcome) -> RefusalCode? {
  if case .refused(let refusal) = outcome { return refusal.code }
  return nil
}

private func grantOf(_ outcome: CoreOutcome) -> [String: Any]? {
  guard case .accepted(let grant) = outcome, let grant else { return nil }
  return ["protocolVersion": grant.protocolVersion, "grantedClasses": grant.grantedClasses.map(\.rawValue)]
}

private func describe(_ outcome: CoreOutcome) -> String {
  if case .refused(let refusal) = outcome { return "refused \(refusal.code.rawValue): \(refusal.reason)" }
  return "accepted"
}

private func describe(_ outcome: AnswerOutcome) -> String {
  if case .refused(let refusal) = outcome { return "refused \(refusal.code.rawValue): \(refusal.reason)" }
  return "answered"
}

/// Compare what a step states against what happened, for the fields it states.
///
/// A corpus expectation is a statement about the fields it names, not about the
/// whole of a value: `tick` says which settlements must come back, not how they
/// are ordered, and a decision states the interaction id rather than the question
/// text. Everything the corpus does not mention is not compared.
private func objection(_ expected: Any?, against actual: Any?, at label: String) -> Bool {
  switch expected {
  case let wanted as [String: Any]:
    guard let got = Wire.object(actual) else {
      print("FAIL \(label): expected an object, got \(String(describing: actual))")
      return false
    }
    for (key, value) in wanted where !objection(value, against: got[key], at: "\(label).\(key)") { return false }
    return true
  case let wanted as [Any]:
    guard let got = Wire.array(actual), got.count == wanted.count else {
      print("FAIL \(label): expected \(wanted.count) items, got \(String(describing: actual))")
      return false
    }
    for (index, value) in wanted.enumerated() where !objection(value, against: got[index], at: "\(label)[\(index)]") {
      return false
    }
    return true
  case let wanted as String:
    guard Wire.string(actual) == wanted else {
      print("FAIL \(label): expected \(wanted), got \(String(describing: actual))")
      return false
    }
    return true
  case let wanted as NSNumber:
    // `NSNumber` bridges to both `Bool` and every numeric type, so a corpus `1`
    // would satisfy a check for `true` if the boolean case came first. Which one
    // it is has to be asked of the number itself.
    if CFGetTypeID(wanted) == CFBooleanGetTypeID() {
      guard Wire.bool(actual) == wanted.boolValue else {
        print("FAIL \(label): expected \(wanted.boolValue), got \(String(describing: actual))")
        return false
      }
      return true
    }
    guard let got = Wire.number(actual), got == wanted.doubleValue else {
      print("FAIL \(label): expected \(wanted), got \(String(describing: actual))")
      return false
    }
    return true
  case is NSNull:
    guard actual == nil || actual is NSNull else {
      print("FAIL \(label): expected nothing, got \(String(describing: actual))")
      return false
    }
    return true
  default:
    print("FAIL \(label): the corpus states something this runner cannot compare")
    return false
  }
}

/// Whether two lists of settlements state the same thing, in any order.
///
/// The corpus lists `tick` and `disconnect` results as a set: which settlements
/// come back is the contract, and the order they arrive in is not.
private func matches(_ actual: [[String: Any]], expect: Any?) -> Bool {
  guard let wanted = Wire.array(expect) else { return false }
  guard actual.count == wanted.count else { return false }
  var remaining = actual
  for entry in wanted {
    guard let index = remaining.firstIndex(where: { objection(entry, against: $0, at: "settlement") }) else { return false }
    remaining.remove(at: index)
  }
  return true
}

private func render(_ value: Any?) -> String {
  guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else {
    return String(describing: value)
  }
  return String(data: data, encoding: .utf8) ?? ""
}

extension Wire {
  /// Re-read a JSON object as a typed value, for the cases where a shape is
  /// already known — the corpus's own limits, and an answer's options.
  static func object<T: Decodable>(from fields: [String: Any], as type: T.Type) -> T? {
    guard let data = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }
}
