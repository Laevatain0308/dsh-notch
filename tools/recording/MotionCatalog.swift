import SwiftUI

/// The motion catalogue, as scenes the demo can play.
///
/// The catalogue's own browser lives inside the application, where the island is —
/// which makes it the wrong place to look at motions, because what is being watched
/// competes with the window it is watched in. The demo is a separate program with a
/// separate window, and it already renders a grid of motions correctly, so the
/// catalogue is read from here instead: the same entries, the same states, and the
/// same way of showing them.
enum MotionCatalog {
  /// One page per six entries, the way the recording cases are grouped.
  static let groups: [[DemoScene]] = {
    var scenes: [DemoScene] = []

    // The changes: what the catalogue serves a transition for.
    for entry in MotionLibrary.entries {
      let transition = MotionLibrary.watchableTransition(for: entry) ?? Transition(from: .nothing, to: .running)
      scenes.append(change(entry.motion.rawValue, entry.motion, transition, entry.plays))
    }

    // The recorded fallback, which is a motion in its own right and the one a
    // transition nobody has authored for plays.
    scenes.append(change(
      "takeShape",
      MotionLibrary.fallback,
      Transition(from: .ambient, to: .progress),
      "没有目录条目时播放的兜底：光环安放到它的新形状"
    ))

    // The states: shown by being held rather than by being played.
    for entry in MotionLibrary.states {
      let presence = entry.serves.from ?? .nothing
      scenes.append(DemoScene(
        id: entry.motion.rawValue,
        title: chinese(presence),
        english: english(presence),
        initialPresence: presence,
        beats: [],
        duration: 8
      ))
    }

    return stride(from: 0, to: scenes.count, by: 6).map { Array(scenes[$0..<min($0 + 6, scenes.count)]) }
  }()

  static var all: [DemoScene] { groups.flatMap { $0 } }

  /// A scene that moves the island from one state into another.
  private static func change(_ id: String, _ motion: Motion, _ transition: Transition, _ plays: String) -> DemoScene {
    DemoScene(
      id: id,
      title: "\(chinese(transition.from)) → \(chinese(transition.to))",
      english: "\(english(transition.from)) → \(english(transition.to))",
      initialPresence: transition.from,
      beats: [DemoBeat(at: 1.0, presence: transition.to)],
      duration: 6
    )
  }

  static func chinese(_ presence: Presence) -> String {
    switch presence {
    case .nothing: return "待机"
    case .ambient: return "环境状态"
    case .progress: return "进行中·有进度"
    case .running: return "运行"
    case .succeeded: return "完成"
    case .failed: return "失败"
    case .deciding: return "决策"
    }
  }

  static func english(_ presence: Presence) -> String {
    switch presence {
    case .nothing: return "Idle"
    case .ambient: return "Ambient"
    case .progress: return "Progress"
    case .running: return "Running"
    case .succeeded: return "Done"
    case .failed: return "Failed"
    case .deciding: return "Decision"
    }
  }
}
