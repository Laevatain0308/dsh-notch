//
//  NotchService.swift
//  DshNotch
//
//  The endpoint, running inside the application.
//
//  Everything the island shows about other programs comes through here: the
//  socket providers connect to, the rules their messages must satisfy, and the
//  decision the user has not answered yet. It is deliberately not part of the
//  board model — that model is DSH's shape, and this is the shape everything
//  else will be built against.
//

import Combine
import Foundation

/// The endpoint, and what the island needs to know about it.
///
/// The endpoint applies everything on its own queue, so this publishes the
/// answers a view needs and nothing else: what the user is being asked, and
/// whether the endpoint is listening at all.
@MainActor
final class NotchService: ObservableObject {
  /// What the island is being asked, which it observes directly.
  ///
  /// Held as a separate object rather than published here so that the view needs
  /// nothing of the transport to draw a decision.
  let inbox = ConsentInbox()
  /// What the providers are showing, composed for the island to draw.
  ///
  /// Published on the main actor on every change the endpoint reports, which is
  /// every message any provider sends. The composition itself is cheap — it is a
  /// walk over what Core holds — so it is recomputed rather than invalidated
  /// selectively, and the view is only told when the result differs.
  @Published private(set) var surface: Surface = Composition.compose(held: [], adjudication: Adjudication(expanded: nil, waiting: nil))
  /// Why the endpoint is not listening, if it is not.
  @Published private(set) var failure: String?
  /// Whether the endpoint is listening for providers.
  @Published private(set) var listening = false

  private let core = NotchCore()
  private let desk: ConsentDesk
  private let endpoint: NotchEndpoint

  init(path: String = Endpoint.path, store: URL = ConsentDesk.storeURL()) {
    desk = ConsentDesk(store: store)
    endpoint = NotchEndpoint(core: core, consent: desk, path: path)
    endpoint.onChange = { [weak self] in
      Task { @MainActor in self?.refresh() }
    }
  }

  /// Begin listening.
  ///
  /// A failure here is reported rather than fatal: the island is still worth
  /// running, and the reason another program cannot reach it is exactly what the
  /// user needs to be told.
  func start() {
    do {
      try endpoint.start()
      listening = true
      failure = nil
    } catch {
      listening = false
      failure = String(describing: error)
      FileHandle.standardError.write(Data("notch: \(error)\n".utf8))
    }
  }

  func stop() {
    endpoint.stop()
    listening = false
  }

  // MARK: - The decision

  /// Allow the program that is waiting, as far as it asked.
  func allow() {
    guard let request = endpoint.consentRequest() else { return }
    endpoint.decide(request.identity, denied: false)
    refresh()
  }

  /// Refuse it. The refusal is recorded, and only the user can open it again.
  func deny() {
    guard let request = endpoint.consentRequest() else { return }
    endpoint.decide(request.identity, denied: true)
    refresh()
  }

  /// Stop presenting the request, without answering it.
  ///
  /// The program is left undecided rather than refused, so a prompt the user did
  /// not read is not a decision they did not make.
  func dismiss() {
    guard let request = endpoint.consentRequest() else { return }
    endpoint.dismiss(request.identity)
    refresh()
  }

  // MARK: - Reading the endpoint

  /// Whether to write what the endpoint holds to standard error.
  ///
  /// The transport is a socket, so it cannot be watched with the tools an HTTP
  /// surface is watched with; this is the replacement, and the reason it is worth
  /// paying for is that the alternative is guessing about a surface you cannot
  /// see into.
  private static let dumping = ProcessInfo.processInfo.environment["DSH_NOTCH_DEBUG"] != nil

  private func refresh() {
    let request = endpoint.consentRequest()
    let prompt = request.map { request in
      ConsentPrompt(
        program: request.identity.displayName,
        path: request.identity.path,
        identifier: request.identity.identifier,
        classes: request.classes
      )
    }
    // `@Published` announces on every assignment, equal or not, and this runs on
    // every message any provider sends, so it is only assigned when it changed.
    if prompt != inbox.prompt { inbox.prompt = prompt }

    // A decision on screen takes the region, so the surface is composed with the
    // prompt the view will actually be showing rather than the one being asked.
    let composed = Composition.compose(
      held: endpoint.inventory(),
      adjudication: endpoint.adjudication(),
      consent: prompt == nil ? nil : request
    )
    if composed != surface { surface = composed }
    if Self.dumping { dump(request: request, surface: composed) }
  }

  /// One line per change: what the user is being asked, and what is being shown.
  private func dump(request: ConsentRequest?, surface: Surface) {
    var parts: [String] = []
    parts.append("consent=\(request.map { "\($0.identity.displayName)[\($0.classes.map(\.rawValue).joined(separator: ","))]" } ?? "none")")
    parts.append("decision=\(surface.decision?.interaction?.id ?? "none")")
    parts.append("waiting=\(surface.waiting?.key ?? "none")")
    parts.append("slots=\(surface.slots.count)")
    parts.append("overflow=\(surface.overflow)")
    parts.append("empty=\(surface.isEmpty)")
    parts.append("open=\(surface.isEmpty ? "board" : "surface")")
    FileHandle.standardError.write(Data("notch: \(parts.joined(separator: " "))\n".utf8))
  }

  /// Ask a provider to do something with one of its entities.
  /// - Parameters:
  ///   - provider: the identity the entity came from.
  ///   - action: one of the names that provider declared.
  ///   - key: the entity the user activated.
  func invoke(provider: String, action: String, key: String) {
    endpoint.invoke(provider, action: action, key: key)
  }

  /// Answer a provider's decision, which is the whole point of the surface.
  /// - Parameters:
  ///   - interactionID: the id of the decision on screen.
  ///   - answers: the chosen option labels, keyed by question id.
  /// - Returns: whether it was accepted.
  @discardableResult
  func answer(interactionID: String, answers: [String: [String]]) -> Bool {
    let outcome = endpoint.answer(interactionID: interactionID, answers: answers)
    refresh()
    return outcome.ok
  }
}
