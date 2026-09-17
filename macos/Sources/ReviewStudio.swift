import AppKit
import SwiftUI

/// Legacy local walkthrough. Launch with `--demo`; the bilingual recorder is in tools/recording.
@MainActor
final class DemoStudio: ObservableObject {
  let board = BoardModel()
  @Published var caption = "按「开始」再录"
  @Published var playing = false
  @Published var hoverNotch = false
  private var job: Task<Void, Never>?
  private var generation = 0

  init() {
    board.previewMode = true
    board.maximumExpandedHeight = 460
  }

  func reset() {
    job?.cancel()
    job = nil
    playing = false
    generation += 1
    caption = "按「开始」再录"
    clearBoard()
    IdleDirector.previewInstance?.automaticActions = false
  }

  func start() {
    job?.cancel()
    generation += 1
    let token = generation
    clearBoard()
    playing = true
    caption = "开始"
    job = Task { @MainActor in
      await runScript(token)
    }
  }

  private func clearBoard() {
    board.expanded = false
    board.showingExpanded = false
    board.wizard = nil
    board.previewMode = true
    board.maximumExpandedHeight = 460
    board.applySnapshot(NotchSnapshot(ok: true, generatedAt: Date().timeIntervalSince1970, origin: "demo", rows: []))
  }

  private func snap(_ rows: [NotchRow]) {
    board.applySnapshot(NotchSnapshot(ok: true, generatedAt: Date().timeIntervalSince1970, origin: "demo", rows: rows))
  }

  private func busyRow(_ i: Int) -> NotchRow {
    NotchRow(id: "demo-\(i)", title: "任务 \(i + 1)", child: false, busy: true, unread: false, lastTurn: nil, approval: nil, ask: nil)
  }

  private func greenRow(_ i: Int) -> NotchRow {
    NotchRow(id: "demo-\(i)", title: "任务 \(i + 1)", child: false, busy: false, unread: true, lastTurn: nil, approval: nil, ask: nil)
  }

  private func redRow(_ i: Int) -> NotchRow {
    NotchRow(
      id: "demo-\(i)",
      title: "任务 \(i + 1)",
      child: false,
      busy: false,
      unread: true,
      lastTurn: NotchLastTurn(at: Date().timeIntervalSince1970, kind: "error", failed: true),
      approval: nil,
      ask: nil
    )
  }

  private func askRow(_ i: Int) -> NotchRow {
    NotchRow(
      id: "demo-\(i)",
      title: "任务 \(i + 1)",
      child: false,
      busy: false,
      unread: false,
      lastTurn: nil,
      approval: nil,
      ask: NotchAsk(id: "demo-ask", questions: [
        NotchQuestion(
          id: "q1",
          question: "这条任务下一步怎么走？",
          detail: "录屏用的假问题，点任意一项即可。",
          header: nil,
          options: [
            NotchOption(label: "先改动画", description: "收起和展开再顺一点"),
            NotchOption(label: "先改文案", description: "字幕再短一点"),
            NotchOption(label: "都行", description: "你选就好"),
          ],
          multiSelect: false
        )
      ])
    )
  }

  private func runScript(_ token: Int) async {
    func alive() -> Bool { token == generation && !Task.isCancelled }

    try? await Task.sleep(for: .milliseconds(500))
    guard alive() else { return }
    IdleDirector.previewInstance?.automaticActions = false
    let tour = IdleDirector.basics + ["dance"]
    for id in tour {
      guard alive() else { return }
      caption = "待机 · \(id)"
      IdleDirector.previewInstance?.play(id)
      let wait = max(1.2, IdleDirector.previewInstance?.currentDuration ?? 7)
      try? await Task.sleep(for: .seconds(wait))
    }

    guard alive() else { return }
    caption = "工作中 · 4"
    board.expanded = false
    snap((0..<4).map(busyRow))
    try? await Task.sleep(for: .seconds(3.4))

    guard alive() else { return }
    caption = "工作中 → 待决策"
    snap([askRow(2), busyRow(0), busyRow(1), busyRow(3)])
    board.expanded = false
    try? await Task.sleep(for: .seconds(1.8))

    guard alive() else { return }
    caption = "工作中 → 成功"
    snap([greenRow(0), askRow(2), busyRow(1), busyRow(3)])
    try? await Task.sleep(for: .seconds(1.6))

    guard alive() else { return }
    caption = "工作中 → 失败"
    snap([greenRow(0), redRow(1), askRow(2), busyRow(3)])
    try? await Task.sleep(for: .seconds(1.6))
    guard alive() else { return }
    caption = "请把鼠标移到黄点上，再选一项"

    while alive() && board.needsAction {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard alive() else { return }
    board.expanded = false
    caption = "决策完成 · 回到工作中"
    try? await Task.sleep(for: .seconds(2.2))

    guard alive() else { return }
    caption = "工作中 → 成功"
    let rest = board.rows.map { row -> NotchRow in
      if row.busy { return greenRow(Int(row.id.split(separator: "-").last ?? "0") ?? 0) }
      return row
    }
    snap(rest)
    try? await Task.sleep(for: .seconds(1.5))
    guard alive() else { return }
    caption = "请点红点"

    while alive() && !board.failedRows.isEmpty {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard alive() else { return }
    caption = "请点绿点"

    while alive() && board.completedUnreadCount > 0 {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard alive() else { return }
    caption = "结束 · 可按「重来」"
    playing = false
  }
}

struct DemoWallpaper: View {
  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      ZStack(alignment: .bottom) {
        LinearGradient(
          colors: [
            Color(red: 0.45, green: 0.72, blue: 0.95),
            Color(red: 0.62, green: 0.82, blue: 0.96),
            Color(red: 0.93, green: 0.86, blue: 0.70),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        Circle()
          .fill(Color(red: 1, green: 0.86, blue: 0.45).opacity(0.95))
          .frame(width: 88, height: 88)
          .blur(radius: 0.5)
          .offset(x: w * 0.22 - w / 2, y: -(h * 0.58))
        mountain(width: w, height: h * 0.42, peak: 0.22, fill: Color(red: 0.35, green: 0.48, blue: 0.58).opacity(0.85))
        mountain(width: w, height: h * 0.36, peak: 0.62, fill: Color(red: 0.28, green: 0.42, blue: 0.46).opacity(0.9))
        Ellipse()
          .fill(
            LinearGradient(
              colors: [Color(red: 0.35, green: 0.62, blue: 0.72).opacity(0.55), Color(red: 0.18, green: 0.38, blue: 0.48).opacity(0.7)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: w * 1.2, height: h * 0.28)
          .offset(y: h * 0.08)
        HStack(alignment: .bottom, spacing: 18) {
          ForEach(0..<7, id: \.self) { i in
            Capsule()
              .fill(Color(red: 0.12, green: 0.32, blue: 0.22).opacity(0.85))
              .frame(width: 10 + CGFloat(i % 3) * 3, height: 48 + CGFloat((i * 17) % 40))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28)
        .padding(.bottom, 18)
      }
      .clipped()
    }
  }

  private func mountain(width: CGFloat, height: CGFloat, peak: CGFloat, fill: Color) -> some View {
    Path { path in
      path.move(to: CGPoint(x: 0, y: height))
      path.addLine(to: CGPoint(x: width * (peak - 0.18), y: height * 0.55))
      path.addLine(to: CGPoint(x: width * peak, y: 8))
      path.addLine(to: CGPoint(x: width * (peak + 0.16), y: height * 0.48))
      path.addLine(to: CGPoint(x: width, y: height))
      path.closeSubpath()
    }
    .fill(fill)
    .frame(width: width, height: height, alignment: .bottom)
  }
}

struct DemoStudioView: View {
  @ObservedObject var studio: DemoStudio
  @ObservedObject var board: BoardModel

  private var previewWidth: CGFloat {
    board.expanded ? 320 : (board.isPillHovered ? 42 : 38)
  }
  private var previewHeight: CGFloat {
    if board.expanded {
      return min(max(board.measuredContentHeight, 120), 420)
    }
    return max(44, board.orbitLayout.height + 24)
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      DemoWallpaper()
      RootView(
        model: board,
        service: NotchService(),
        consent: ConsentInbox(),
        onConsentAllow: {},
        onConsentDeny: {},
        onConsentDismiss: {},
        onAnswer: { _, _ in },
        panelSize: CGSize(width: 320, height: 460),
        restSize: CGSize(width: 38, height: 44)
      )
      .frame(width: previewWidth, height: previewHeight, alignment: .topTrailing)
      .animation(.spring(response: 0.32, dampingFraction: 0.78), value: previewWidth)
      .animation(.spring(response: 0.32, dampingFraction: 0.78), value: previewHeight)
      .padding(.top, 96)
      .onHover { hovering in
        studio.hoverNotch = hovering
        if hovering && board.needsAction {
          board.expanded = true
        } else if !hovering {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            if !studio.hoverNotch { board.expanded = false }
          }
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        Text(studio.caption)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        HStack(spacing: 8) {
          Button("开始") { studio.start() }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.20, green: 0.48, blue: 0.36))
            .disabled(studio.playing)
          Button("重来") { studio.reset() }
            .buttonStyle(.bordered)
          .tint(.white)
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
  }
}

final class DemoKeyWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@MainActor
final class DemoStudioDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  static var hold: DemoStudioDelegate?
  let studio = DemoStudio()
  var window: NSWindow?
  func applicationDidFinishLaunching(_ notification: Notification) {
    show()
  }
  func show() {
    guard window == nil else {
      window?.makeKeyAndOrderFront(nil)
      return
    }
    setbuf(stdout, nil)
    let screen = NSScreen.screens.first { abs($0.frame.minX) < 1 && abs($0.frame.minY) < 1 }
      ?? NSScreen.main
      ?? NSScreen.screens.first
    let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let width = min(1280, vis.width - 48)
    let height = min(800, vis.height - 48)
    let frame = NSRect(x: vis.minX + 24, y: vis.maxY - 24 - height, width: width, height: height)
    let window = DemoKeyWindow(
      contentRect: frame,
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "dsh-notch 录屏模拟台"
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.backgroundColor = NSColor(red: 0.45, green: 0.72, blue: 0.95, alpha: 1)
    window.contentView = NSHostingView(rootView: DemoStudioView(studio: studio, board: studio.board))
    window.setFrame(frame, display: true)
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    self.window = window
    FileHandle.standardOutput.write(Data("DEMO_STUDIO ready \(NSStringFromRect(window.frame)) count=1\n".utf8))
  }
  func windowWillClose(_ notification: Notification) { NSApplication.shared.terminate(nil) }
}
