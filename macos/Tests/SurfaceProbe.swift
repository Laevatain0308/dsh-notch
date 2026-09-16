import Foundation

/// What the island decides to show, and why.
///
/// The presentation rules are the ones a provider is most tempted to influence
/// and least able to: an entity carries no position, no order and no size, and
/// this probe holds the composition to that — a provider that sends all three
/// changes nothing about where it appears.
@main enum SurfaceProbe {
  static func main() {
    var failures = 0
    var checks = 0
    func check(_ value: Bool, _ label: String) {
      checks += 1
      if !value {
        failures += 1
        print("FAIL \(label)")
      }
    }

    /// A core with providers that have registered, snapshotted, and sent the
    /// entities the case states.
    func world(_ entities: [(provider: String, entity: [String: Any])]) -> (NotchCore, [String]) {
      let core = NotchCore()
      let providers = Array(Set(entities.map(\.provider))).sorted()
      for provider in providers {
        core.connect(provider)
        _ = core.receive(provider, .register(["registration": ["protocolVersion": 1, "requestedClasses": ["ambient", "progress", "activity", "result", "awaiting"]]]), now: 1_000_000)
        _ = core.receive(provider, .snapshot(["entities": []]), now: 1_000_000)
      }
      for entry in entities {
        guard let data = try? JSONSerialization.data(withJSONObject: entry.entity) else { continue }
        _ = core.receive(entry.provider, ProviderMessage.decode(from: data), now: 1_000_000)
      }
      return (core, providers)
    }

    /// The surface, as Core's inventory composes it.
    func compose(_ core: NotchCore, now: Int = 1_000_000) -> Surface {
      Composition.compose(held: core.inventory(), adjudication: core.adjudication())
    }

    // MARK: Order follows the class, then how recent it is

    let ordered = world([
      ("p1", ["type": "upsert", "entity": ["key": "ambient", "class": "ambient", "state": "present", "lifetime": "held"]]),
      ("p1", ["type": "upsert", "entity": ["key": "progress", "class": "progress", "state": "running", "lifetime": "held"]]),
      ("p1", ["type": "upsert", "entity": ["key": "activity", "class": "activity", "state": "running", "lifetime": "held"]]),
      ("p1", ["type": "upsert", "entity": ["key": "result", "class": "result", "state": "succeeded", "lifetime": "held"]]),
    ]).0
    let classes = compose(ordered).slots.map { slot -> String in
      switch slot {
      case .entity(let presented): return presented.behaviourClass.rawValue
      case .aggregate(let aggregate): return aggregate.behaviourClass.rawValue
      }
    }
    check(classes == ["result", "activity", "progress", "ambient"], "a result outranks activity, then progress, then ambient: \(classes)")

    // MARK: A decision outranks everything, and is not one of the four places

    let deciding = world([
      ("p1", ["type": "upsert", "entity": ["key": "result", "class": "result", "state": "succeeded", "lifetime": "held"]]),
      ("p1", ["type": "upsert", "entity": ["key": "ask", "class": "awaiting", "state": "pending", "lifetime": "held", "title": "Proceed?", "interaction": ["id": "i1", "questions": [["id": "q1", "question": "Proceed?", "options": [["label": "Yes"]]]]]]]),
    ]).0
    let withDecision = compose(deciding)
    check(withDecision.decision?.key == "ask", "the decision is the expanded entity")
    check(withDecision.decision?.title == "Proceed?", "it keeps the title the provider gave it")
    check(withDecision.slots.count == 1, "the decision does not take one of the capsule's places")
    check(withDecision.overflow == 0, "and leaves nothing over")

    // MARK: The same kind of thing from several providers is one affordance

    let many = world([
      ("p1", ["type": "upsert", "entity": ["key": "a", "class": "progress", "state": "running", "lifetime": "held", "fraction": 0.2]]),
      ("p2", ["type": "upsert", "entity": ["key": "b", "class": "progress", "state": "running", "lifetime": "held", "fraction": 0.4]]),
      ("p3", ["type": "upsert", "entity": ["key": "c", "class": "progress", "state": "running", "lifetime": "held"]]),
    ]).0
    let aggregated = compose(many)
    check(aggregated.slots.count == 1, "three providers reporting progress take one place, not three")
    if case .aggregate(let aggregate) = aggregated.slots.first {
      check(aggregate.entities == 3, "the affordance counts the entities it stands for")
      check(aggregate.providers == 3, "and the providers they came from")
      // Meaned floats land near their decimal rather than on it, so this is a
      // comparison of what was computed, not of how it was printed.
      let mean = aggregate.fraction ?? -1
      check(abs(mean - 0.3) < 1e-9, "and averages only the fractions that were determinate: \(mean)")
    } else {
      check(false, "the place is an aggregate")
    }

    // MARK: Results are never summarised into a count

    let results = world([
      ("p1", ["type": "upsert", "entity": ["key": "a", "class": "result", "state": "succeeded", "lifetime": "held", "unread": true]]),
      ("p2", ["type": "upsert", "entity": ["key": "b", "class": "result", "state": "failed", "lifetime": "held", "unread": true]]),
    ]).0
    let individual = compose(results)
    check(individual.slots.count == 2, "two finished results are two things to read, not one count")
    if case .entity(let first) = individual.slots.first {
      check(first.unread == true, "a result carries whether the user has seen it")
      check(first.state == "succeeded", "and its outcome")
    } else {
      check(false, "a result is presented on its own")
    }

    // MARK: The surface is bounded

    let crowded = world((1...9).map { index in
      ("p1", ["type": "upsert", "entity": ["key": "k\(index)", "class": "result", "state": "succeeded", "lifetime": "held", "title": "Result \(index)"]] as [String: Any])
    }).0
    let bounded = compose(crowded)
    check(bounded.slots.count == Limits.capsuleCapacity, "the capsule represents at most four entities individually: \(bounded.slots.count)")
    check(bounded.overflow == 5, "and counts the remainder rather than shrinking everything to fit: \(bounded.overflow)")

    // MARK: Recency decides between equals

    let core = NotchCore()
    core.connect("p1")
    _ = core.receive("p1", .register(["registration": ["protocolVersion": 1, "requestedClasses": ["result"]]]), now: 1_000_000)
    _ = core.receive("p1", .snapshot(["entities": []]), now: 1_000_000)
    _ = core.receive("p1", .upsert(["entity": ["key": "old", "class": "result", "state": "succeeded", "lifetime": "held"]]), now: 1_000_000)
    _ = core.receive("p1", .upsert(["entity": ["key": "new", "class": "result", "state": "succeeded", "lifetime": "held"]]), now: 1_000_001)
    let recent = Composition.compose(held: core.inventory(), adjudication: core.adjudication())
    if case .entity(let first) = recent.slots.first {
      check(first.key == "new", "the more recent of two equals comes first, and it did not change position by luck: \(first.key)")
    } else {
      check(false, "there is a first slot")
    }

    // MARK: A provider cannot ask for a place

    let withHints = world([
      ("p1", ["type": "upsert", "entity": ["key": "a", "class": "activity", "state": "running", "lifetime": "held", "order": 0, "position": "first", "size": 100, "priority": 99]]),
      ("p2", ["type": "upsert", "entity": ["key": "b", "class": "result", "state": "succeeded", "lifetime": "held", "order": 9, "position": "last", "size": 1, "priority": 0]]),
    ]).0
    let hinted = compose(withHints)
    // p2 asked to be last and p1 asked to be first; the result outranks the
    // activity because a result outranks an activity, and for no other reason.
    if case .entity(let first) = hinted.slots.first {
      check(first.provider == "p2" && first.behaviourClass == .result, "a provider's order, position and size change nothing")
    } else {
      check(false, "there is a first slot")
    }

    // MARK: Nothing changing means nothing to draw

    let idle = world([
      ("p1", ["type": "upsert", "entity": ["key": "a", "class": "ambient", "state": "present", "lifetime": "held"]]),
    ]).0
    check(compose(idle).working == false, "an ambient state alone is not something to keep drawing")

    let busy = world([
      ("p1", ["type": "upsert", "entity": ["key": "a", "class": "activity", "state": "running", "lifetime": "held"]]),
    ]).0
    check(compose(busy).working, "work in progress is something to keep drawing")

    let settled = world([
      ("p1", ["type": "upsert", "entity": ["key": "a", "class": "progress", "state": "paused", "lifetime": "held", "fraction": 0.5]]),
    ]).0
    check(compose(settled).working == false, "progress that is paused is not advancing")

    // MARK: An empty surface

    let nothing = compose(world([]).0)
    check(nothing.isEmpty, "a surface with nothing behind it is empty")
    check(nothing.decision == nil && nothing.waiting == nil && nothing.slots.isEmpty && nothing.overflow == 0, "and every part of it says so")

    print("CHECKS=\(checks)")
    print("FAILURES=\(failures)")
    exit(failures == 0 ? 0 : 1)
  }
}
