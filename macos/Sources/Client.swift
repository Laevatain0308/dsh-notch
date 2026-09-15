import Darwin
import Foundation

struct RuntimeFile: Decodable {
  var origin: String
  var token: String
  /// Host process that wrote this file; absent in files written before 0.4.0.
  var pid: Int?
}

/// The connection file this Notch reads, and the Host rewrites on every start.
func runtimeFileURL() -> URL {
  ProcessInfo.processInfo.environment["DSH_NOTCH_RUNTIME_FILE"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/dsh-notch/runtime.json")
}

/// Whether the DSH Host that owns this Notch is still alive.
///
/// The Host stops this process when it shuts down gracefully. A Host that was
/// killed instead cannot, so the overlay answers the question itself and exits
/// rather than sitting on screen attached to a dead origin.
/// - Returns: `nil` while no Host pid is known, which is not a shutdown.
func hostProcessIsAlive() -> Bool? {
  guard let data = try? Data(contentsOf: runtimeFileURL()),
        let file = try? JSONDecoder().decode(RuntimeFile.self, from: data),
        let pid = file.pid, pid > 0 else { return nil }
  if kill(pid_t(pid), 0) == 0 { return true }
  // EPERM means the pid exists but belongs to another user.
  return errno == EPERM
}

struct NotchOption: Decodable, Identifiable, Equatable {
  var label: String
  var description: String?
  var id: String { label }
}

struct NotchQuestion: Decodable, Identifiable, Equatable {
  var id: String
  var question: String
  var detail: String?
  var header: String?
  var options: [NotchOption]?
  var multiSelect: Bool?
}

struct NotchApproval: Decodable, Equatable {
  var id: String
  var toolName: String
  var reason: String?
}

struct NotchAsk: Decodable, Equatable {
  var id: String
  var questions: [NotchQuestion]
}

struct NotchLastTurn: Decodable, Equatable {
  var at: Double
  var kind: String
  var failed: Bool
}

struct NotchRow: Decodable, Identifiable, Equatable {
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

final class NotchClient: @unchecked Sendable {
  private var origin = ""
  private var token = ""

  func reloadRuntime() throws {
    let data = try Data(contentsOf: runtimeFileURL())
    let file = try JSONDecoder().decode(RuntimeFile.self, from: data)
    origin = file.origin
    token = file.token
  }

  func status() async throws -> NotchSnapshot {
    try reloadRuntime()
    return try await get("/dsh-notch/status")
  }

  func approve(id: String, outcome: String) async throws {
    try await post("/dsh-notch/approve", body: ["id": id, "outcome": outcome])
  }

  @MainActor
  func answer(id: String, answers: [[String: Any]]) async throws {
    try await postJSON("/dsh-notch/answer", payload: ["id": id, "answers": answers])
  }

  func seen(sessionId: String) async throws {
    try await post("/dsh-notch/seen", body: ["sessionId": sessionId])
  }

  func seenAll() async throws {
    try await postJSON("/dsh-notch/seen", payload: ["all": true])
  }

  func focus(sessionId: String) async throws {
    try await post("/dsh-notch/focus", body: ["sessionId": sessionId])
  }

  private func get(_ path: String) async throws -> NotchSnapshot {
    var request = try makeRequest(path)
    request.httpMethod = "GET"
    let (data, response) = try await URLSession.shared.data(for: request)
    try throwIfBad(response)
    return try JSONDecoder().decode(NotchSnapshot.self, from: data)
  }

  private func post(_ path: String, body: [String: String]) async throws {
    try await postJSON(path, payload: body)
  }

  private func postJSON(_ path: String, payload: [String: Any]) async throws {
    var request = try makeRequest(path)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (_, response) = try await URLSession.shared.data(for: request)
    try throwIfBad(response)
  }

  private func makeRequest(_ path: String) throws -> URLRequest {
    if origin.isEmpty { try reloadRuntime() }
    guard let url = URL(string: origin + path) else { throw NotchClientError.noRuntime }
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }

  private func throwIfBad(_ response: URLResponse) throws {
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status < 200 || status >= 300 { throw NotchClientError.http(status) }
  }
}
