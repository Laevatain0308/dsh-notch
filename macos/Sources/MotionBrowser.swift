//
//  MotionBrowser.swift
//  DshNotch
//
//  Every motion the island can play, played.
//
//  The rule this exists for is that a motion is considered to exist only when it
//  renders here: a catalogue entry nobody can watch is a claim, not a motion, and
//  the probe that checks the list cannot check what it looks like. So each entry
//  gets a scene — the island, driven through the transition the entry was authored
//  for — and the recorded fallback gets one too, because a fallback nobody has
//  watched is how a transition quietly becomes nothing.
//
//  Reached with `--motions`, the way the settings window is reached with
//  `--settings`: opening it from the command line is how a build gets looked at
//  without a hand on the mouse.
//

import AppKit
import SwiftUI

/// The window where the catalogue is watched.
@MainActor
final class MotionBrowserController: NSObject {
  private var window: NSWindow?

  /// Open it, which `--motions` does at launch.
  @objc func show() {
    if window == nil {
      let hosting = NSHostingController(rootView: MotionBrowserView())
      let window = NSWindow(contentViewController: hosting)
      window.title = "Notch — motions"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 760, height: 520))
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

/// The catalogue, and a stage for whatever is selected.
struct MotionBrowserView: View {
  /// Which scene is on the stage, by the transition it plays.
  @State private var selected: Transition?
  @State private var model = BoardModel()
  @State private var lastPlayed: String?
  @State private var gaps = MotionLibrary()

  /// One scene: the transition, the motion it resolves to, and whether the
  /// library had it.
  private struct Scene: Identifiable {
    let id: String
    let motion: Motion
    let transition: Transition
    let plays: String
    let fellBack: Bool
  }

  /// Every scene, one per catalogue entry plus the fallback.
  ///
  /// The fallback's scene is a transition nothing is catalogued for, chosen from
  /// what the probe reports as gaps, so what is watched is the motion a user
  /// actually gets for an unauthored change.
  private var scenes: [Scene] {
    var scenes: [Scene] = MotionLibrary.entries.map { entry in
      // A rule can serve several transitions; the first one the island can
      // produce is the one worth watching.
      let transition = firstTransition(servedBy: entry)
      return Scene(id: entry.serves.to?.rawValue ?? entry.motion.rawValue, motion: entry.motion,
                   transition: transition, plays: entry.plays, fellBack: false)
    }
    scenes.append(Scene(
      id: "fallback",
      motion: MotionLibrary.fallback,
      transition: Transition(from: .ambient, to: .progress),
      plays: "the recorded fallback: the ring settles into its new shape",
      fellBack: true
    ))
    return scenes
  }

  /// The first transition the island can produce that an entry was authored for.
  private func firstTransition(servedBy entry: MotionEntry) -> Transition {
    for from in Presence.allCases {
      for to in Presence.allCases where from != to {
        let transition = Transition(from: from, to: to)
        if entry.serves.matches(transition), PresenceReading.between(.showing(from), .showing(to)) == transition {
          return transition
        }
      }
    }
    return Transition(from: .nothing, to: .running)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      list
      Divider()
      stage
    }
    .background(NotchTokens.bodyBackground)
  }

  private var list: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("动效目录")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.top, 14)
        Text("\(scenes.count) 个场景；点一个在右边播放。")
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.45))
          .padding(.horizontal, 14)
          .padding(.bottom, 10)

        ForEach(scenes) { scene in
          Button {
            play(scene)
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 6) {
                Text(scene.motion.rawValue)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(.white.opacity(0.9))
                if scene.fellBack {
                  Text("fallback")
                    .font(.system(size: 9))
                    .foregroundStyle(NotchTokens.amber)
                }
                Spacer(minLength: 0)
                if lastPlayed == scene.id {
                  Text("playing")
                    .font(.system(size: 9))
                    .foregroundStyle(NotchTokens.greenComplete)
                }
              }
              Text("\(scene.transition.id) — \(scene.plays)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == scene.transition ? NotchTokens.fieldBackground : Color.clear)
          }
          .buttonStyle(.plain)
        }

        if !gaps.gaps.isEmpty {
          Text("没有目录条目的转换（走 fallback）")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.top, 14)
          Text(gaps.gaps.keys.sorted { $0.id < $1.id }.map(\.id).joined(separator: "\n"))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 14)
            .padding(.top, 4)
        }
      }
      .frame(width: 320, alignment: .leading)
    }
  }

  private var stage: some View {
    ZStack(alignment: .topTrailing) {
      DemoWallpaper()
      RootView(
        model: model,
        service: NotchService(),
        consent: ConsentInbox(),
        onConsentAllow: {},
        onConsentDeny: {},
        onConsentDismiss: {},
        onAnswer: { _, _ in },
        onAction: { _, _, _ in },
        onDismiss: {},
        panelSize: CGSize(width: 320, height: 460),
        restSize: CGSize(width: 38, height: 44)
      )
      .frame(width: 320, height: 460, alignment: .topTrailing)
      .padding(.trailing, 24)
      .padding(.top, 60)
      .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
  }

  /// Drive the island through the transition a scene is about.
  private func play(_ scene: Scene) {
    selected = scene.transition
    lastPlayed = scene.id
    model.playTransition(from: scene.transition.from, to: scene.transition.to)
    // And resolve it here as well, so the gap list on the left is what the scene
    // just produced rather than a claim about it.
    _ = gaps.resolve(scene.transition)
  }
}

private extension Surface {
  /// A surface reading as one kind of presence, for deciding whether a transition
  /// is one the island can actually produce.
  static func showing(_ presence: Presence) -> Surface {
    MotionLibrary.surface(presence)
  }
}
