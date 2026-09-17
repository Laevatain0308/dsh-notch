import Darwin
import Foundation

/// Who a running program is, as the operating system reports it.
///
/// This is the fact the consent surface shows and consent is pinned to, so it is
/// worth being able to ask about a process directly: `dsh-notch <pid>` prints
/// what Notch would say about it, which is how the difference between a program
/// and the application it belongs to can be seen rather than assumed.
@main enum IdentityProbe {
  static func main() {
    let arguments = CommandLine.arguments
    guard arguments.count > 1, let pid = pid_t(arguments[1]) else {
      print("usage: identity <pid>")
      exit(2)
    }

    guard let identity = ProviderIdentity.describe(pid) else {
      print("FAIL no identity for pid \(pid)")
      exit(1)
    }
    print("pid=\(identity.pid)")
    print("path=\(identity.path)")
    print("bundle=\(identity.bundle ?? "none")")
    print("displayName=\(identity.displayName)")
    print("identifier=\(identity.identifier ?? "none")")
    print("codeHash=\(identity.codeHash ?? "none")")
    print("identity=\(identity.id)")
  }
}
