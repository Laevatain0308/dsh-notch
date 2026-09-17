import AppKit
import Combine
import SwiftUI

/// Guided local walkthrough mode: the island stands off the screen edge and
/// stays expanded while a question waits, so a reviewer can watch an answer
/// being sent. Distinct from `DSH_NOTCH_RUNTIME_FILE`, which only says where
/// to read the connection details — a Host that pins that path is ordinary.
var walkthroughMode: Bool {
  ProcessInfo.processInfo.environment["DSH_NOTCH_WALKTHROUGH"] != nil
}

@main
enum DshNotchMain {
  static func main() {
    if CommandLine.arguments.contains("--verify-idle-resources") {
      let ids = IdleDirector.basics + ["dance"]
      let missing = ids.filter { IdleLibrary.shared.clip($0) == nil }
      print("IDLE_RESOURCES=\(ids.count - missing.count)/\(ids.count)")
      exit(missing.isEmpty ? 0 : 1)
    }
    let app = NSApplication.shared
    if CommandLine.arguments.contains("--demo") {
      app.setActivationPolicy(.regular)
      let delegate = DemoStudioDelegate()
      DemoStudioDelegate.hold = delegate
      app.delegate = delegate
      delegate.show()
      app.run()
      return
    }
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let panelW: CGFloat = 480
  private let restW: CGFloat = 32
  private let restH: CGFloat = 110
  private let topOffset: CGFloat = 100
  private let model = BoardModel()
  /// The endpoint the island owns, which is where other programs attach.
  private let service = NotchService()
  /// The window the user reviews and revokes from, and the item that opens it.
  private lazy var settings = SettingsWindowController(service: service)
  /// Where every change the island can show is resolved to a motion.
  private let motions = MotionLibrary()
  /// The window where the catalogue is watched.
  private let browser = MotionBrowserController()
  /// The surface as it was, which is what a transition is measured against.
  private var lastSurface: Surface?
  private var panel: NotchPanel?
  private var hosting: NotchHostingView<RootView>?
  private var cursorTimer: Timer?
  private var foldWork: DispatchWorkItem?
  private var enteredIsland = false
  private var cancellables = Set<AnyCancellable>()
  /// Signal sources are cancelled if they go out of scope, so they are held.
  private var signalSources: [DispatchSourceSignal] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Started twice — a second double-click in Finder — the second one cannot
    // listen, would draw a second island over the first, and could not serve
    // anyone. It says so and leaves, rather than becoming a second thing on screen
    // that answers nothing.
    if let running = alreadyRunningInstance() {
      FileHandle.standardError.write(Data("notch: another Notch is already running (pid \(running))\n".utf8))
      NSApp.terminate(nil)
      return
    }
    ProcessInfo.processInfo.disableAutomaticTermination("dsh-notch")
    ProcessInfo.processInfo.disableSuddenTermination()
    let panel = NotchPanel(size: NSSize(width: panelW, height: restH))
    // The island is handed the decision and the three ways to answer it, and
    // nothing about where any of them came from.
    let root = RootView(
      model: model,
      service: service,
      consent: service.inbox,
      onConsentAllow: { [weak service] in service?.allow() },
      onConsentDeny: { [weak service] in service?.deny() },
      onConsentDismiss: { [weak service] in service?.dismiss() },
      onAnswer: { [weak service] interactionId, answers in
        service?.answer(interactionID: interactionId, answers: answers)
      },
      onAction: { [weak service] provider, action, key in
        service?.invoke(provider: provider, action: action, key: key)
      },
      onDismiss: { [weak model] in model?.expanded = false },
      panelSize: CGSize(width: panelW, height: restH),
      restSize: CGSize(width: restW, height: restH)
    )
    let hosting = NotchHostingView(rootView: root)
    hosting.sizingOptions = []
    hosting.wantsLayer = true
    hosting.layer?.isOpaque = false
    hosting.layer?.backgroundColor = NSColor.clear.cgColor
    panel.embedHost(hosting)
    panel.ignoresMouseEvents = false
    self.panel = panel
    self.hosting = hosting
    pinToScreen()
    retargetIsland()
    panel.orderFrontRegardless()
    model.start()
    service.start()
    settings.install()
    // Opening it from the command line is how a build can be checked without a
    // hand on the mouse, which is the only way this window gets looked at before
    // it is released.
    if CommandLine.arguments.contains("--settings") { settings.show() }
    // The motion catalogue, which is checked by watching it: a motion that cannot
    // be rendered here is not a motion, whatever the list says.
    if CommandLine.arguments.contains("--motions") { browser.show() }
    // A `kill` is how this process is usually asked to stop, and AppKit does not
    // turn it into a termination on its own. The signal is ignored and turned
    // into an ordinary quit instead, so the endpoint gives up its address on the
    // way out rather than leaving a file the next start has to reason about.
    for number in [SIGTERM, SIGINT] {
      signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
      source.setEventHandler { NSApp.terminate(nil) }
      source.resume()
      signalSources.append(source)
    }
    // A program asking to be allowed is a decision: it opens the island the way
    // a question does, and closes it again once it is answered or set aside.
    service.inbox.$prompt
      .receive(on: DispatchQueue.main)
      .sink { [weak self] prompt in
        guard let self else { return }
        if prompt != nil { self.model.expanded = true }
        else if !self.model.needsAction { self.model.expanded = false }
      }
      .store(in: &cancellables)

    // A question opens the island when it arrives and closes it when it is
    // settled, which is what the board's own questions have always done. Work in
    // progress does neither: it is what the capsule is for.
    // What the capsule counts comes from the providers whenever they are showing
    // anything: the board is one provider's private route into the island, and the
    // capsule should not be the last thing that still needs it.
    model.surfaceCounts = { [weak service] in
      guard let surface = service?.surface, !surface.isEmpty else { return nil }
      return surface.summary
    }

    model.capsuleTargets = { [weak service] in
      guard let surface = service?.surface else { return (failed: nil, completed: nil) }
      func first(_ predicate: (Presented) -> Bool) -> Presented? {
        for slot in surface.slots {
          if case .entity(let presented) = slot, predicate(presented) { return presented }
        }
        return nil
      }
      return (
        failed: first { $0.behaviourClass == .result && $0.state == "failed" },
        completed: first { $0.behaviourClass == .result && $0.unread == true && $0.state != "failed" }
      )
    }

    service.$surface
      .receive(on: DispatchQueue.main)
      .sink { [weak self] surface in
        guard let self else { return }
        // One place turns a change into a motion, whatever changed and whoever
        // changed it: the transition is read from the surface, resolved through
        // the catalogue, and only then played.
        if let before = self.lastSurface, let transition = PresenceReading.between(before, surface) {
          let resolved = self.motions.resolve(transition)
          self.model.play(resolved.motion, from: before, to: surface)
        }
        self.lastSurface = surface
        let interactionId = surface.decision?.interaction?.id
        self.model.pendingDecision = surface.decision != nil || surface.waiting != nil
        // A lamp is drawn from these counts, so a change in them is a change to
        // draw — including one no board ever saw.
        self.model.updateOrbitLayout()
        if interactionId != nil { self.model.expanded = true }
        else if !self.model.needsAction { self.model.expanded = false }
      }
      .store(in: &cancellables)
    Publishers.CombineLatest3(model.$expanded, model.$currentIslandWidth, model.$currentIslandHeight)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.retargetIsland() }
      .store(in: &cancellables)
    cursorTimer = commonModeTimer(interval: 0.05, tolerance: 0.01) { [weak self] in
      self?.tickPointer()
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(pinToScreen),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  @objc private func pinToScreen() {
    guard let panel else { return }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
    guard let screen else { return }
    let visible = screen.visibleFrame
    let layout = NotchScreenLayout(availableHeight: visible.height, preferredInset: topOffset)
    model.maximumExpandedHeight = layout.maximumHeight
    // Anchor the island to the upper-right edge, ~100pt below the top of the
    // usable screen. A walkthrough stands it off that edge so a reviewer can see
    // the overlay and the window behind it at the same time.
    let walkthroughInset: CGFloat = walkthroughMode ? 360 : 0
    let width = max(1, model.currentIslandWidth)
    let height = min(max(1, model.currentIslandHeight), model.maximumExpandedHeight)
    panel.pin(
      island: NSSize(width: width, height: height),
      topRight: NSPoint(x: visible.maxX - walkthroughInset, y: visible.maxY - layout.edgeInset)
    )
  }

  /// Whether the pointer is over the island rather than its transparent
  /// container. The container is deliberately larger than the island while the
  /// island is animating, and a pointer over that empty margin is not hovering.
  private func pointerOverVisual() -> Bool {
    guard let panel else { return false }
    return panel.islandFrame.contains(NSEvent.mouseLocation)
  }

  private func tickPointer() {
    guard panel != nil else { return }
    let hit = pointerOverVisual()
    // The only source of truth for the rest capsule's hover shape. The capsule
    // carries its own `onHover`, but that view exists only while the compact
    // content is on screen: it cannot report a pointer that left during an
    // expanded panel, which left the collapsed capsule stuck in its hovered
    // shape. It also re-decided mid-animation, because the growing window moves
    // its own edge across a resting pointer.
    //
    // Announced only on a real change: `@Published` fires on every assignment,
    // and this tick runs twenty times a second for the life of the process, so
    // an unconditional assignment would re-render the whole tree forever.
    if model.isPillHovered != hit { model.isPillHovered = hit }
    if hit {
      enteredIsland = true
      foldWork?.cancel()
      foldWork = nil
      model.foldEnabled = true
      // Expand when hovering if there are items needing action or if user triggered expansion.
      if !model.expanded && (model.needsAction || model.allowExpandOnHover || service.surface.decision != nil) {
        // Setting `expanded` retargets the island, and the geometry observer
        // resizes the panel from the new target. Resizing here as well would
        // use the pre-expansion size and restart the spring for nothing.
        model.expanded = true
      }
      return
    }
    // A guided local walkthrough stays visible until its test answer is sent.
    if walkthroughMode && model.needsAction { return }
    guard model.expanded, model.foldEnabled, enteredIsland, foldWork == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.foldWork = nil
        if self.pointerOverVisual() { return }
        self.enteredIsland = false
        self.model.expanded = false
        self.panel?.orderFrontRegardless()
      }
    }
    foldWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
  }

  /// Whether the DSH Host is still there, for what still reads it.
  ///
  /// This used to decide when Notch exits, which made the surface a possession of
  /// one host: it appeared when that host started and left when that host did. A
  /// surface any program can ask to speak through cannot also be a program's
  /// dependent — the user runs it, and it stays until the user stops it. What is
  /// left here is a fact about the old HTTP path, which the shell reports and acts
  /// on by showing that it is waiting for a Host rather than by disappearing.
  private var hostIsThere: Bool {
    hostProcessIsAlive() ?? false
  }

  /// Another copy of this program, if one is running.
  ///
  /// Asked of the process table rather than of the socket, because the copy that
  /// is running may have been started before this one and holds the address: the
  /// answer wanted here is "is there already a Notch", not "is the endpoint free".
  /// - Returns: its process id, or nothing.
  private func alreadyRunningInstance() -> pid_t? {
    let mine = getpid()
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-x", "-o", "pid=,comm="]
    let pipe = Pipe()
    task.standardOutput = pipe
    guard (try? task.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      let parts = line.split(separator: " ", omittingEmptySubsequences: true)
      guard parts.count >= 2, let pid = pid_t(parts[0]), pid != mine else { continue }
      let name = (String(parts[1]) as NSString).lastPathComponent
      if name == "Notch" || name == "dsh-notch" { return pid }
    }
    return nil
  }

  /// Give up the endpoint on the way out.
  ///
  /// The address is a file, and a file that outlives its listener makes the next
  /// start look like a conflict — which the endpoint handles, by checking whether
  /// anything is actually listening. Removing it here means that check is a
  /// fallback for a crash rather than the ordinary path.
  func applicationWillTerminate(_ notification: Notification) {
    service.stop()
  }

  /// Point the panel at the island size the SwiftUI animation is heading for.
  /// The panel only sizes its transparent container; the drawn island is the
  /// animation's own business.
  private func retargetIsland() {
    guard let panel else { return }
    let width = max(1, model.currentIslandWidth)
    let height = min(max(1, model.currentIslandHeight), model.maximumExpandedHeight)
    panel.resizeAnchored(to: NSSize(width: width, height: height))
  }
}
