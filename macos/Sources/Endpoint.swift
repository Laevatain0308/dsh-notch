//
//  Endpoint.swift
//  DshNotch
//
//  The address providers connect to, and the connections themselves.
//
//  Notch owns the endpoint: a local stream socket carrying newline-delimited
//  JSON. Providers connect to it, and Notch takes their identity from the socket
//  rather than from anything they say — a Unix socket yields the peer's process
//  id through socket credentials, which a provider cannot forge. That is the
//  whole reason the transport is a socket and not loopback HTTP: over TCP a
//  connection cannot be attributed to a process without scanning the process
//  table, and asking a provider for its own pid and then believing it is exactly
//  the "identity is claimed, not observed" failure the design forbids.
//
//  Framing is newline-delimited JSON. `JSONSerialization` never emits a raw
//  newline inside a string, so a newline delimits unambiguously, and the stream
//  stays readable with ordinary tools.
//

import Darwin
import Foundation
import Security

/// Where providers connect.
///
/// Short and fixed, never derived from a home directory: a Unix socket address
/// is limited to 104 bytes on macOS, and a path built from a long user name can
/// silently exceed it. The Codex app-server daemon has exactly that bug — an
/// over-long address falls back to a server nobody else can reach, and the
/// failure is invisible — so this refuses to start instead of truncating.
enum Endpoint {
  /// The directory the socket lives in, created 0700 and owned by this user.
  static let directory = "/tmp/notch"
  /// The socket itself.
  static let path = "/tmp/notch/notch.sock"
  /// How many bytes `sun_path` holds, terminator included.
  static let addressCapacity = 104
}

/// Who a connection is, as the operating system reports it.
///
/// The pid is not part of the identity: it changes every time the program runs.
/// What consent is pinned to is the executable and its code signature, so
/// replacing an authorized program does not inherit its authority.
struct ProviderIdentity: Equatable, Sendable {
  /// The peer's process id, for display and for the record.
  let pid: pid_t
  /// The executable the peer is running.
  let path: String
  /// The signing identifier, when the binary has one.
  let identifier: String?
  /// The hash of the code the peer is running, which changes when it does.
  let codeHash: String?

  /// The stable identity consent is pinned to.
  var id: String {
    "\(path)#\(codeHash ?? "unsigned")"
  }

  /// What the user is shown for this provider.
  var displayName: String {
    (path as NSString).lastPathComponent
  }

  /// Read the identity of one connected peer.
  /// - Parameter descriptor: the accepted connection.
  /// - Returns: the identity, or nothing when the peer cannot be identified —
  ///   in which case the connection is refused rather than trusted.
  static func of(_ descriptor: Int32) -> ProviderIdentity? {
    var pid: pid_t = 0
    var size = socklen_t(MemoryLayout<pid_t>.size)
    // A peer that has already gone gives `ENOTCONN` rather than a pid, which is
    // a connection there is nothing to do with.
    guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return nil }

    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(MAXPATHLEN)) > 0 else { return nil }
    let executable = String(cString: path)

    var identifier: String?
    var codeHash: String?
    var code: SecStaticCode?
    if SecStaticCodeCreateWithPath(URL(fileURLWithPath: executable) as CFURL, [], &code) == errSecSuccess, let code {
      var information: CFDictionary?
      let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
      if SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
         let fields = information as? [String: Any] {
        identifier = fields["identifier"] as? String
        // The hash of the code actually running: a binary replaced in place
        // produces a different one, which is what invalidates a grant.
        if let hashes = fields["cdhashes"] as? [Data], let first = hashes.first {
          codeHash = first.map { String(format: "%02x", $0) }.joined()
        }
      }
    }
    return ProviderIdentity(pid: pid, path: executable, identifier: identifier, codeHash: codeHash)
  }
}

/// Why the endpoint could not start.
enum EndpointError: Error, CustomStringConvertible {
  /// The address does not fit the platform's limit.
  case addressTooLong(String, Int)
  /// The socket's directory is not ours to use.
  case directoryUnsafe(String)
  /// Another Notch is already listening.
  case alreadyRunning(String)
  /// The socket could not be created, bound or listened on.
  case failed(String, Int32)

  var description: String {
    switch self {
    case .addressTooLong(let path, let count):
      return "the socket address \(path) is \(count) bytes, and this platform accepts at most \(Endpoint.addressCapacity - 1)"
    case .directoryUnsafe(let reason):
      return "refusing to use the socket directory: \(reason)"
    case .alreadyRunning(let path):
      return "another Notch is already listening on \(path)"
    case .failed(let call, let code):
      return "\(call) failed: \(String(cString: strerror(code)))"
    }
  }
}

/// Notch's endpoint: it listens, reads providers, and answers them.
///
/// Every call into `NotchCore` happens on one serial queue. Core is the one
/// object in the process that must not be touched from two threads, and a
/// provider's message is small, so serialising them costs nothing that matters.
final class NotchEndpoint {
  private let core: NotchCore
  private let consent: ConsentDesk
  private let path: String
  private let queue = DispatchQueue(label: "notch.endpoint")

  private var listener: Int32 = -1
  private var accepts: DispatchSourceRead?
  private var timer: DispatchSourceTimer?
  private var connections: [ProviderID: Connection] = [:]
  private var running = false

  /// One connected provider.
  private final class Connection {
    let descriptor: Int32
    let identity: ProviderIdentity
    var pending = Data()
    var source: DispatchSourceRead?

    init(descriptor: Int32, identity: ProviderIdentity) {
      self.descriptor = descriptor
      self.identity = identity
    }
  }

  init(core: NotchCore, consent: ConsentDesk = ConsentDesk(), path: String = Endpoint.path) {
    self.core = core
    self.consent = consent
    self.path = path
  }

  /// Begin listening.
  ///
  /// Creating the address is the part with traps in it: an address that does not
  /// fit silently becomes a socket nobody can reach, and a socket file left by a
  /// crash makes the next start look like a conflict.
  /// - Throws: `EndpointError` when the address cannot be used, which is a
  ///   reason to tell the user rather than to fall back to something else.
  func start() throws {
    let length = path.utf8.count
    guard length < Endpoint.addressCapacity else { throw EndpointError.addressTooLong(path, length) }
    try prepareDirectory()

    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw EndpointError.failed("socket", errno) }

    do {
      try bindListener(descriptor)
    } catch {
      Darwin.close(descriptor)
      throw error
    }

    guard listen(descriptor, 16) == 0 else {
      let code = errno
      Darwin.close(descriptor)
      unlink(path)
      throw EndpointError.failed("listen", code)
    }
    // The socket file is the first gate on who may connect at all, so it is
    // closed to everyone but its owner before anyone is accepted.
    chmod(path, 0o600)
    listener = descriptor
    running = true

    startAccepting()
    startLeaseTimer()
    FileHandle.standardError.write(Data("notch: listening on \(path)\n".utf8))
  }

  /// Stop listening and remove the address.
  func stop() {
    running = false
    timer?.cancel()
    timer = nil
    accepts?.cancel()
    accepts = nil
    if listener >= 0 {
      Darwin.close(listener)
      listener = -1
    }
    for connection in connections.values {
      connection.source?.cancel()
      connection.source = nil
    }
    connections.removeAll()
    unlink(path)
  }

  /// The providers currently connected, for the management surface.
  func identities() -> [ProviderIdentity] {
    connections.values.map(\.identity)
  }

  /// Deliver the user's answer, and tell the provider what became of it.
  ///
  /// The user answers from Notch's own surface, which is not the endpoint's
  /// queue, so this is where an answer enters it — and where the settlement
  /// leaves. Who the decision belonged to has to be read before the answer is
  /// applied: answering gives the seat up, and with it the only thing that says
  /// which provider is waiting to hear.
  /// - Parameters:
  ///   - interactionID: the id of the decision on screen.
  ///   - answers: the chosen option labels, keyed by question id.
  /// - Returns: the settlement to report, or why the answer was refused.
  func answer(interactionID: String, answers: [String: [String]]) -> AnswerOutcome {
    queue.sync {
      let answering = core.adjudication().expanded?.provider
      let outcome = core.answer(interactionID: interactionID, answers: answers)
      guard case .answered(let settlement) = outcome, let answering, let connection = connections[answering] else {
        return outcome
      }
      send(encoded(settlement), to: connection)
      return outcome
    }
  }

  /// Settle decisions the clock has passed, and tell the providers that raised
  /// them.
  ///
  /// Called by the lease timer, and by anything that has to move the clock
  /// itself: a test, or the machine waking from sleep, where the timer that
  /// would have fired did not.
  /// - Parameter now: current epoch milliseconds.
  func settleDue(now: Int) {
    queue.sync { tick(now: now) }
  }

  /// Wait until everything already received has been applied.
  ///
  /// Messages are applied on the endpoint's own queue, so anything outside it —
  /// the management surface, or a probe — cannot look at Core and see a
  /// consistent picture without asking it to catch up first.
  func synchronize() {
    queue.sync {}
  }

  // MARK: - The address

  /// Create the socket's directory, or refuse to use one that is not ours.
  ///
  /// `/tmp` is world-writable, so another user could have created this directory
  /// first and be waiting to answer in Notch's place. The permission bits and the
  /// owner are therefore checked rather than assumed.
  private func prepareDirectory() throws {
    let directory = (path as NSString).deletingLastPathComponent
    let manager = FileManager.default
    if !manager.fileExists(atPath: directory) {
      try manager.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    var status = stat()
    guard lstat(directory, &status) == 0 else {
      throw EndpointError.directoryUnsafe("it cannot be read")
    }
    guard (status.st_mode & S_IFMT) == S_IFDIR else {
      throw EndpointError.directoryUnsafe("it is not a directory")
    }
    guard status.st_uid == getuid() else {
      throw EndpointError.directoryUnsafe("it belongs to another user")
    }
    guard (status.st_mode & 0o077) == 0 else {
      throw EndpointError.directoryUnsafe("it is readable by other users")
    }
  }

  /// Bind the listener, clearing a socket file left behind by a crash.
  private func bindListener(_ descriptor: Int32) throws {
    if bind(descriptor, path) != 0 {
      let code = errno
      guard code == EADDRINUSE else { throw EndpointError.failed("bind", code) }
      // A file already exists. It is a conflict only if something is actually
      // listening there: after a crash the file outlives the process, and
      // treating that as "already running" would make the app unstartable.
      guard !isListening() else { throw EndpointError.alreadyRunning(path) }
      unlink(path)
      guard bind(descriptor, path) == 0 else { throw EndpointError.failed("bind", errno) }
    }
  }

  /// Whether anything is accepting connections at the address.
  private func isListening() -> Bool {
    let probe = socket(AF_UNIX, SOCK_STREAM, 0)
    guard probe >= 0 else { return false }
    defer { Darwin.close(probe) }
    return connect(probe, path)
  }

  /// Bind an address in the form `bind(2)` wants.
  private func bind(_ descriptor: Int32, _ path: String) -> Int32 {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.copyBytes(from: Array(path.utf8.prefix(buffer.count - 1)))
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    return withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, size) }
    }
  }

  /// Connect a socket to the address, answering whether it succeeded.
  private func connect(_ descriptor: Int32, _ path: String) -> Bool {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.copyBytes(from: Array(path.utf8.prefix(buffer.count - 1)))
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    return withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, size) }
    } == 0
  }

  // MARK: - Connections

  /// Accept connections whenever one is waiting.
  ///
  /// A read source rather than a loop around `accept`: a loop has to block, and
  /// the queue it would block on is the one that applies messages — a listener
  /// waiting for a provider would stop Notch from answering the provider it
  /// already has.
  private func startAccepting() {
    // The source is only consulted when the kernel says a connection is waiting,
    // so accepting never has to wait; the descriptor is made non-blocking to keep
    // that true while draining several at once.
    _ = fcntl(listener, F_SETFL, O_NONBLOCK)
    let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
    source.setEventHandler { [weak self] in self?.acceptReady() }
    source.resume()
    accepts = source
  }

  /// Accept every connection that is ready, and no more.
  private func acceptReady() {
    while running {
      let descriptor = Darwin.accept(listener, nil, nil)
      guard descriptor >= 0 else {
        if errno == EINTR { continue }
        if errno != EAGAIN && errno != EWOULDBLOCK && running {
          FileHandle.standardError.write(Data("notch: accept failed: \(String(cString: strerror(errno)))\n".utf8))
        }
        return
      }
      // A provider that dies mid-write must not take Notch down with it.
      var on: Int32 = 1
      setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

      // A peer that cannot be identified is not a peer Notch can trust, and
      // there is nothing to tell it: the connection is simply closed.
      guard let identity = ProviderIdentity.of(descriptor) else {
        // A peer that cannot be identified is not one Notch can trust, and there
        // is nothing useful to tell it: the connection is refused.
        FileHandle.standardError.write(Data("notch: refused a connection that could not be identified\n".utf8))
        Darwin.close(descriptor)
        continue
      }
      let connection = Connection(descriptor: descriptor, identity: identity)
      connections[identity.id] = connection
      watch(connection)
    }
  }

  /// Read one connection on the endpoint's own queue.
  ///
  /// A read source rather than a thread parked in `read`, and not only to keep
  /// the thread count down: an accepted socket inherits the listener's
  /// non-blocking flag, so a plain `read` returns `EAGAIN` the moment there is
  /// nothing waiting — which, read as an end of stream, would hang up on every
  /// provider the instant it connected.
  private func watch(_ connection: Connection) {
    let source = DispatchSource.makeReadSource(fileDescriptor: connection.descriptor, queue: queue)
    source.setEventHandler { [weak self] in self?.receiveReady(connection) }
    // The descriptor belongs to the source now, so it is closed exactly once, by
    // the source, however the connection ends.
    source.setCancelHandler { Darwin.close(connection.descriptor) }
    source.resume()
    connection.source = source
  }

  /// Read everything one connection has waiting.
  private func receiveReady(_ connection: Connection) {
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = Darwin.read(connection.descriptor, &buffer, buffer.count)
      if count > 0 {
        append(Data(buffer[0..<count]), to: connection)
        continue
      }
      if count < 0 && errno == EINTR { continue }
      // Nothing waiting is not the end of anything; a closed socket is.
      if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
      hangUp(connection)
      return
    }
  }

  /// Add bytes to a connection's buffer and act on every complete frame.
  ///
  /// Frames are split on newlines rather than on reads, because a write is not a
  /// message: a provider may send two in one write, or one across two.
  private func append(_ chunk: Data, to connection: Connection) {
    connection.pending.append(chunk)
    while let newline = connection.pending.firstIndex(of: UInt8(ascii: "\n")) {
      let frame = connection.pending[connection.pending.startIndex..<newline]
      connection.pending.removeSubrange(connection.pending.startIndex...newline)
      guard !frame.isEmpty else { continue }
      deliver(Data(frame), from: connection)
    }
  }

  /// Read one message, apply it, and answer it.
  ///
  /// Nothing reaches Core until the user has allowed the program that sent it.
  /// The gate is here rather than in Core because it is the one decision that
  /// depends on who the peer is, and only the transport knows that.
  private func deliver(_ frame: Data, from connection: Connection) {
    let message = ProviderMessage.decode(from: frame)
    let provider = connection.identity.id
    let at = now()

    switch consent.state(of: connection.identity) {
    case .denied:
      // The refusal is recorded, and only the user can open it again: a provider
      // that could re-open it by reconnecting would be able to ask forever.
      send(refusal(.consentDenied, "the user has refused this program"), to: connection)
      return
    case .undecided:
      askIfNew(connection, message: message, at: at)
      send(refusal(.notConsented, "the user has not allowed this program yet"), to: connection)
      return
    case .allowed(let classes):
      // A program that was allowed to show progress is not thereby allowed to ask
      // the user to decide something: a class it was not allowed needs a new
      // decision, and until then it is asking for more than it has.
      if case .register(let fields) = message,
         let asked = requestedClasses(fields),
         !asked.isSubset(of: classes) {
        askIfNew(connection, message: message, at: at)
        send(refusal(.notConsented, "the user has not allowed every class this program is asking for"), to: connection)
        return
      }
      core.connect(provider, displayName: connection.identity.displayName)
    }

    let outcome = core.receive(provider, message, now: at)

    switch outcome {
    case .refused(let refusal):
      send(self.refusal(refusal.code, refusal.reason), to: connection)
    case .accepted(let grant):
      guard let grant else { return }
      send([
        "type": "granted",
        "grant": [
          "protocolVersion": grant.protocolVersion,
          "grantedClasses": grant.grantedClasses.map(\.rawValue),
          "limits": Limits.asJSON,
        ],
      ], to: connection)
    }
  }

  /// Put a program's request in front of the user, if it is not already there.
  ///
  /// A request arises only from a connection that asked for something, which is
  /// what stops a program from making a prompt appear whenever it likes.
  private func askIfNew(_ connection: Connection, message: ProviderMessage, at: Int) {
    guard case .register(let fields) = message else { return }
    let classes = requestedClasses(fields) ?? []
    guard !classes.isEmpty else { return }
    _ = consent.ask(connection.identity, classes: classes.sorted { $0.rawValue < $1.rawValue }, now: at)
  }

  /// The classes a registration asks for, as far as they can be read.
  private func requestedClasses(_ fields: [String: Any]) -> Set<CapabilityClass>? {
    guard let registration = Wire.object(fields["registration"]), let asked = Wire.array(registration["requestedClasses"]) else {
      return nil
    }
    return Set(asked.compactMap { Wire.string($0) }.compactMap { CapabilityClass(rawValue: $0) })
  }

  /// What the user has not decided yet, which is what the consent surface shows.
  func consentRequest() -> ConsentRequest? {
    queue.sync { consent.pending() }
  }

  /// Record the user's decision, and tell the program what it was.
  ///
  /// Allowing is what lets the program register, so the granted message is what
  /// it is waiting for rather than something it has to ask about again.
  /// - Parameters:
  ///   - identity: the observed program the decision is about.
  ///   - denied: whether the user refused it.
  ///   - now: current epoch milliseconds.
  func decide(_ identity: ProviderIdentity, denied: Bool) {
    queue.sync {
      let request = consent.pending()
      let classes = request?.identity.id == identity.id ? request?.classes ?? [] : []
      consent.decide(identity, classes: classes, denied: denied, now: now())
      guard let connection = connections[identity.id] else { return }
      send(denied ? ["type": "consent.denied"] : ["type": "consent.granted"], to: connection)
    }
  }

  /// Whether the user's decision is even reached, for a program that asked long
  /// enough ago that the interval has passed.
  func reconsider(_ identity: ProviderIdentity) {
    queue.sync { consent.reconsider(identity, now: now()) }
  }

  /// Forget a decision entirely, so the next request is a first request.
  func forget(_ identity: ProviderIdentity) {
    queue.sync { consent.forget(identity.id) }
  }

  /// One refusal, as a provider is told about it.
  private func refusal(_ code: RefusalCode, _ reason: String) -> [String: Any] {
    ["type": "refused", "code": code.rawValue, "reason": reason]
  }

  /// Forget a connection that ended.
  private func hangUp(_ connection: Connection) {
    connection.source?.cancel()
    connection.source = nil
    let provider = connection.identity.id
    connections[provider] = nil
    Darwin.close(connection.descriptor)
    // A provider that vanished leaves decisions nobody can answer, so Core
    // settles them rather than leaving the user looking at a question whose
    // asker is gone.
    let settled = core.disconnect(provider)
    if !settled.isEmpty {
      FileHandle.standardError.write(Data("notch: \(provider) disconnected with \(settled.count) decision(s) outstanding\n".utf8))
    }
  }

  // MARK: - Time

  /// Settle what the clock settles, and tell whoever is still there.
  private func startLeaseTimer() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + .milliseconds(Limits.leaseRenewMs), repeating: .milliseconds(Limits.leaseRenewMs), leeway: .milliseconds(200))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.tick(now: self.now())
    }
    timer.resume()
    self.timer = timer
  }

  private func tick(now: Int) {
    for entry in core.tick(now: now) {
      guard let connection = connections[entry.provider] else { continue }
      send(encoded(entry.settlement), to: connection)
    }
  }

  /// The current time in epoch milliseconds, which is what the protocol counts in.
  private func now() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
  }

  // MARK: - Writing

  /// One settlement, as the provider is told about it.
  private func encoded(_ settlement: Settlement) -> [String: Any] {
    var outcome: [String: Any] = [:]
    switch settlement.outcome {
    case .answered(let answers):
      outcome["status"] = "answered"
      outcome["answers"] = answers
    case .cancelled(let reason):
      outcome["status"] = "cancelled"
      outcome["reason"] = reason
    }
    return [
      "type": "interaction.settled",
      "key": settlement.key,
      "interactionId": settlement.interactionID,
      "outcome": outcome,
    ]
  }

  /// Write one message to a provider.
  ///
  /// A provider that has gone away is not an error worth reporting: its message
  /// simply did not land, and the connection's own end will settle whatever it
  /// was holding.
  private func send(_ fields: [String: Any], to connection: Connection) {
    guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
    data.append(UInt8(ascii: "\n"))
    data.withUnsafeBytes { buffer in
      var written = 0
      while written < buffer.count {
        let count = Darwin.write(connection.descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
        if count <= 0 {
          if count < 0 && errno == EINTR { continue }
          return
        }
        written += count
      }
    }
  }
}
