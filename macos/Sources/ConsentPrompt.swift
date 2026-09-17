//
//  ConsentPrompt.swift
//  DshNotch
//
//  A program asking to be allowed, as the island draws it.
//
//  Deliberately not the observation record it came from: a view has no business
//  holding a peer's process id, and the prompt carries only what is drawn. It
//  also carries no provider-supplied text — the program is named by the
//  executable the operating system reported, and the classes are described in
//  Notch's own words, because a program's account of itself is a claim and this
//  decision is about what was observed.
//

import Foundation

/// A request for the user's decision, in the form the island presents it.
struct ConsentPrompt: Equatable, Sendable {
  /// The program, as the operating system named it.
  let program: String
  /// Where the executable is, so the user can tell two programs of one name apart.
  let path: String
  /// The signing identifier, when the program has one.
  let identifier: String?
  /// The classes being asked for that the program does not already hold.
  let classes: [CapabilityClass]

  /// One class, in Notch's own words.
  ///
  /// The wording is Notch's and not the provider's, and it is deliberately plain:
  /// it says what would appear, not what the program says it does.
  static func wording(for behaviourClass: CapabilityClass) -> String {
    switch behaviourClass {
    case .ambient: return "显示环境状态"
    case .progress: return "显示进度"
    case .activity: return "显示正在运行"
    case .result: return "显示完成结果"
    case .awaiting: return "向你提问，并等你的回答"
    }
  }

  /// Whether this request would allow the program to put questions in front of
  /// the user, which is the part worth calling out rather than listing.
  var asksToAsk: Bool { classes.contains(.awaiting) }
}
