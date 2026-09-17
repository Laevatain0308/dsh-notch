//
//  Consent.swift
//  DshNotch
//
//  Who is allowed to say anything, and how they came to be allowed.
//
//  Identity is observed, not claimed: the transport reads the peer's process,
//  executable and code signature, and everything here is pinned to that. A
//  provider cannot claim a name, and replacing an authorized program does not
//  inherit its authority, because the recorded identity includes the hash of the
//  code that was allowed.
//
//  Consent is expressed over behaviour classes rather than over programs,
//  because a class is legible without knowing the provider: "this program may
//  show progress" is a sentence a user can decide. A provider asking for classes
//  it was not allowed needs a new decision for the ones it is adding.
//
//  Nothing here renders. This decides what Notch will accept, and holds the
//  question the user has not answered yet.
//

import Foundation

/// What Notch has decided about one observed program.
enum Consent: Equatable, Sendable {
  /// Never asked, or asked and not yet answered.
  case undecided
  /// The user allowed it, for the classes it asked for.
  case allowed(classes: Set<CapabilityClass>)
  /// The user refused it.
  case denied
}

/// A program waiting for the user's decision.
struct ConsentRequest: Equatable, Sendable {
  /// The observed identity the decision is about.
  let identity: ProviderIdentity
  /// The classes being asked for that are not already allowed.
  let classes: [CapabilityClass]
  /// When the request was raised, which is what the rate limit counts from.
  let askedAt: Int
}

/// One recorded decision, as it is written down.
private struct ConsentRecord: Codable {
  /// The observed identity, which is the executable and the hash of its code.
  var id: String
  /// What the user sees this program called.
  var displayName: String
  /// The classes the user allowed.
  var classes: [String]
  /// Whether the user refused, in which case `classes` is empty.
  var denied: Bool
  /// When the decision was made, for the record the user can review.
  var decidedAt: Int
}

/// What Notch will accept, and what it is waiting to be told.
final class ConsentDesk {
  private var records: [String: ConsentRecord] = [:]
  /// Identities being asked about right now, with when they were asked.
  private var asking: [String: ConsentRequest] = [:]
  private let store: URL
  private var loaded = false

  /// Where the decisions are written down.
  ///
  /// A plain file with the owner's permissions and nothing else: it holds no
  /// secret, and a record a user cannot read is a record a user cannot audit.
  static func storeURL() -> URL {
    ProcessInfo.processInfo.environment["DSH_NOTCH_CONSENT_FILE"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dsh/dsh-notch/consent.json")
  }

  init(store: URL = ConsentDesk.storeURL()) {
    self.store = store
  }

  /// What Notch has decided about one identity.
  ///
  /// A recorded decision is matched on the whole identity, so a binary replaced
  /// in place is a program Notch has never been told about — which is the point
  /// of recording the hash of the code rather than its path.
  func state(of identity: ProviderIdentity) -> Consent {
    load()
    guard let record = records[identity.id] else { return .undecided }
    if record.denied { return .denied }
    return .allowed(classes: Set(record.classes.compactMap { CapabilityClass(rawValue: $0) }))
  }

  /// Ask the user about a program, unless they were asked a moment ago.
  ///
  /// The only way a prompt appears is a connection that asked for something, and
  /// a provider that reconnects in a loop cannot make one appear more often than
  /// the stated interval. Silence is not consent: an unanswered request leaves
  /// the program undecided and rendered not at all.
  /// - Parameters:
  ///   - identity: the observed identity.
  ///   - classes: the classes it is asking for.
  ///   - now: current epoch milliseconds.
  /// - Returns: the request being shown, or nothing when it is too soon to ask
  ///   again or the user has already refused.
  func ask(_ identity: ProviderIdentity, classes: [CapabilityClass], now: Int) -> ConsentRequest? {
    load()
    if case .denied = state(of: identity) { return nil }

    // Only what is new is a question. The classes already allowed are not the
    // user's to decide again, and asking about them a second time would make an
    // expansion look like a first request.
    var already: Set<CapabilityClass> = []
    if case .allowed(let allowed) = state(of: identity) { already = allowed }
    let wanted = Set(classes).subtracting(already)
    guard !wanted.isEmpty else { return nil }

    if let outstanding = asking[identity.id] {
      let merged = Set(outstanding.classes).union(wanted)
      // The same question, asked again too soon, is not asked again.
      if merged == Set(outstanding.classes), now - outstanding.askedAt < Limits.consentRateLimitMs { return nil }
      let again = ConsentRequest(identity: identity, classes: merged.sorted { $0.rawValue < $1.rawValue }, askedAt: now)
      asking[identity.id] = again
      return again
    }

    let request = ConsentRequest(identity: identity, classes: wanted.sorted { $0.rawValue < $1.rawValue }, askedAt: now)
    asking[identity.id] = request
    return request
  }

  /// The question the user has not answered, if one is waiting.
  ///
  /// One at a time: a consent prompt is not an entity and cannot queue alongside
  /// them, so a second program asking while the user is deciding waits its turn.
  func pending() -> ConsentRequest? {
    asking.values.min { $0.askedAt < $1.askedAt }
  }

  /// Record the user's decision, and stop asking.
  /// - Parameters:
  ///   - identity: the observed identity.
  ///   - classes: what the user allowed; empty with `denied` to refuse.
  ///   - denied: whether the user refused.
  ///   - now: current epoch milliseconds.
  func decide(_ identity: ProviderIdentity, classes: [CapabilityClass], denied: Bool, now: Int) {
    load()
    asking[identity.id] = nil
    // Allowing one more class adds to what was allowed, and never replaces it:
    // a decision about a new class is not a decision about the old ones.
    var allowed: Set<CapabilityClass> = []
    if case .allowed(let existing) = state(of: identity) { allowed = existing }
    let total = denied ? [] : allowed.union(classes)
    records[identity.id] = ConsentRecord(
      id: identity.id,
      displayName: identity.displayName,
      classes: total.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue),
      denied: denied,
      decidedAt: now
    )
    save()
  }

  /// Forget a denial or a grant, so the next request is a first request.
  ///
  /// This is the user's move and only the user's: a provider cannot reach it, and
  /// nothing expires into it.
  func forget(_ id: String) {
    load()
    records[id] = nil
    asking[id] = nil
    save()
  }

  /// Every decision on record, for the surface the user reviews them from.
  func decisions() -> [(identity: String, displayName: String, classes: [CapabilityClass], denied: Bool, decidedAt: Int)] {
    load()
    return records.values
      .sorted { $0.decidedAt > $1.decidedAt }
      .map { record in
        (record.id, record.displayName, record.classes.compactMap { CapabilityClass(rawValue: $0) }, record.denied, record.decidedAt)
      }
  }

  /// Ask again, after the user chose to reconsider a program they refused.
  ///
  /// The floor exists so that "reconsider" cannot become a way to be asked
  /// continuously: the user's own action is the only thing that opens this, and
  /// even then not sooner than the stated interval.
  func reconsider(_ identity: ProviderIdentity, now: Int) {
    load()
    guard let record = records[identity.id] else { return }
    if now - record.decidedAt < Limits.reRequestFloorMs { return }
    records[identity.id] = nil
    save()
  }

  // MARK: - What is written down

  private func load() {
    guard !loaded else { return }
    loaded = true
    guard let data = try? Data(contentsOf: store) else { return }
    guard let decoded = try? JSONDecoder().decode([ConsentRecord].self, from: data) else { return }
    for record in decoded { records[record.id] = record }
  }

  /// Write the decisions down, readable by their owner and nobody else.
  ///
  /// A failure here is not worth stopping for: the decision still holds for as
  /// long as Notch runs, and the alternative — refusing a decision the user just
  /// made because a file could not be written — is worse than asking again later.
  private func save() {
    let directory = store.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(records.values.sorted { $0.id < $1.id }) else { return }
    try? data.write(to: store, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)
  }
}
