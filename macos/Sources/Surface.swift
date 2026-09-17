//
//  Surface.swift
//  DshNotch
//
//  What the island shows, decided from what Core holds.
//
//  Notch owns everything about how information appears: what is shown, in what
//  order, how many entities are represented individually, which one is expanded,
//  and what happens to the rest. Providers contribute state and nothing else —
//  an entity carries no position, no order and no size, and this file could not
//  honour one if it did.
//
//  This is settled before the second provider exists, because arbitration cannot
//  be retrofitted once providers assume they own a slot: they never do.
//

import Foundation

/// One entity, as the surface presents it.
///
/// The provider it came from travels with it, so the expanded surface can name
/// whoever asked the user to decide, and so the management surface can say what
/// came from where.
struct Presented: Equatable, Sendable {
  let provider: ProviderID
  let key: String
  let behaviourClass: CapabilityClass
  let state: String
  let title: String?
  let body: String?
  let fraction: Double?
  let unread: Bool?
  let actions: [String]?
  /// What a decision is asking, which is what the user answers.
  let interaction: Interaction?
}

/// Several providers reporting the same kind of thing, as one affordance.
///
/// Five programs downloading is one download indicator with a count on it, not
/// five icons competing for the same edge of the screen.
struct Aggregate: Equatable, Sendable {
  let behaviourClass: CapabilityClass
  /// How many entities this affordance stands for.
  let entities: Int
  /// How many providers they came from, which is not the same number.
  let providers: Int
  /// The mean of the fractions that were determinate, or nothing when none were:
  /// an indeterminate advance has no progress to average, and inventing one for
  /// it would show the user a number nobody measured.
  let fraction: Double?
}

/// One place in the capsule.
enum Slot: Equatable, Sendable {
  /// An entity the user has to be able to tell apart from every other one.
  case entity(Presented)
  /// A kind of information, however many providers are reporting it.
  case aggregate(Aggregate)
}

/// What the capsule's summary needs to know.
///
/// Work in progress is counted twice over — unquantified and quantified — because
/// the island reads them differently: a spinner and a progress bar are different
/// things to be told about, and only the second can say how far along it is.
struct Summary: Equatable, Sendable {
  /// Work in progress that is not quantified.
  let running: Int
  /// Advance that is, or could be, quantified.
  let progress: Int
  /// Finished results the user has not read.
  let completed: Int
  /// Finished results that failed.
  let failed: Int

  /// What the counts are while the island is showing one kind of presence.
  ///
  /// Note what is missing: ambient state and a decision have no count. The capsule
  /// summarises *work* — how much is running, how much is waiting to be read, how
  /// much went wrong — and something with no lifecycle is shown in the panel rather
  /// than summed in the ring. A change that only involves those is a change the
  /// capsule cannot show.
  static func showing(_ presence: Presence) -> Summary {
    switch presence {
    case .nothing, .ambient, .deciding: return Summary(running: 0, progress: 0, completed: 0, failed: 0)
    case .progress: return Summary(running: 0, progress: 1, completed: 0, failed: 0)
    case .running: return Summary(running: 1, progress: 0, completed: 0, failed: 0)
    case .succeeded: return Summary(running: 0, progress: 0, completed: 1, failed: 0)
    case .failed: return Summary(running: 0, progress: 0, completed: 0, failed: 1)
    }
  }
}

/// Everything the island draws, and nothing else.
struct Surface: Equatable, Sendable {
  /// The decision on screen, which the user can answer.
  let decision: Presented?
  /// The one decision queued behind it, which the user cannot answer yet.
  let waiting: Presented?
  /// What the capsule represents individually, highest priority first.
  let slots: [Slot]
  /// How many entities the capsule does not represent individually.
  let overflow: Int
  /// A program asking to be allowed, when the user is the one being asked.
  let consent: ConsentPrompt?
  /// Whether anything is changing on its own, which is what decides whether the
  /// island has to keep drawing at all.
  let working: Bool
  /// How much of each kind there is, for the capsule's summary.
  ///
  /// Counted over everything the surface stands for rather than over the slots:
  /// four entities are represented individually and the rest are a count, and a
  /// summary that stopped counting at four would tell the user less the more
  /// there was.
  let summary: Summary

  /// Whether there is no provider content to show.
  ///
  /// A consent request is not provider content: it is Notch's own question, drawn
  /// by Notch's own view, and a surface that holds nothing but one has nothing for
  /// the content view to draw. Counting it here is what made the island open for a
  /// program asking to be allowed and then draw an empty panel — the surface was
  /// "not empty", so the content view took the region, and the request was never
  /// presented at all.
  var isEmpty: Bool {
    decision == nil && waiting == nil && slots.isEmpty && overflow == 0
  }
}

/// Composing the surface from what Core holds.
enum Composition {
  /// The order the presentation spec states, most important first.
  ///
  /// A decision outranks a finished result, which outranks work in progress, then
  /// progress, then ambient state. A provider cannot ask for a better place than
  /// the kind of information it is sending earns it.
  static func rank(_ behaviourClass: CapabilityClass) -> Int {
    switch behaviourClass {
    case .awaiting: return 0
    case .result: return 1
    case .activity: return 2
    case .progress: return 3
    case .ambient: return 4
    }
  }

  /// Classes that are represented one entity at a time.
  ///
  /// A finished result is something the user reads and acknowledges, and one
  /// decision is already on screen at a time; neither can be summarised into a
  /// count without losing the thing that makes it useful.
  static func isRepresentedIndividually(_ behaviourClass: CapabilityClass) -> Bool {
    behaviourClass == .result
  }

  /// Build the surface.
  /// - Parameters:
  ///   - held: every entity Core holds, from every provider.
  ///   - adjudication: the decision on screen and the one waiting behind it.
  /// - Returns: what the island draws.
  static func compose(held: [HeldEntity], adjudication: Adjudication, consent: ConsentRequest? = nil) -> Surface {
    // Awaiting entities are the expanded surface's business and nobody else's:
    // the one on screen and the one waiting behind it are presented there, and a
    // settled one is a record of what was asked rather than something to show. So
    // none of them competes for a place in the capsule.
    let candidates = held.filter { $0.entity.class != .awaiting }

    // Most important first, then most recent. The order is total: two entities
    // that tie on both are ordered by provider and key, so nothing on screen
    // depends on the order a dictionary happened to iterate in.
    let ordered = candidates.sorted { left, right in
      let leftRank = rank(left.entity.class)
      let rightRank = rank(right.entity.class)
      if leftRank != rightRank { return leftRank < rightRank }
      if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
      if left.provider != right.provider { return left.provider < right.provider }
      return left.entity.key < right.entity.key
    }

    var slots: [Slot] = []
    var overflow = 0
    // The slot each class already has, so a second provider reporting the same
    // kind of thing adds to that affordance instead of taking another place.
    var aggregated: Set<CapabilityClass> = []

    for item in ordered {
      let behaviourClass = item.entity.class

      guard isRepresentedIndividually(behaviourClass) else {
        // Already folded into its class's affordance, which is where the count
        // of it is shown; it is represented, just not on its own.
        guard !aggregated.contains(behaviourClass) else { continue }
        guard slots.count < Limits.capsuleCapacity else {
          overflow += 1
          continue
        }
        aggregated.insert(behaviourClass)
        slots.append(.aggregate(aggregate(of: behaviourClass, in: candidates)))
        continue
      }

      guard slots.count < Limits.capsuleCapacity else {
        overflow += 1
        continue
      }
      slots.append(.entity(present(item)))
    }

    // The region an expanded decision occupies is one region, and a decision
    // already in it is not interrupted: a program asking to be allowed waits for
    // the user to finish what they are doing. While consent holds the region, no
    // entity is presented there — which is what makes the consent decision
    // impossible to imitate, rather than merely hard to imitate convincingly.
    let decision = adjudication.expanded.flatMap { presented($0, in: held) }
    let regionIsFree = decision == nil && adjudication.waiting == nil
    let prompt = regionIsFree ? consent.map { request in
      ConsentPrompt(
        program: request.identity.displayName,
        path: request.identity.path,
        identifier: request.identity.identifier,
        classes: request.classes
      )
    } : nil

    let results = candidates.filter { $0.entity.class == .result }
    return Surface(
      decision: decision,
      waiting: adjudication.waiting.flatMap { presented($0, in: held) },
      slots: slots,
      overflow: overflow,
      consent: prompt,
      working: held.contains { $0.entity.class == .activity || ($0.entity.class == .progress && $0.entity.state == "running") },
      summary: Summary(
        running: candidates.filter { $0.entity.class == .activity }.count,
        progress: candidates.filter { $0.entity.class == .progress }.count,
        completed: results.filter { $0.entity.unread == true && $0.entity.state != "failed" }.count,
        failed: results.filter { $0.entity.state == "failed" }.count
      )
    )
  }

  /// Everything of one class, counted across providers.
  private static func aggregate(of behaviourClass: CapabilityClass, in held: [HeldEntity]) -> Aggregate {
    let members = held.filter { $0.entity.class == behaviourClass }
    let fractions = members.compactMap(\.entity.fraction)
    return Aggregate(
      behaviourClass: behaviourClass,
      entities: members.count,
      providers: Set(members.map(\.provider)).count,
      fraction: fractions.isEmpty ? nil : fractions.reduce(0, +) / Double(fractions.count)
    )
  }

  /// One entity, as the surface presents it.
  private static func present(_ item: HeldEntity) -> Presented {
    Presented(
      provider: item.provider,
      key: item.entity.key,
      behaviourClass: item.entity.class,
      state: item.entity.state,
      title: item.entity.title,
      body: item.entity.body,
      fraction: item.entity.fraction,
      unread: item.entity.unread,
      actions: item.entity.actions,
      interaction: item.entity.interaction
    )
  }

  /// The decision on screen, looked up among what Core holds.
  private static func presented(_ decision: Decision, in held: [HeldEntity]) -> Presented? {
    guard let item = held.first(where: { $0.provider == decision.provider && $0.entity.key == decision.key }) else {
      return nil
    }
    return present(item)
  }
}
