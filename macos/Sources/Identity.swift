//
//  Identity.swift
//  DshNotch
//
//  Who a connection is, as the operating system reports it.
//
//  This is its own file because three things need it and none of them owns it:
//  the transport reads it, the consent record is pinned to it, and the island
//  shows it to the user when a program asks to be allowed. It is never taken
//  from the provider, which is the whole of its value.
//

import Darwin
import Foundation
import Security

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

