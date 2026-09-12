import Foundation

struct RuntimeFile: Decodable {
  var origin: String
  var token: String
}

struct NotchOption: Decodable, Identifiable {
  var label: String
  var description: String?
  var id: String { label }
}

struct NotchQuestion: Decodable, Identifiable {
  var id: String
  var question: String
  var detail: String?
  var header: String?
  var options: [NotchOption]?
  var multiSelect: Bool?
}

struct NotchApproval: Decodable {
  var id: String
  var toolName: String
  var reason: String?
}

struct NotchAsk: Decodable {
  var id: String
  var questions: [NotchQuestion]
}

struct NotchLastTurn: Decodable {
  var at: Double
  var kind: String
  var failed: Bool
}

struct NotchRow: Decodable, Identifiable {
  var id: String
  var title: String
  var child: Bool
  var busy: Bool
  var unread: Bool
  var lastTurn: NotchLastTurn?
  var approval: NotchApproval?
  var ask: NotchAsk?

  var needsAction: Bool { approval != nil || ask != nil }
  /// A red lamp is a finished unsuccessful turn, never a session that is still running.
  var isFailedResult: Bool { lastTurn?.failed == true && !busy && !needsAction }
}

struct NotchSnapshot: Decodable {
  var ok: Bool
  var generatedAt: Double
  var origin: String
  var rows: [NotchRow]
}

enum NotchClientError: Error {
  case noRuntime
  case http(Int)
}

// Preview-only transport: no credential reads, network, or live session actions.
final class NotchClient: @unchecked Sendable {
  func reloadRuntime() throws { throw NotchClientError.noRuntime }
  func status() async throws -> NotchSnapshot { throw NotchClientError.noRuntime }
  func approve(id: String, outcome: String) async throws {}
  @MainActor func answer(id: String, answers: [[String: Any]]) async throws {}
  func seen(sessionId: String) async throws {}
  func seenAll() async throws {}
  func focus(sessionId: String) async throws {}
}
