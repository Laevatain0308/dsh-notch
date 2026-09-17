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
  }
}
