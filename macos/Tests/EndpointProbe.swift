import Darwin
import Foundation

/// Exercise the endpoint the way a provider would: over the socket.
///
/// The corpus proves what the rules do with a message. This proves the messages
/// get there: that a provider can connect, that Notch knows who it is without
/// being told, that a refusal comes back framed and readable, and that the traps
/// in the address — a stale file, an address too long, a second instance — are
/// handled rather than survived by luck.
@main enum EndpointProbe {
  static func main() {
    // A provider that writes to a socket Notch has closed must get an error, not
    // a signal that ends the process — the contract has no answer for a provider
    // that dies because the other end hung up.
    signal(SIGPIPE, SIG_IGN)
    var failures = 0
    func check(_ value: Bool, _ label: String) {
      if !value {
        failures += 1
        print("FAIL \(label)")
      }
    }

    let root = "/tmp/notch-probe-\(getpid())"
    let path = "\(root)/notch.sock"
    try? FileManager.default.removeItem(atPath: root)

    // MARK: The address is checked before anything is created

    let absurd = "/tmp/" + String(repeating: "n", count: 140) + "/notch.sock"
    let longEndpoint = NotchEndpoint(core: NotchCore(), path: absurd)
    do {
      try longEndpoint.start()
      check(false, "an address that does not fit is refused")
    } catch let error as EndpointError {
      if case .addressTooLong(_, let count) = error {
        check(count > 103, "the refusal states the address length: \(count)")
      } else {
        check(false, "an over-long address is refused for being over-long: \(error)")
      }
    } catch {
      check(false, "an over-long address is refused: \(error)")
    }

    // MARK: A provider connects and is identified

    let core = NotchCore()
    let endpoint = NotchEndpoint(core: core, path: path)
    do {
      try endpoint.start()
    } catch {
      print("FAIL the endpoint starts: \(error)")
      exit(1)
    }

    var status = stat()
    check(lstat(path, &status) == 0, "the socket file exists after start")
    check((status.st_mode & 0o777) == 0o600, "the socket is closed to other users: \(String(status.st_mode & 0o777, radix: 8))")
    check(lstat(root, &status) == 0 && (status.st_mode & 0o777) == 0o700, "the directory is closed to other users")

    guard let provider = ProviderClient(path: path) else {
      print("FAIL a provider can connect")
      exit(1)
    }
    check(waitFor(endpoint) { !$0.identities().isEmpty }, "the connection is accepted")

    let identity = endpoint.identities().first
    let providerID = identity?.id ?? ""
    check(identity?.pid == getpid(), "Notch reads the peer's pid from the socket, not from the provider")
    check(identity?.path.hasSuffix("/dsh-notch") == true, "the peer's executable is read from the operating system")
    check(identity?.codeHash?.isEmpty == false, "the peer's code hash is read, so replacing the binary invalidates consent")

    // MARK: The exchange

    provider.send(["type": "renew"])
    check(provider.reply()?["code"] as? String == "not-registered", "a message before registration is refused, and the reason arrives framed")

    provider.send([
      "type": "register",
      "registration": ["protocolVersion": 1, "displayName": "Probe", "requestedClasses": ["activity", "awaiting"]],
    ])
    let granted = provider.reply()
    check(granted?["type"] as? String == "granted", "registration is answered with a grant")
    let grant = granted?["grant"] as? [String: Any]
    check((grant?["grantedClasses"] as? [String]) == ["activity", "awaiting"], "the grant names the classes")
    check((grant?["limits"] as? [String: Int])?["capsuleCapacity"] == 4, "the grant states the limits it will enforce")

    // A class that was not granted is refused, which is also how this probe
    // synchronises: a reply proves every message sent before it has been applied.
    provider.send(["type": "snapshot", "entities": []])
    provider.send(["type": "upsert", "entity": ["key": "k", "class": "progress", "state": "running", "lifetime": "held"]])
    check(provider.reply()?["code"] as? String == "class-not-granted", "a class that was not granted is refused")
    check(core.held(providerID).isEmpty, "an accepted snapshot is answered with silence, and holds nothing yet")

    provider.send(["type": "upsert", "entity": ["key": "k", "class": "activity", "state": "running", "lifetime": "held"]])
    provider.send(["type": "wat"])
    check(provider.reply()?["code"] as? String == "unknown-message", "an unknown type is refused")
    check(core.held(providerID).count == 1, "the accepted delta was applied")

    provider.send(["type": "upsert", "entity": ["key": "a", "class": "awaiting", "state": "pending", "lifetime": "held", "title": "Ask", "interaction": ["id": "i1", "questions": [["id": "q1", "question": "Proceed?", "options": [["label": "Yes"], ["label": "No"]]]]]]])
    provider.send(["type": "wat"])
    _ = provider.reply()
    check(core.adjudication().expanded?.interaction.id == "i1", "the decision is on screen")
    check(core.adjudication().expanded?.title == "Ask", "the decision keeps the title the provider gave it")

    // MARK: Two frames in one write

    provider.write(Data("{\"type\":\"renew\"}\n{\"type\":\"wat\"}\n".utf8))
    check(provider.reply()?["code"] as? String == "unknown-message", "frames are split on newlines, not on writes")

    // MARK: The user answers, and the provider is told

    let answered = endpoint.answer(interactionID: "i1", answers: ["q1": ["Yes"]])
    check(answered.ok, "the user can answer the decision on screen")
    let settled = provider.reply()
    check(settled?["type"] as? String == "interaction.settled", "the settlement is delivered to the provider")
    check(settled?["interactionId"] as? String == "i1", "the settlement names the interaction")
    check((settled?["outcome"] as? [String: Any])?["status"] as? String == "answered", "the settlement says it was answered")

    // MARK: A question nobody answers is settled at its deadline

    provider.send(["type": "upsert", "entity": ["key": "b", "class": "awaiting", "state": "pending", "lifetime": "held", "interaction": ["id": "i2", "questions": [["id": "q1", "question": "Proceed?", "options": [["label": "Yes"]]]]]]])
    provider.send(["type": "wat"])
    _ = provider.reply()
    check(core.adjudication().expanded?.interaction.id == "i2", "the next decision takes the place the first gave up")
    endpoint.settleDue(now: Int(Date().timeIntervalSince1970 * 1000) + Limits.interactionDeadlineMs)
    check(waitFor(endpoint) { $0.identities().count == 1 }, "the provider is still connected")
    check(provider.reply()?["interactionId"] as? String == "i2", "the provider is told the question timed out")

    // MARK: A second instance

    let second = NotchEndpoint(core: NotchCore(), path: path)
    var refusedSecond = false
    do {
      try second.start()
    } catch let error as EndpointError {
      if case .alreadyRunning = error { refusedSecond = true }
    } catch {
      refusedSecond = false
    }
    check(refusedSecond, "a second Notch on the same address is refused, and says why")

    // MARK: A provider that goes away

    provider.close()
    check(waitFor(endpoint) { $0.identities().isEmpty }, "the endpoint notices a connection that ended")
    check(core.providers().isEmpty, "a provider that left is no longer registered")
    check(core.adjudication().expanded == nil, "and holds nothing on screen")

    // MARK: A socket file left behind by a crash

    endpoint.stop()
    check(lstat(path, &status) != 0, "stopping removes the socket file")
    check(leaveStaleSocket(at: path), "a socket file can be left behind the way a crash leaves one")
    check(lstat(path, &status) == 0, "the stale file is there")

    let restarted = NotchEndpoint(core: NotchCore(), path: path)
    var restartedCleanly = false
    do {
      try restarted.start()
      restartedCleanly = true
    } catch {
      print("FAIL a stale socket file is cleared rather than treated as a conflict: \(error)")
    }
    check(restartedCleanly, "a stale socket file is cleared rather than treated as a conflict")
    restarted.stop()

    // MARK: A directory that is not ours to use

    let shared = "/tmp/notch-probe-open-\(getpid())"
    try? FileManager.default.removeItem(atPath: shared)
    _ = try? FileManager.default.createDirectory(atPath: shared, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o777])
    let open = NotchEndpoint(core: NotchCore(), path: "\(shared)/notch.sock")
    var refusedOpen = false
    do {
      try open.start()
    } catch let error as EndpointError {
      if case .directoryUnsafe = error { refusedOpen = true }
    } catch {
      refusedOpen = false
    }
    check(refusedOpen, "a directory other users can write to is refused")
    try? FileManager.default.removeItem(atPath: shared)
    try? FileManager.default.removeItem(atPath: root)

    print("FAILURES=\(failures)")
    exit(failures == 0 ? 0 : 1)
  }
}

/// Wait for the endpoint to reach a state, asking it to catch up between looks.
///
/// The endpoint applies messages on its own queue, so looking at Core from
/// outside it sees whatever happened to have been applied. `synchronize` is what
/// makes the look a fact rather than a race.
private func waitFor(_ endpoint: NotchEndpoint, seconds: Double = 2, _ condition: (NotchEndpoint) -> Bool) -> Bool {
  let deadline = Date().addingTimeInterval(seconds)
  while Date() < deadline {
    endpoint.synchronize()
    if condition(endpoint) { return true }
    usleep(10_000)
  }
  endpoint.synchronize()
  return condition(endpoint)
}

/// Leave a socket file behind the way a crash does: bound, then abandoned.
private func leaveStaleSocket(at path: String) -> Bool {
  let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
  guard descriptor >= 0 else { return false }
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
  withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    buffer.copyBytes(from: Array(path.utf8.prefix(buffer.count - 1)))
  }
  let size = socklen_t(MemoryLayout<sockaddr_un>.size)
  let bound = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, size) }
  } == 0
  close(descriptor)
  return bound
}

/// A provider, as one would be written against the protocol.
private final class ProviderClient {
  private let descriptor: Int32
  private var pending = Data()

  init?(path: String) {
    descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.copyBytes(from: Array(path.utf8.prefix(buffer.count - 1)))
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, size) }
    }
    guard connected == 0 else {
      Darwin.close(descriptor)
      return nil
    }
    var on: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    setReadTimeout(2)
  }

  /// A read that waits forever is a probe that never reports, so a read that
  /// waits is a read that has already failed.
  private func setReadTimeout(_ seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  func send(_ fields: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
    write(data + Data("\n".utf8))
  }

  func write(_ data: Data) {
    data.withUnsafeBytes { buffer in
      var written = 0
      while written < buffer.count {
        let count: Int = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
        if count <= 0 { return }
        written += count
      }
    }
  }

  /// The next message, or nothing when none arrives before the timeout.
  ///
  /// An accepted message is answered with silence, so "nothing came back" is a
  /// fact this probe relies on rather than a failure of the read.
  func reply(seconds: Int = 2) -> [String: Any]? {
    setReadTimeout(seconds)
    guard let line = nextLine() else { return nil }
    return (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
  }

  private func nextLine() -> Data? {
    while true {
      if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
        let line = pending[pending.startIndex..<newline]
        pending.removeSubrange(pending.startIndex...newline)
        return Data(line)
      }
      var buffer = [UInt8](repeating: 0, count: 4096)
      let count: Int = Darwin.read(descriptor, &buffer, buffer.count)
      guard count > 0 else { return nil }
      pending.append(contentsOf: buffer[0..<count])
    }
  }

  func close() {
    Darwin.close(descriptor)
  }
}
