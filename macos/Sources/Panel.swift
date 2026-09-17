import AppKit
import SwiftUI

/// A repeating timer that keeps firing while the run loop is in a tracking mode.
///
/// `Timer.scheduledTimer` installs in `.default` only, and macOS switches the
/// main run loop to `.eventTracking` whenever the pointer is moving over a
/// view, a control is being dragged, or the window is resizing. Timers left in
/// `.default` stop for exactly those intervals — so a pointer poll that decides
/// hover, and the animation clocks that draw the result, freeze under the very
/// cursor that is watching them, then jump to catch up.
///
/// The body runs on the main actor synchronously. A timer added to the main run
/// loop already fires on the main thread, so the usual `Task { @MainActor in }`
/// wrapper would only add a scheduler hop to every frame.
/// @param interval - seconds between fires.
/// @param tolerance - slack the system may use to batch this timer with others.
/// Polling timers run for the life of the process, so a little tolerance lets
/// the CPU stay in a deeper idle state instead of waking for each one alone.
/// @param body - work to perform on the main actor.
/// @returns the installed timer, already scheduled in `.common` modes.
@discardableResult
func commonModeTimer(interval: TimeInterval, tolerance: TimeInterval = 0, _ body: @escaping @MainActor () -> Void) -> Timer {
  let timer = Timer(timeInterval: interval, repeats: true) { _ in
    MainActor.assumeIsolated { body() }
  }
  timer.tolerance = tolerance
  RunLoop.main.add(timer, forMode: .common)
  return timer
}

enum NotchGeometryAnimation {
  /// The island's own travel: the capsule's shape and size, and how fast it
  /// answers the pointer.
  ///
  /// This is the shell and nothing else. What is drawn inside it — the cube, the
  /// lamps, the ring — keeps its own pace, which is set where each of those is
  /// drawn; a shell that answers the pointer quickly is not a reason for the
  /// contents to change quickly too, and reading this value from them is how that
  /// happened once already. The container's settle delay and how long a collapse
  /// keeps its content do read `duration`, because those are the shell's own
  /// bookkeeping rather than anything drawn.
  static let animation = Animation.spring(duration: 0.26, bounce: 0.08)
  static let duration: TimeInterval = 0.26
}

/// How fast what is drawn inside the island changes.
///
/// Separate from the shell's travel on purpose: the shapes the user watches —
/// the cube, the lamps, the panel's content — change at the pace they were
/// authored for, and the shell can be made to answer the pointer as quickly as it
/// likes without touching them.
enum NotchContentAnimation {
  /// A panel's content appearing or going away.
  static let fade = Animation.easeOut(duration: 0.28)
  static let fadeDuration: TimeInterval = 0.28
  /// The contents answering the pointer, which is a gesture rather than a state
  /// change: quick enough to feel like a response, slower than the shell so the
  /// two do not arrive together.
  static let hover = Animation.easeOut(duration: 0.22)
}

final class NotchPanel: NSPanel {
  /// The island's intended size.
  ///
  /// The window is only a transparent container that has to be large enough to
  /// draw the island; the island itself is drawn by SwiftUI at whatever size the
  /// running animation is on. Window frames are quantised to whole points, so
  /// animating the container would quantise the island's motion too — a 4pt
  /// hover morph would have five representable positions and read as a
  /// staircase. A view's frame has no such limit, so the island animates there.
  private(set) var islandSize: NSSize = .zero
  private var settleTimer: Timer?

  /// The island's rectangle on screen, derived from the container's top-right
  /// corner, which the island is anchored to.
  var islandFrame: NSRect {
    NSRect(x: frame.maxX - islandSize.width, y: frame.maxY - islandSize.height,
           width: islandSize.width, height: islandSize.height)
  }

  /// One container size, anchored to the current top-right corner.
  private func anchored(_ size: NSSize) -> NSRect {
    NSRect(x: frame.maxX - size.width, y: frame.maxY - size.height, width: size.width, height: size.height)
  }

  func cancelResize() {
    settleTimer?.invalidate()
    settleTimer = nil
  }

  /// Retarget the island.
  ///
  /// The container grows immediately, because an island mid-animation must never
  /// be clipped. It shrinks only once the animation has finished, so the extra
  /// transparent area — which does swallow clicks — is short-lived rather than
  /// the island's permanent footprint.
  /// @param size - the island size the SwiftUI animation is heading for.
  func resizeAnchored(to size: NSSize) {
    guard size.width > 0, size.height > 0 else { return }
    guard islandSize != size else { return }
    islandSize = size
    let container = NSSize(width: max(frame.width, size.width), height: max(frame.height, size.height))
    if container != frame.size { setFrame(anchored(container), display: true) }
    cancelResize()
    settleTimer = commonModeTimer(interval: NotchGeometryAnimation.duration + 0.03) { [weak self] in
      guard let self else { return }
      self.settleTimer?.invalidate()
      self.settleTimer = nil
      let settled = self.anchored(self.islandSize)
      if settled.size != self.frame.size { self.setFrame(settled, display: true) }
    }
  }

  /// Place the island for a screen anchor, with no animation.
  /// @param size - island size to start from.
  /// @param topRight - screen point the island's top-right corner sits on.
  func pin(island size: NSSize, topRight: NSPoint) {
    cancelResize()
    islandSize = size
    setFrame(NSRect(x: topRight.x - size.width, y: topRight.y - size.height, width: size.width, height: size.height), display: true)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  // An accessory panel has no active app Edit menu to route Command keys.
  // Handle only standard editing commands, and only for our focused editor.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isKeyWindow, let editor = firstResponder as? NSTextView else {
      return super.performKeyEquivalent(with: event)
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else {
      return super.performKeyEquivalent(with: event)
    }
    let key = event.charactersIgnoringModifiers?.lowercased()
    if flags.contains(.shift) {
      if key == "z", editor.isEditable, let undo = editor.undoManager, undo.canRedo {
        undo.redo()
        return true
      }
      return super.performKeyEquivalent(with: event)
    }
    switch key {
    case "a": editor.selectAll(nil)
    case "c": editor.copy(nil)
    case "x" where editor.isEditable: editor.cut(nil)
    case "v" where editor.isEditable: editor.paste(nil)
    case "z" where editor.isEditable:
      guard let undo = editor.undoManager, undo.canUndo else {
        return super.performKeyEquivalent(with: event)
      }
      undo.undo()
    default: return super.performKeyEquivalent(with: event)
    }
    return true
  }

  convenience init(size: NSSize) {
    self.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    appearance = NSAppearance(named: .darkAqua)
    hasShadow = false
    isMovable = false
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
    isReleasedWhenClosed = false
  }

  /// Put the SwiftUI host on a transparent container.
  ///
  /// The container paints nothing: the island is drawn by SwiftUI, which is the
  /// only way it can move at sub-point precision. An `NSVisualEffectView` is
  /// also ruled out — a behind-window blur re-samples and re-blurs the desktop
  /// behind the panel on every frame of a geometry animation.
  func embedHost(_ hosting: NSView) {
    let container = NSView(frame: contentView?.bounds ?? NSRect(origin: .zero, size: frame.size))
    container.autoresizingMask = [.width, .height]
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.clear.cgColor
    container.layer?.masksToBounds = false
    contentView = container
    hosting.autoresizingMask = [.width, .height]
    hosting.frame = container.bounds
    hosting.wantsLayer = true
    hosting.layer?.isOpaque = false
    hosting.layer?.backgroundColor = NSColor.clear.cgColor
    container.addSubview(hosting)
  }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
  override var isOpaque: Bool { false }

  // The panel is intentionally nonactivating. A click must reach SwiftUI
  // controls immediately, even while another app is the active application.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct NotchScreenLayout {
  let edgeInset: CGFloat
  let maximumHeight: CGFloat

  init(availableHeight: CGFloat, preferredInset: CGFloat = 100) {
    let height = max(1, availableHeight)
    edgeInset = min(preferredInset, max(0, (height - 1) / 2))
    maximumHeight = height - 2 * edgeInset
  }
}
