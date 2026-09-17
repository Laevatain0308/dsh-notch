import Foundation

/// The library of motions, held to its own rules.
///
/// The catalogue is the answer to "what can this surface do", so it is checked the
/// way a list is: nobody may add a motion nobody can render, two entries may not
/// claim the same transition, and a transition the island can produce with nothing
/// catalogued for it has to fall back and be written down.
@main enum MotionLibraryProbe {
  /// Every motion the island can play, which the catalogue is checked against.
  ///
  /// Written out rather than taken from `CaseIterable` so that adding a motion to
  /// the enum and forgetting the catalogue is a failing check rather than a
  /// silently complete-looking list.
  static let everyMotion: [Motion] = [
    .birth, .arrivalSuccess, .arrivalFailure, .decisionArrives, .decisionResumes,
    .settle, .takeShape,
  ]

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

    // MARK: The catalogue is a list of what can be rendered

    check(!MotionLibrary.entries.isEmpty, "there is a catalogue")
    let rules = MotionLibrary.entries.map(\.serves)
    let pairs = rules.map { "\($0.from?.rawValue ?? "*")->\($0.to?.rawValue ?? "*")" }
    check(Set(pairs).count == pairs.count, "no two entries claim the same transitions")
    for entry in MotionLibrary.entries {
      check(!entry.plays.isEmpty, "\(entry.motion.rawValue) says what it plays")
    }
    let named = Set(MotionLibrary.entries.map(\.motion))
    // The fallback is deliberately not an entry: it is what plays when nothing in
    // the catalogue fits, and cataloguing it would make every transition a match.
    let unnamed = everyMotion.filter { !named.contains($0) && $0 != MotionLibrary.fallback }
    check(unnamed.isEmpty, "every motion is either catalogued or the recorded fallback: \(unnamed.map(\.rawValue))")

    // MARK: What the island can show, against what it can animate

    // Every transition the reading can produce, so the gaps are a fact rather than
    // a hope. This is the check that says whether the catalogue covers the
    // surface: a pair it cannot produce is not a gap worth authoring.
    var producible = 0
    var missing: [String] = []
    for from in Presence.allCases {
      for to in Presence.allCases where from != to {
        let transition = Transition(from: from, to: to)
        guard PresenceReading.between(surfaceShowing(from), surfaceShowing(to)) == transition else { continue }
        producible += 1
        if MotionLibrary.catalogued(transition) == nil { missing.append(transition.id) }
      }
    }
    check(producible > 0, "the reading produces transitions")
    // Not a failure: the specification says an unauthored transition falls back and
    // is recorded. What would be a failure is a transition that resolves to
    // nothing at all, so that is what is checked — and the gaps are printed,
    // because that is the list a person authoring motion needs.
    var fallbacks = 0
    var catalogued = 0
    // A library of its own, so the walk's gaps are not the ones asserted on below.
    let libraryForCounting = MotionLibrary(log: { _ in })
    for from in Presence.allCases {
      for to in Presence.allCases where from != to {
        let transition = Transition(from: from, to: to)
        let (_, fellBack) = libraryForCounting.resolve(transition)
        if fellBack { fallbacks += 1 } else { catalogued += 1 }
      }
    }
    let total = Presence.allCases.count * (Presence.allCases.count - 1)
    check(fallbacks + catalogued == total, "every transition either is catalogued or falls back: \(catalogued) of \(total)")
    // An entry that matches nothing the island can show is a motion nobody can
    // see, which is the same as not having written it.
    for entry in MotionLibrary.entries {
      let covers = Presence.allCases.contains { from in
        Presence.allCases.contains { to in
          from != to && entry.serves.matches(Transition(from: from, to: to))
        }
      }
      check(covers, "\(entry.motion.rawValue) serves at least one transition the island can show")
    }
    print("NOTE \(missing.count) of \(producible) transitions the island can show fall back: \(missing.joined(separator: ", "))")

    // MARK: Resolution, and what happens when nothing fits

    check(
      MotionLibrary.catalogued(Transition(from: .running, to: .succeeded))?.motion == .arrivalSuccess,
      "work that finished and succeeded travels into the ring"
    )

    var logged: [String] = []
    let library = MotionLibrary(log: { logged.append($0) })
    _ = library
    let known = library.resolve(Transition(from: .running, to: .succeeded))
    check(known.motion == .arrivalSuccess && !known.fellBack, "a catalogued transition plays its motion")
    check(logged.isEmpty, "and nothing is written down about it")

    // A transition the island cannot currently produce is the honest way to test
    // the fallback, since a producible one would be a gap in the catalogue.
    // One of the transitions the note above lists as falling back: two kinds of
    // informational state, with nothing in the catalogue about either becoming
    // the other.
    let unknown = Transition(from: .ambient, to: .progress)
    let fellBack = library.resolve(unknown)
    check(fellBack.motion == MotionLibrary.fallback, "an uncatalogued transition plays the fallback")
    check(fellBack.fellBack, "and says so")
    check(logged.count == 1, "and is written down, for the developer reviewing the library")
    check(logged.first?.contains(unknown.id) == true, "with the transition it was: \(logged.first ?? "")")
    check(library.gaps[unknown] == 1, "and counted where a developer can find it")

    _ = library.resolve(unknown)
    check(library.gaps.count == 1 && library.gaps[unknown] == 2, "asking twice counts twice, on one entry")

    // MARK: Stillness is given up only where it has to be

    check(MotionLibrary.drawsContinuously(.birth), "a ring being drawn from nothing needs the island drawing")
    check(MotionLibrary.drawsContinuously(MotionLibrary.fallback), "and so does the fallback")

    // MARK: The reading itself

    check(PresenceReading.of(surfaceShowing(.nothing)) == .nothing, "an empty surface is nothing")
    check(PresenceReading.of(surfaceShowing(.deciding)) == .deciding, "a question outranks everything")
    check(PresenceReading.of(surfaceShowing(.failed)) == .failed, "a failure outranks a completion")
    check(PresenceReading.of(surfaceShowing(.succeeded)) == .succeeded, "a completion outranks work in progress")
    check(PresenceReading.of(surfaceShowing(.running)) == .running, "work in progress outranks progress")
    check(PresenceReading.of(surfaceShowing(.progress)) == .progress, "and progress outranks ambient state")
    check(PresenceReading.of(surfaceShowing(.ambient)) == .ambient, "ambient state is the least of them")

    check(
      PresenceReading.between(surfaceShowing(.running), surfaceShowing(.running)) == nil,
      "a surface that did not change has no transition to animate"
    )
    check(
      PresenceReading.between(surfaceShowing(.running), surfaceShowing(.succeeded)) == Transition(from: .running, to: .succeeded),
      "work that finished is the transition between the two readings"
    )

    print("CHECKS=\(checks)")
    print("FAILURES=\(failures)")
    exit(failures == 0 ? 0 : 1)
  }

  /// A surface showing one kind of presence, built from real entities so the
  /// reading is tested against the composition rather than against a fixture.
  private static func surfaceShowing(_ presence: Presence) -> Surface {
    let core = NotchCore()
    core.connect("p1")
    _ = core.receive("p1", .register(["registration": ["protocolVersion": 1, "requestedClasses": ["ambient", "progress", "activity", "result", "awaiting"]]]), now: 1_000_000)
    _ = core.receive("p1", .snapshot(["entities": []]), now: 1_000_000)

    func upsert(_ entity: [String: Any]) {
      _ = core.receive("p1", .upsert(["entity": entity]), now: 1_000_000)
    }
    switch presence {
    case .nothing:
      break
    case .ambient:
      upsert(["key": "a", "class": "ambient", "state": "present", "lifetime": "held"])
    case .progress:
      upsert(["key": "a", "class": "progress", "state": "running", "lifetime": "held", "fraction": 0.4])
    case .running:
      upsert(["key": "a", "class": "activity", "state": "running", "lifetime": "held"])
    case .succeeded:
      upsert(["key": "a", "class": "result", "state": "succeeded", "lifetime": "held", "unread": true])
    case .failed:
      upsert(["key": "a", "class": "result", "state": "failed", "lifetime": "held", "unread": true])
    case .deciding:
      upsert([
        "key": "a", "class": "awaiting", "state": "pending", "lifetime": "held",
        "interaction": ["id": "i1", "questions": [["id": "q1", "question": "Proceed?", "options": [["label": "Yes"]]]]],
      ])
    }
    return Composition.compose(held: core.inventory(), adjudication: core.adjudication())
  }
}
