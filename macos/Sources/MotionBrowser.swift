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
//  It is laid out exactly the way the recording demo is — the same tiles, the same
//  grid, the same capsule of controls, the same window — because that demo is what
//  a catalogue of motions should look like: one island per entry, big enough to
//  watch, six to a page, playing in a loop so any two of them can be compared. The
//  only difference is where the scenes come from: this reads the motion catalogue,
//  and the demo reads a list written by hand for recording.
//
//  Reached with `--motions`, the way the settings window is reached with
//  `--settings`: opening it from the command line is how a build gets looked at
//  without a hand on the mouse, and the demo is reached the same way.
//

import AppKit
import SwiftUI

/// One thing the island does, and the two states that describe it.
struct MotionScene: Identifiable {
  let id: String
  let motion: Motion
  let kind: MotionKind
  /// The state it is, or the state it begins from.
  let from: Presence
  /// The state it ends in, the same as `from` for a state.
  let to: Presence
  let plays: String
  let fellBack: Bool

  var isState: Bool { kind == .state }

  /// What the tile says, in the demo's shape: the states it is between.
  var title: String {
    guard !isState else { return MotionScene.chinese(from) }
    return "\(MotionScene.chinese(from)) → \(MotionScene.chinese(to))"
  }

  var englishTitle: String {
    guard !isState else { return MotionScene.english(from) }
    return "\(MotionScene.english(from)) → \(MotionScene.english(to))"
  }

  /// The motion's own name, which is what a developer greps for.
  var name: String { motion.rawValue }

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

  /// The catalogue as pages of six, the way the demo groups its scenes.
  ///
  /// Changes first, then the states, then the fallback on its own page: a page is
  /// what fits on screen at once, and the two kinds are worth watching together
  /// rather than mixed.
  static let groups: [[MotionScene]] = {
    let changes: [MotionScene] = MotionLibrary.entries.map { entry in
      let transition = MotionLibrary.watchableTransition(for: entry) ?? Transition(from: .nothing, to: .running)
      return MotionScene(id: entry.motion.rawValue, motion: entry.motion, kind: .transition,
                         from: transition.from, to: transition.to, plays: entry.plays, fellBack: false)
    }
    let fallback = MotionScene(
      id: "takeShape", motion: MotionLibrary.fallback, kind: .transition,
      from: .ambient, to: .progress,
      plays: "没有目录条目时播放的兜底：光环安放到它的新形状", fellBack: true
    )
    let states: [MotionScene] = MotionLibrary.states.map { entry in
      let presence = entry.serves.from ?? .nothing
      return MotionScene(id: entry.motion.rawValue, motion: entry.motion, kind: .state,
                         from: presence, to: presence, plays: entry.plays, fellBack: false)
    }
    let all = changes + [fallback] + states
    return stride(from: 0, to: all.count, by: 6).map { Array(all[$0..<min($0 + 6, all.count)]) }
  }()

  static var all: [MotionScene] { groups.flatMap { $0 } }
}

/// One card's island, and how it is driven.
@MainActor final class MotionTile: ObservableObject, Identifiable {
  let id = UUID()
  let scene: MotionScene
  let board = BoardModel()

  init(_ scene: MotionScene) {
    self.scene = scene
    board.previewMode = true
    board.applySurface(MotionLibrary.surface(scene.from))
  }

  /// Put the island into the state the scene begins from.
  func reset() {
    board.applySurface(MotionLibrary.surface(scene.from))
  }

  /// Move it to the state the scene ends in, which is the motion.
  ///
  /// A state scene is not moved: it is put into that state and left there, which
  /// is what that state looks like.
  func play() {
    guard !scene.isState else { return }
    board.applySurface(MotionLibrary.surface(scene.to))
  }
}

/// The catalogue, paged, playing.
@MainActor final class MotionBrowserModel: ObservableObject {
  @Published var tiles: [MotionTile] = []
  @Published var group = 0
  @Published var selected = 0
  @Published var solo = false
  @Published var autoplay = true
  @Published var controls = false
  private var job: Task<Void, Never>?
  private var epoch = 0

  var count: Int { solo ? MotionScene.all.count : MotionScene.groups.count }
  var page: Int { solo ? selected : group }
  var scenes: [MotionScene] { solo ? [MotionScene.all[selected]] : MotionScene.groups[group] }

  func move(_ direction: Int) {
    if solo { selected = (selected + direction + count) % count } else { group = (group + direction + count) % count }
    replay()
  }

  func toggleLayout() {
    if !solo { selected = group * 6 }
    else { group = selected / 6 }
    solo.toggle()
    replay()
  }

  /// Show the page, play it, and go on to the next one.
  ///
  /// One loop for the whole page rather than a timer per tile: the cards are being
  /// compared, and a page whose motions started at different moments is a page
  /// that cannot be read.
  func replay() {
    job?.cancel()
    epoch += 1
    let token = epoch
    job = Task { @MainActor in
      while !Task.isCancelled, token == epoch {
        let batch = self.scenes.map(MotionTile.init)
        self.tiles = batch
        for tile in batch { tile.reset() }
        try? await Task.sleep(for: .seconds(0.5))
        guard token == self.epoch else { return }
        for tile in batch { tile.play() }
        try? await Task.sleep(for: .seconds(3.2))
        guard token == self.epoch else { return }
        if self.autoplay {
          if self.solo { self.selected = (self.selected + 1) % self.count }
          else { self.group = (self.group + 1) % self.count }
        }
      }
    }
  }

  func stop() {
    job?.cancel()
    job = nil
    epoch += 1
  }
}

/// One tile: what it is, and the island doing it.
///
/// The same measurements as the recording demo's tile, because they were arrived
/// at by watching these motions and they are right: an island two and a half times
/// its size is the size at which a lamp can be seen changing.
struct MotionTileView: View {
  let tile: MotionTile
  let solo: Bool
  @ObservedObject var board: BoardModel

  init(tile: MotionTile, solo: Bool) {
    self.tile = tile
    self.solo = solo
    board = tile.board
  }

  var body: some View {
    GeometryReader { geo in
      let scale: CGFloat = solo ? min(5.4, (geo.size.height - 140) / 110) : min(2.65, (geo.size.height - 104) / 104)
      VStack(spacing: 0) {
        VStack(spacing: 5) {
          Text(tile.scene.title)
            .font(.system(size: solo ? 40 : 24, weight: .semibold))
            .foregroundStyle(tile.scene.fellBack ? NotchTokens.amber : Color(white: 0.14))
          Text(tile.scene.englishTitle)
            .font(.system(size: solo ? 27 : 17, weight: .medium))
            .foregroundStyle(Color(white: 0.34))
          Text(tile.scene.name)
            .font(.system(size: solo ? 17 : 12, design: .monospaced))
            .foregroundStyle(Color(white: 0.52))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(height: solo ? 130 : 96)

        ZStack {
          RootView(
            model: board,
            service: NotchService(),
            consent: ConsentInbox(),
            onConsentAllow: {},
            onConsentDeny: {},
            onConsentDismiss: {},
            onAnswer: { _, _ in },
            onAction: { _, _, _ in },
            onDismiss: {},
            panelSize: CGSize(width: 340, height: 260),
            restSize: CGSize(width: 38, height: 44)
          )
          .frame(width: 38, height: max(44, board.orbitLayout.height + 24))
          .scaleEffect(scale)
          .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }
}

/// The window: the tiles, and the controls.
struct MotionBrowserView: View {
  @ObservedObject var model: MotionBrowserModel

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .bottom) {
        Color(white: 0.965)
        if model.solo {
          if let tile = model.tiles.first {
            MotionTileView(tile: tile, solo: true)
              .id(tile.id)
              .padding(.horizontal, 60)
              .padding(.top, 22)
              .padding(.bottom, 80)
          }
        } else {
          VStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { row in
              HStack(spacing: 26) {
                ForEach(Array(model.tiles.dropFirst(row * 3).prefix(3))) { tile in
                  MotionTileView(tile: tile, solo: false).id(tile.id)
                }
              }
            }
          }
          .padding(.horizontal, 38)
          .padding(.top, 16)
          .padding(.bottom, 68)
        }

        HStack(spacing: 18) {
          Button { model.move(-1) } label: { Image(systemName: "chevron.left") }
            .keyboardShortcut(.leftArrow, modifiers: []).help("上一组")
          Text("\(model.page + 1) / \(model.count)").monospacedDigit().foregroundStyle(.secondary)
          Button { model.move(1) } label: { Image(systemName: "chevron.right") }
            .keyboardShortcut(.rightArrow, modifiers: []).help("下一组")
          Divider().frame(height: 18)
          Button { model.replay() } label: { Image(systemName: "arrow.counterclockwise") }
            .keyboardShortcut("r", modifiers: []).help("重播")
          Toggle("全部连播", isOn: $model.autoplay).toggleStyle(.checkbox)
          Button { model.controls.toggle() } label: { Image(systemName: "eye.slash") }
            .keyboardShortcut("h", modifiers: []).help("显示 / 隐藏控制栏")
          Button { model.toggleLayout() } label: { Image(systemName: model.solo ? "square.grid.3x2" : "rectangle") }
            .keyboardShortcut("s", modifiers: []).help("并排 / 单场景")
          Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            .keyboardShortcut("f", modifiers: [.command, .control]).help("全屏")
        }
        .font(.system(size: 14))
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 15)
        .opacity(model.controls ? 1 : 0)
        .allowsHitTesting(model.controls)
        .animation(.easeOut(duration: 0.15), value: model.controls)
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let point): model.controls = point.y > geo.size.height - 70
        case .ended: model.controls = false
        }
      }
    }
    .frame(minWidth: 900, minHeight: 620)
  }
}

/// The window the catalogue is watched in, with the demo's chrome.
@MainActor final class MotionBrowserController: NSObject, NSWindowDelegate {
  private let model = MotionBrowserModel()
  private var window: NSWindow?

  /// Open it, which `--motions` does at launch.
  @objc func show() {
    if window == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.title = "Notch · 动效库"
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.contentView = NSHostingView(rootView: MotionBrowserView(model: model))
      window.backgroundColor = NSColor(white: 0.965, alpha: 1)
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.collectionBehavior = [.fullScreenPrimary]
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    model.replay()
  }

  func windowWillClose(_ notification: Notification) {
    model.stop()
  }
}
