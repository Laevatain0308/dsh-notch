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
  /// The application it is part of, when it is part of one.
  ///
  /// A program inside a bundle is shown as the application rather than as the
  /// binary within it: "Notch" is what the user recognises, and the signature
  /// covers the bundle, so that is what the identity is pinned to.
  let bundle: String?
  /// The signing identifier, when the binary has one.
  let identifier: String?
  /// The hash of the code the peer is running, which changes when it does.
  let codeHash: String?

  /// The stable identity consent is pinned to.
  var id: String {
    "\(bundle ?? path)#\(codeHash ?? "unsigned")"
  }

  /// What the user is shown for this provider.
  var displayName: String {
    guard let bundle else { return (path as NSString).lastPathComponent }
    return ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
  }

  /// The application a path belongs to, if it is inside one.
  ///
  /// Read from the path rather than from the bundle API, because the question is
  /// about a *different* process: which application it was launched from is a
  /// fact about where its executable sits, and the other process's bundles are
  /// not this one's to ask about.
  /// - Parameter executable: the path the operating system reported.
  /// - Returns: the `.app` directory containing it, or nothing.
  static func application(containing executable: String) -> String? {
    guard let range = executable.range(of: ".app/Contents/MacOS/") else { return nil }
    return String(executable[executable.startIndex..<range.lowerBound]) + ".app"
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
    return describe(pid)
  }

  /// Who a running process is, as far as the operating system will say.
  /// - Parameter pid: the process to describe.
  /// - Returns: the identity, or nothing when even its path cannot be read.
  static func describe(_ pid: pid_t) -> ProviderIdentity? {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(MAXPATHLEN)) > 0 else { return nil }
    let executable = String(cString: path)
    // The signature covers the application, so that is what is asked about and
    // what the identity is pinned to.
    let bundle = application(containing: executable)

    var identifier: String?
    var codeHash: String?
    var code: SecStaticCode?
    let signed = bundle ?? executable
    if SecStaticCodeCreateWithPath(URL(fileURLWithPath: signed) as CFURL, [], &code) == errSecSuccess, let code {
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
    return ProviderIdentity(pid: pid, path: executable, bundle: bundle, identifier: identifier, codeHash: codeHash)
  }
}

