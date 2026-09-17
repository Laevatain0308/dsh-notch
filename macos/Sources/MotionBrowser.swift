//
//  MotionBrowser.swift
//  DshNotch
//
//  Every motion the island can play, playing.
//
//  The rule this exists for is that a motion is considered to exist only when it
//  renders here: a catalogue entry nobody can watch is a claim, not a motion, and
//  the probe that checks the list cannot check what any of it looks like.
//
//  It is laid out the way the review studio is, because that is what a library of
//  motions is: a card per entry, each one an island actually doing the thing, so
//  the catalogue can be read by looking rather than by clicking. Every card runs
//  its own island and keeps doing its own motion, so a state is seen by watching it
//  hold and a change is seen by watching it happen — over and over, which is what
//  makes it comparable with the card beside it.
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
      window.title = "Notch — 动效库"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 880, height: 640))
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

/// One thing the island does, and how to show it.
struct MotionScene: Identifiable {
  let id: String
  let motion: Motion
  let kind: MotionKind
  /// The state it is, or the state it begins from.
  let from: Presence
  /// The state it ends in, which is the same as `from` for a state.
  let to: Presence
  /// The motion's own name, which is what a developer greps for.
  let name: String
  let plays: String
  let fellBack: Bool

  var isState: Bool { kind == .state }

  /// The heading, in the shape the review studio uses: what it is about.
  var title: String {
    guard !isState else { return MotionScene.stateTitle(from) }
    return "\(MotionScene.stateTitle(from)) → \(MotionScene.stateTitle(to))"
  }

  /// What a presence is called, in the island's own words.
  static func stateTitle(_ presence: Presence) -> String {
    switch presence {
    case .nothing: return "空闲"
    case .ambient: return "环境状态"
    case .progress: return "进行中·有进度"
    case .running: return "进行中"
    case .succeeded: return "已完成"
    case .failed: return "失败"
    case .deciding: return "等待决策"
    }
  }

  /// Every scene: the states first, then the changes.
  static func all() -> [MotionScene] {
    let states = MotionLibrary.states.map { entry -> MotionScene in
      let presence = entry.serves.from ?? .nothing
      return MotionScene(id: entry.motion.rawValue, motion: entry.motion, kind: .state,
                         from: presence, to: presence, name: entry.motion.rawValue,
                         plays: entry.plays, fellBack: false)
    }
    var changes: [MotionScene] = MotionLibrary.entries.map { entry in
      let transition = MotionLibrary.watchableTransition(for: entry) ?? Transition(from: .nothing, to: .running)
      return MotionScene(id: entry.motion.rawValue, motion: entry.motion, kind: .transition,
                         from: transition.from, to: transition.to, name: entry.motion.rawValue,
                         plays: entry.plays, fellBack: false)
    }
    changes.append(MotionScene(
      id: "takeShape-fallback", motion: MotionLibrary.fallback, kind: .transition,
      from: .ambient, to: .progress, name: "takeShape · fallback",
      plays: "没有目录条目时播放的兜底：光环安放到它的新形状", fellBack: true
    ))
    return states + changes
  }
}

/// The catalogue, as cards.
struct MotionBrowserView: View {
  private let scenes = MotionScene.all()
  private let columns = [GridItem(.adaptive(minimum: 264), spacing: 16)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
          ForEach(scenes) { scene in
            MotionCard(scene: scene)
          }
        }
        footer
      }
      .padding(22)
    }
    .background(Color(red: 0.93, green: 0.93, blue: 0.94))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("动效库")
        .font(.system(size: 20, weight: .semibold))
      Text("每一格都是岛屿本人。前四格是持续状态，会一直保持，可以慢慢看；后面是状态切换，反复播放，方便和旁边那格比较。")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      Text("关于兜底")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      Text("岛屿能显示的 42 种转换里，有 14 种没有目录条目——全部是「一种信息态变成另一种信息态」（环境状态↔进行中、进度↔进行中之类）。它们播放的是兜底：光环安放到新形状。最后一格就是它。要补哪一个，见 docs/adding-a-motion.md。")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// One motion, playing on its own island.
///
/// Its own island and its own model: two cards side by side are two independent
/// states being compared, and sharing one model would make each card's motion
/// depend on the last one watched — which is the confusion a library exists to
/// remove.
struct MotionCard: View {
  let scene: MotionScene

  @State private var model = BoardModel()
  @State private var loop: Timer?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(scene.title)
          .font(.system(size: 13, weight: .medium))
        Text(scene.name)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      stage
      Text(scene.plays)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(scene.fellBack ? NotchTokens.amber.opacity(0.8) : Color.black.opacity(0.06), lineWidth: 1)
    )
    .onAppear { begin() }
    .onDisappear {
      loop?.invalidate()
      loop = nil
    }
  }

  private var stage: some View {
    ZStack(alignment: .topTrailing) {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(red: 0.16, green: 0.17, blue: 0.19))
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
        panelSize: CGSize(width: 220, height: 180),
        restSize: CGSize(width: 38, height: 44)
      )
      .frame(width: 132, height: 96, alignment: .topTrailing)
      .padding(.top, 14)
      .padding(.trailing, 14)
      .allowsHitTesting(false)
    }
    .frame(height: 124)
  }

  /// Put the island into the state, and keep the motion going.
  ///
  /// A state is held, so it is set once and left. A change is played, so it is
  /// played again and again: a motion watched once is a motion nobody can compare
  /// with the one beside it, and comparing them is the reason for a grid.
  private func begin() {
    model.snapOrbit(to: scene.from)
    guard !scene.isState else { return }
    play()
    let timer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { _ in
      Task { @MainActor in play() }
    }
    RunLoop.main.add(timer, forMode: .common)
    loop = timer
  }

  private func play() {
    // Back to where it begins, at once: what is being watched is the change, not
    // the way the card got back to the start.
    model.snapOrbit(to: scene.from)
    model.surfaceCounts = { Summary.showing(scene.to) }
    model.playTransition(from: scene.from, to: scene.to)
  }
}
