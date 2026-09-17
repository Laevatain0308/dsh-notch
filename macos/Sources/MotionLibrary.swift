//
//  MotionLibrary.swift
//  DshNotch
//
//  Every transition this surface can animate, named and accounted for.
//
//  Motion is the reason the island exists, and it is Notch's asset rather than
//  each provider's problem: a new provider reuses motion instead of commissioning
//  it, and a transition nobody has authored yet degrades through a recorded
//  fallback instead of silently becoming nothing. A provider never supplies a
//  curve or a duration; it supplies state, and state is what these are keyed to.
//
//  The key is a transition between two *kinds of presence* rather than anything
//  about a session, because that is the only vocabulary every provider shares.
//  Work that was running and is now a finished result is the same transition
//  whether it came from DSH or from a download, and it plays the same motion.
//

import Foundation

/// What the surface is showing, as a transition is stated in.
///
/// One value per kind of thing the island can be showing at once, which is
/// coarser than the entity model on purpose: the catalogue is about what the user
/// sees change, and two providers' progress bars change the same way.
enum Presence: String, CaseIterable, Sendable {
  /// Nothing at all from any provider.
  case nothing
  /// State with no lifecycle: a temperature, a mode, a count.
  case ambient
  /// Quantified advance, determinate or not.
  case progress
  /// Work in progress that is not quantified.
  case running
  /// A finished result that succeeded.
  case succeeded
  /// A finished result that failed.
  case failed
  /// Work blocked until the user decides.
  case deciding
}

/// One change the surface can show.
struct Transition: Hashable, Sendable {
  let from: Presence
  let to: Presence

  var id: String { "\(from.rawValue)->\(to.rawValue)" }
}

/// What the island does about one transition.
///
/// The motion itself is played by the capsule's own machinery; this states which
/// motion it is, so that the library is a list of what exists rather than a
/// second implementation of it.
enum Motion: String, Sendable {
  /// Nothing was shown and work has appeared: the ring is drawn from nothing.
  case birth
  /// Work finished and succeeded: a light travels into the ring.
  case arrivalSuccess
  /// Work finished and failed: the same travel, in the colour of failure.
  case arrivalFailure
  /// A question appeared: the ring stops travelling and holds.
  case decisionArrives
  /// A question was answered and work remains: the ring resumes travelling.
  case decisionResumes
  /// Everything finished: the ring closes.
  case settle
  /// The ring takes a new shape without a more particular motion to describe it.
  ///
  /// The recorded fallback, and a motion in its own right: a change the library
  /// has not been taught to say anything about still has to look like something
  /// happened, and this is the plainest way to say it.
  case takeShape
}

/// The transitions one entry was authored for.
///
/// A rule rather than a pair, because the same motion serves a family of changes:
/// work finishing is the same travel whether the ring was empty or busy, and
/// writing that out thirty-six times would be a list nobody could keep true. What
/// a rule leaves out is what falls back, and that is the list worth reading.
struct TransitionRule: Sendable {
  /// What was showing, or nothing for "whatever was".
  let from: Presence?
  /// What is showing, or nothing for "whatever it became".
  let to: Presence?

  func matches(_ transition: Transition) -> Bool {
    (from == nil || from == transition.from) && (to == nil || to == transition.to)
  }

  /// How much of a transition this rule names.
  ///
  /// The destination counts for more, because a motion says what something
  /// became: a rule that names it is describing the motion, and a rule that only
  /// names the origin is describing when it is available.
  var specificity: Int {
    (to == nil ? 0 : 2) + (from == nil ? 0 : 1)
  }
}

/// One catalogued motion, and the transitions it serves.
struct MotionEntry: Sendable {
  let motion: Motion
  /// The transitions it was authored for.
  let serves: TransitionRule
  /// What plays, in a sentence, for the developer reading the list.
  let plays: String
  /// Whether the island draws anything at all while it plays, which is what
  /// decides whether stillness has to be given up for it.
  let drawsContinuously: Bool
}

/// The catalogue, and what it does with a transition it has never seen.
///
/// A miss is not an error and not a crash: it plays the fallback, which is the
/// plainest motion that still says something changed, and it is written down so
/// the next person to work on motion knows what to author. The record is for
/// Notch's authors and never for the user: it is not part of the island.
final class MotionLibrary {
  /// Every motion that exists, in the order the developer reads them.
  ///
  /// An entry exists here only when the island renders it; a motion that is
  /// catalogued but cannot be drawn is not a motion, and the list is the whole of
  /// what this surface can do.
  static let entries: [MotionEntry] = [
    entry(.decisionResumes, from: .deciding, to: .running, "the ring resumes travelling once the question is answered"),
    entry(.arrivalSuccess, to: .succeeded, "a light travels into the ring as work finishes well"),
    entry(.arrivalFailure, to: .failed, "the same travel, in the colour of failure"),
    entry(.decisionArrives, to: .deciding, "the ring stops travelling and holds, and the question opens"),
    entry(.settle, to: .nothing, "the ring closes as the last of it ends"),
    entry(.birth, from: .nothing, "the ring is drawn from nothing as something appears"),
  ]

  // What is not here: the island opening and closing around its content. That is
  // the geometry's own animation, keyed to the island's expansion rather than to
  // anything a provider did, and a catalogue that took both readings would answer
  // one transition with two motions.

  /// The motion played when nothing in the catalogue fits.
  ///
  /// The plainest thing that still tells the user something changed: the ring
  /// settles into its new shape, which says that something is different without
  /// saying what. A transition that became nothing at all would be a state change
  /// the user never sees, which is worse than an unpolished one.
  static let fallback = Motion.takeShape

  /// Transitions that fell back, and how often.
  ///
  /// Keyed by the transition rather than logged as a stream, because the useful
  /// question is "what is missing from the library" and not "what happened at
  /// 14:03".
  private(set) var gaps: [Transition: Int] = [:]
  private let log: (String) -> Void

  init(log: @escaping (String) -> Void = { message in
    FileHandle.standardError.write(Data("notch: \(message)\n".utf8))
  }) {
    self.log = log
  }

  /// The motion one transition plays, and whether the library had it.
  /// - Parameter transition: the change to animate.
  /// - Returns: the motion, and whether it was the fallback.
  func resolve(_ transition: Transition) -> (motion: Motion, fellBack: Bool) {
    if let found = Self.catalogued(transition) { return (found.motion, false) }
    gaps[transition, default: 0] += 1
    log("no motion is catalogued for \(transition.id); playing \(Self.fallback.rawValue)")
    return (Self.fallback, true)
  }

  /// The entry for one transition, if the library has it.
  /// The entry that serves a transition, if any.
  ///
  /// The most specific rule wins, and rules of equal specificity are settled by
  /// the order they are written in — which is the order a person reads them, so
  /// that is where a tie is decided rather than somewhere in this function.
  static func catalogued(_ transition: Transition) -> MotionEntry? {
    entries
      .filter { $0.serves.matches(transition) }
      .max { $0.serves.specificity < $1.serves.specificity }
  }

  /// The transition worth watching for one entry.
  ///
  /// A rule can serve several transitions, and they are not equally watchable: an
  /// entry about something appearing is served by an ambient entity appearing and
  /// by work appearing, and only the second changes what the capsule draws. The
  /// one whose counts change is the one a scene should show, which is not the same
  /// as the first one the reading happens to produce.
  /// - Parameter entry: the catalogue entry.
  /// - Returns: a transition the island can produce and the capsule can show, or
  ///   nothing when the entry serves neither.
  static func watchableTransition(for entry: MotionEntry) -> Transition? {
    var fallback: Transition?
    for from in Presence.allCases {
      for to in Presence.allCases where from != to {
        let transition = Transition(from: from, to: to)
        guard entry.serves.matches(transition),
              PresenceReading.between(surface(from), surface(to)) == transition else { continue }
        if fallback == nil { fallback = transition }
        if Summary.showing(from) != Summary.showing(to) { return transition }
      }
    }
    return fallback
  }

  /// Whether the island has to keep drawing while a motion plays.
  static func drawsContinuously(_ motion: Motion) -> Bool {
    entries.first { $0.motion == motion }?.drawsContinuously ?? true
  }

  private static func entry(
    _ motion: Motion,
    from: Presence? = nil,
    to: Presence? = nil,
    _ plays: String,
    draws: Bool = true
  ) -> MotionEntry {
    MotionEntry(motion: motion, serves: TransitionRule(from: from, to: to), plays: plays, drawsContinuously: draws)
  }
}

/// What the surface is showing, as one value.
///
/// The island draws several things at once; a transition is about the one that
/// matters, so this is the most interesting thing on screen, by the same order the
/// composition uses. A question outranks a finished result, which outranks work in
/// progress, which outranks ambient state — because that is the order in which
/// they deserve the user's attention, and therefore the order in which a change
/// deserves to be animated.
enum PresenceReading {
  /// What one surface is showing.
  static func of(_ surface: Surface) -> Presence {
    if surface.decision != nil || surface.waiting != nil { return .deciding }
    if surface.summary.failed > 0 { return .failed }
    if surface.summary.completed > 0 { return .succeeded }
    if surface.summary.running > 0 { return .running }
    if surface.summary.progress > 0 { return .progress }
    if !surface.slots.isEmpty { return .ambient }
    return .nothing
  }

  /// The transition between two surfaces, if there is one to animate.
  /// - Parameters:
  ///   - before: what was showing.
  ///   - after: what is showing now.
  /// - Returns: the transition, or nothing when the reading did not change.
  static func between(_ before: Surface, _ after: Surface) -> Transition? {
    let from = of(before)
    let to = of(after)
    guard from != to else { return nil }
    return Transition(from: from, to: to)
  }
}

extension MotionLibrary {
  /// A surface showing one kind of presence, for callers that need to name a
  /// transition without having one in hand.
  /// - Parameters:
  ///   - presence: what it should read as.
  ///   - count: how many entities of that kind it holds, which is what a motion
  ///     that retains a source count is measured against.
  static func surface(_ presence: Presence, count: Int = 1) -> Surface {
    let core = NotchCore()
    core.connect("p")
    _ = core.receive("p", .register(["registration": ["protocolVersion": 1, "requestedClasses": ["ambient", "progress", "activity", "result", "awaiting"]]]), now: 1)
    _ = core.receive("p", .snapshot(["entities": []]), now: 1)
    let entity: [String: Any]? = switch presence {
    case .nothing: nil
    case .ambient: ["key": "a", "class": "ambient", "state": "present", "lifetime": "held"]
    case .progress: ["key": "a", "class": "progress", "state": "running", "lifetime": "held", "fraction": 0.5]
    case .running: ["key": "a", "class": "activity", "state": "running", "lifetime": "held"]
    case .succeeded: ["key": "a", "class": "result", "state": "succeeded", "lifetime": "held", "unread": true]
    case .failed: ["key": "a", "class": "result", "state": "failed", "lifetime": "held", "unread": true]
    case .deciding: ["key": "a", "class": "awaiting", "state": "pending", "lifetime": "held", "interaction": ["id": "i1", "questions": [["id": "q1", "question": "q", "options": [["label": "y"]]]]]]
    }
    if let entity {
      for index in 0..<max(1, count) {
        var one = entity
        one["key"] = "a\(index)"
        _ = core.receive("p", .upsert(["entity": one]), now: 1)
      }
    }
    return Composition.compose(held: core.inventory(), adjudication: core.adjudication())
  }
}
