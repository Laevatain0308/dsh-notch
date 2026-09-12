import AppKit
import SwiftUI

/// Earlier recording-stage reference. The supported recorder is in tools/recording.
@MainActor
final class DemoStudio: ObservableObject {
  @Published var board = BoardModel()
  @Published var caption = "按「开始」再录"
  @Published var playing = false
  private var job: Task<Void, Never>?
  private var generation = 0

  init() { resetBoard() }

  func reset() {
    job?.cancel()
    job = nil
    playing = false
    generation += 1
    caption = "按「开始」再录"
    resetBoard()
    IdleDirector.previewInstance?.automaticActions = false
  }

  func start() {
    job?.cancel()
    generation += 1
    let token = generation
    resetBoard()
    playing = true
    job = Task { @MainActor in
      await runScript(token)
    }
  }

  private func resetBoard() {
    board = BoardModel()
    board.previewMode = true
    board.maximumExpandedHeight = 460
    board.expanded = false
  }

  private func snap(_ rows: [NotchRow]) {
    board.applySnapshot(NotchSnapshot(ok: true, generatedAt: Date().timeIntervalSince1970, origin: "demo", rows: rows))
  }

  private func busy(_ n: Int) -> [NotchRow] {
    (0..<n).map { i in
      NotchRow(id: "demo-\(i)", title: "任务 \(i + 1)", child: false, busy: true, unread: false, lastTurn: nil, approval: nil, ask: nil)
    }
  }

  private func mixed() -> [NotchRow] {
    [
      NotchRow(id: "demo-0", title: "任务 1", child: false, busy: false, unread: true, lastTurn: nil, approval: nil, ask: nil),
      NotchRow(
        id: "demo-1",
        title: "任务 2",
        child: false,
        busy: false,
        unread: true,
        lastTurn: NotchLastTurn(at: Date().timeIntervalSince1970, kind: "error", failed: true),
        approval: nil,
        ask: nil
      ),
      NotchRow(
        id: "demo-2",
        title: "任务 3",
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
      ),
      NotchRow(id: "demo-3", title: "任务 4", child: false, busy: true, unread: false, lastTurn: nil, approval: nil, ask: nil),
    ]
  }

  private func runScript(_ token: Int) async {
    func alive() -> Bool { token == generation && !Task.isCancelled }

    try? await Task.sleep(for: .milliseconds(400))
    guard alive() else { return }
    IdleDirector.previewInstance?.automaticActions = false
    let tour = IdleDirector.basics + ["dance"]
    for id in tour {
      guard alive() else { return }
      caption = "待机 · \(id)"
      IdleDirector.previewInstance?.play(id)
      let wait = IdleDirector.previewInstance?.currentDuration ?? 7
      try? await Task.sleep(for: .seconds(wait))
    }

    guard alive() else { return }
    caption = "4 个任务开始运行"
    snap(busy(4))
    try? await Task.sleep(for: .seconds(2.2))

    guard alive() else { return }
    caption = "请把鼠标移到黄点上，点一个选项"
    snap(mixed())

    while alive() && board.needsAction {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard alive() else { return }
    caption = "请点红点"

    while alive() && !board.failedRows.isEmpty {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard alive() else { return }
    caption = "蓝灯即将结束"
    try? await Task.sleep(for: .seconds(2.6))
    guard alive() else { return }
    snap(board.rows.filter { !$0.busy })
    caption = "请点绿点"

    while alive() && board.completedUnreadCount > 0 {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard alive() else { return }
    caption = "结束 · 可按「重来」"
    playing = false
  }
}

struct DemoStudioView: View {
  @ObservedObject var studio: DemoStudio
  @State private var hoverNotch = false

  private var previewWidth: CGFloat {
    studio.board.expanded ? 320 : (studio.board.isPillHovered ? 42 : 38)
  }
  private var previewHeight: CGFloat {
    if studio.board.expanded {
      return min(max(studio.board.measuredContentHeight, studio.board.needsAction ? 280 : 160), 420)
    }
    return max(44, studio.board.orbitLayout.height + 24)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 24) {
      VStack(alignment: .leading, spacing: 12) {
        Text("录屏模拟台").font(.system(size: 18, weight: .semibold))
        Text(studio.caption)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .frame(minHeight: 36, alignment: .topLeading)
        ZStack(alignment: .topTrailing) {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
          RootView(
            model: studio.board,
            panelSize: CGSize(width: 320, height: 460),
            restSize: CGSize(width: 38, height: 44)
          )
          .frame(width: previewWidth, height: previewHeight)
          .clipped()
          .onHover { hovering in
            hoverNotch = hovering
            if hovering && studio.board.needsAction {
              studio.board.expanded = true
            } else if !hovering {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                if !hoverNotch { studio.board.expanded = false }
              }
            }
          }
        }
        .frame(width: 360, height: 440, alignment: .topTrailing)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      VStack(alignment: .leading, spacing: 10) {
        Button(studio.playing ? "进行中…" : "开始") { studio.start() }
          .disabled(studio.playing)
          .keyboardShortcut(.defaultAction)
        Button("重来") { studio.reset() }
        Text("不接 Host，不影响正在跑的 notch。\n黄 / 红 / 绿需要你点。")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.top, 8)
        Spacer()
      }
      .frame(width: 180)
    }
    .padding(24)
    .frame(minWidth: 640, minHeight: 520)
  }
}

@MainActor
final class DemoStudioDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let studio = DemoStudio()
  var window: NSWindow?
  func applicationDidFinishLaunching(_ notification: Notification) {
    setbuf(stdout, nil)
    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
      styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )
    window.title = "dsh-notch 录屏模拟台"
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.isFloatingPanel = true
    window.hidesOnDeactivate = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.contentView = NSHostingView(rootView: DemoStudioView(studio: studio))
    let screen = NSScreen.screens.first { abs($0.frame.minX) < 1 && abs($0.frame.minY) < 1 } ?? NSScreen.main
    if let vis = screen?.visibleFrame {
      window.setFrame(NSRect(x: vis.midX - 360, y: vis.maxY - 620, width: 720, height: 560), display: true)
    }
    window.orderFrontRegardless()
    NSApplication.shared.activate(ignoringOtherApps: true)
    self.window = window
    print("DEMO_STUDIO ready")
  }
  func windowWillClose(_ notification: Notification) { NSApplication.shared.terminate(nil) }
}
