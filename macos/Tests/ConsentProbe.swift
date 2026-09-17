import Darwin
import Foundation

/// Who may speak, and what it takes to be allowed to.
///
/// The rules here are the ones that decide whether a program can put something on
/// the user's screen, so the probe is written the way the threat is: a program
/// that connects repeatedly, that asks for more than it was allowed, and that
/// reconnects after being refused.
@main enum ConsentProbe {
  static func main() {
    signal(SIGPIPE, SIG_IGN)
    var failures = 0
    var checks = 0
    func check(_ value: Bool, _ label: String) {
      checks += 1
      if !value {
        failures += 1
        print("FAIL \(label)")
      }
    }

    let root = "/tmp/notch-consent-\(getpid())"
    let path = "\(root)/notch.sock"
    let store = URL(fileURLWithPath: "\(root)/consent.json")
    try? FileManager.default.removeItem(atPath: root)

    let core = NotchCore()
    let desk = ConsentDesk(store: store)
    let endpoint = NotchEndpoint(core: core, consent: desk, path: path)
    do {
      try endpoint.start()
    } catch {
      print("FAIL the endpoint starts: \(error)")
      exit(1)
    }

    guard let provider = Provider(path: path) else {
      print("FAIL a provider can connect")
      exit(1)
    }
    check(waitFor(endpoint) { !$0.identities().isEmpty }, "the connection is accepted")

    let identity = endpoint.identities().first
    let id = identity?.id ?? ""

    // MARK: Nothing is rendered, and nothing is queued

    provider.send(["type": "renew"])
    check(provider.reply()?["code"] as? String == "not-consented", "a message from an unknown program is refused")

    provider.send(registration(["activity", "result"]))
    check(provider.reply()?["code"] as? String == "not-consented", "registering does not allow it either")

    provider.send(["type": "snapshot", "entities": []])
    check(provider.reply()?["code"] as? String == "not-consented", "a snapshot from an unknown program is refused")
    provider.send(["type": "upsert", "entity": ["key": "a", "class": "activity", "state": "running", "lifetime": "held"]])
    check(provider.reply()?["code"] as? String == "not-consented", "and so is state")
    endpoint.synchronize()
    check(core.held(id).isEmpty, "the entities of an unconsented program are dropped, not queued")
    check(core.adjudication().expanded == nil, "and nothing of it is on screen")

    // MARK: The user is asked once, and about the classes

    let request = endpoint.consentRequest()
    check(request?.identity.id == id, "the user is asked about the program that connected")
    check(request?.identity.pid == getpid(), "and about what was observed of it, not what it said")
    check(request?.classes.sorted { $0.rawValue < $1.rawValue } == [.activity, .result], "the request states the classes it asked for")

    // Asking again immediately does not produce a second question.
    provider.send(registration(["activity", "result"]))
    _ = provider.reply()
    check(endpoint.consentRequest()?.askedAt == request?.askedAt, "a program cannot make a prompt appear again at will")

    // MARK: Allowing lets it in

    guard let observed = identity else {
      print("FAIL the program was identified")
      exit(1)
    }
    endpoint.decide(observed, denied: false)
    let granted = provider.reply()
    check(granted?["type"] as? String == "consent.granted", "allowing tells the program, which does not have to ask again")

    provider.send(registration(["activity"]))
    let grant = provider.reply()
    check(grant?["type"] as? String == "granted", "registering after being allowed is granted")
    check((grant?["grant"] as? [String: Any])?["grantedClasses"] as? [String] == ["activity"], "and grants the classes it asked for")

    provider.send(["type": "snapshot", "entities": []])
    provider.send(["type": "upsert", "entity": ["key": "a", "class": "activity", "state": "running", "lifetime": "held"]])
    provider.send(["type": "wat"])
    _ = provider.reply()
    endpoint.synchronize()
    check(core.held(id).count == 1, "an allowed program's entities are rendered")

    // MARK: A class it was not allowed needs a new decision

    provider.send(registration(["activity", "awaiting"]))
    check(provider.reply()?["code"] as? String == "not-consented", "asking for a new class needs a new decision")
    let widened = endpoint.consentRequest()
    check(widened?.classes == [.awaiting], "and the question is only about what is being added")
    endpoint.decide(observed, denied: false)
    _ = provider.reply()
    provider.send(registration(["activity", "awaiting"]))
    check(provider.reply()?["type"] as? String == "granted", "the widened request is granted once the user allows it")

    // MARK: The decision outlives the connection

    endpoint.synchronize()
    check(desk.state(of: observed) == .allowed(classes: [.activity, .result, .awaiting]), "the decisions are on record")
    let reopened = ConsentDesk(store: store)
    check(
      reopened.state(of: observed) == .allowed(classes: [.activity, .result, .awaiting]),
      "and survive a restart, with the class allowed later added to the ones allowed before rather than replacing them"
    )

    let contents = (try? Data(contentsOf: store)) ?? Data()
    check(!contents.isEmpty, "the record is written down")

    // A program whose code changed is a program Notch has not been told about.
    let replaced = ProviderIdentity(pid: observed.pid, path: observed.path, identifier: observed.identifier, codeHash: "0000000000000000000000000000000000000000")
    check(reopened.state(of: replaced) == .undecided, "a program replaced in place is not the program that was allowed")

    // MARK: Refusing is remembered

    let strangerPath = "\(root)/stranger.sock"
    let strangerCore = NotchCore()
    let strangerDesk = ConsentDesk(store: URL(fileURLWithPath: "\(root)/stranger.json"))
    let strangerEndpoint = NotchEndpoint(core: strangerCore, consent: strangerDesk, path: strangerPath)
    do {
      try strangerEndpoint.start()
    } catch {
      print("FAIL the second endpoint starts: \(error)")
      exit(1)
    }
    guard let refused = Provider(path: strangerPath) else {
      print("FAIL a second provider can connect")
      exit(1)
    }
    check(waitFor(strangerEndpoint) { !$0.identities().isEmpty }, "the second program connects")
    guard let stranger = strangerEndpoint.identities().first else {
      print("FAIL the second program is identified")
      exit(1)
    }
    refused.send(registration(["result"]))
    _ = refused.reply()
    strangerEndpoint.decide(stranger, denied: true)
    check(refused.reply()?["type"] as? String == "consent.denied", "refusing tells the program")

    refused.send(registration(["result"]))
    check(refused.reply()?["code"] as? String == "consent-denied", "and a refused program stays refused")
    check(strangerEndpoint.consentRequest() == nil, "and cannot make the user be asked again by asking again")
    check(strangerDesk.state(of: stranger) == .denied, "the refusal is on record")

    // MARK: The user opens it again, and only the user

    strangerDesk.reconsider(stranger, now: Int(Date().timeIntervalSince1970 * 1000))
    check(strangerDesk.state(of: stranger) == .denied, "reconsidering is not immediate: the floor has not passed")

    strangerDesk.reconsider(stranger, now: Int(Date().timeIntervalSince1970 * 1000) + Limits.reRequestFloorMs)
    check(strangerDesk.state(of: stranger) == .undecided, "after the floor, the next request is a first request")

    let forgetting = ConsentDesk(store: URL(fileURLWithPath: "\(root)/stranger.json"))
    check(forgetting.state(of: stranger) == .undecided, "clearing the record is written down too")
    forgetting.forget(stranger.id)
    check(forgetting.decisions().isEmpty, "and forgetting removes it from the record the user reviews")

    // MARK: One question at a time

    let crowded = ConsentDesk(store: URL(fileURLWithPath: "\(root)/crowded.json"))
    let first = ProviderIdentity(pid: 1, path: "/Applications/One.app/Contents/MacOS/One", identifier: "one", codeHash: "a")
    let second = ProviderIdentity(pid: 2, path: "/Applications/Two.app/Contents/MacOS/Two", identifier: "two", codeHash: "b")
    _ = crowded.ask(first, classes: [.progress], now: 1000)
    _ = crowded.ask(second, classes: [.result], now: 1001)
    check(crowded.pending()?.identity.id == first.id, "the question the user sees is the one that was asked first")
    crowded.decide(first, classes: [.progress], denied: false, now: 1002)
    check(crowded.pending()?.identity.id == second.id, "and the next one is asked after that")

    // MARK: What the user reviews

    check(crowded.decisions().count == 1, "the decisions on record are the ones the user made")
    check(crowded.decisions().first?.classes == [.progress], "with the classes that were allowed")
    check(crowded.decisions().first?.identity == first.id, "and the program they were allowed for")

    provider.close()
    refused.close()
    endpoint.stop()
    strangerEndpoint.stop()
    try? FileManager.default.removeItem(atPath: root)
    print("CHECKS=\(checks)")
    print("FAILURES=\(failures)")
    exit(failures == 0 ? 0 : 1)
  }

  /// A registration asking for the stated classes.
  private static func registration(_ classes: [String]) -> [String: Any] {
    ["type": "register", "registration": ["protocolVersion": 1, "requestedClasses": classes]]
  }
}

/// Wait for the endpoint to reach a state, asking it to catch up between looks.
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

/// A provider, as one would be written against the protocol.
private final class Provider {
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

  private func setReadTimeout(_ seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  func send(_ fields: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
    let line = data + Data("\n".utf8)
    line.withUnsafeBytes { buffer in
      var written = 0
      while written < buffer.count {
        let count: Int = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
        if count <= 0 { return }
        written += count
      }
    }
  }

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
