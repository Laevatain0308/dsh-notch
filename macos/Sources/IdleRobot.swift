import AppKit
import SwiftUI

struct IdleEye: Decodable {
  var x: Double; var y: Double; var w: Double; var h: Double
  var r: Double; var angle: Double; var opacity: Double
}
struct IdleFrame: Decodable {
  var points: [[Double]]; var eyes: [IdleEye]; var body: Int; var eye: Int
}
struct IdleClip: Decodable {
  var fps: Double; var duration: Double; var frames: [IdleFrame]
}

enum IdleInterpolation {
  static func mix(_ a: IdleFrame, _ b: IdleFrame, _ t: Double) -> IdleFrame {
    let w = max(0, min(1, t))
    func n(_ x: Double, _ y: Double) -> Double { x + (y-x)*w }
    func color(_ x: Int, _ y: Int) -> Int {
      [16,8,0].reduce(0) { $0 | (Int(n(Double((x >> $1)&255), Double((y >> $1)&255)).rounded()) << $1) }
    }
    let points = zip(a.points,b.points).map { [n($0[0],$1[0]),n($0[1],$1[1])] }
    let eyes = zip(a.eyes,b.eyes).map { e,f in
      IdleEye(x:n(e.x,f.x),y:n(e.y,f.y),w:n(e.w,f.w),h:n(e.h,f.h),r:n(e.r,f.r),angle:n(e.angle,f.angle),opacity:n(e.opacity,f.opacity))
    }
    return IdleFrame(points:points,eyes:eyes,body:color(a.body,b.body),eye:color(a.eye,b.eye))
  }
  static func smooth(_ value: Double) -> Double {
    let t=max(0,min(1,value));return t*t*t*(t*(t*6-15)+10)
  }
}

@MainActor
final class IdleLibrary {
  static let shared = IdleLibrary()
  private var clips: [String: IdleClip] = [:]
  func clip(_ id: String) -> IdleClip? {
    if let clip = clips[id] { return clip }
    guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Idle"),
          let data = try? Data(contentsOf: url), let clip = try? JSONDecoder().decode(IdleClip.self, from: data),
          !clip.frames.isEmpty else { return nil }
    clips[id] = clip
    return clip
  }
}

/// Only advances while an idle robot is visible. Screen sleep never queues overdue gags.
@MainActor
final class IdleDirector: ObservableObject {
  static let basics = ["blink", "scan", "tilt", "nod", "stretch", "hop", "balance", "sneeze", "sleep"]
  @Published var action: String? = "blink"
  @Published var began = Date()
  @Published var asleep = false
  private var timer: Timer?
  private var nextBasic = Date()
  private var nextRare = Date()
  private var previous = "blink"
  private var blendFrom: IdleFrame?
  private var blendBegan = Date()
  var animating: Bool { action != nil || blendFrom != nil }
  func frame(at now: Date) -> IdleFrame? {
    guard let neutral=IdleLibrary.shared.clip("blink")?.frames.first else { return nil }
    var target=neutral
    if let id=action,let clip=IdleLibrary.shared.clip(id) {
      let elapsed=max(0,now.timeIntervalSince(began))
      let position=min(elapsed*clip.fps,Double(clip.frames.count-1))
      let index=Int(position)
      target=IdleInterpolation.mix(clip.frames[index],clip.frames[min(index+1,clip.frames.count-1)],position-Double(index))
      if id == "dance" {
        let weight=IdleInterpolation.smooth(min(elapsed/0.35,(clip.duration-elapsed)/0.45))
        target=IdleInterpolation.mix(neutral,target,weight)
      }
    }
    if let source=blendFrom {
      return IdleInterpolation.mix(source,target,IdleInterpolation.smooth(now.timeIntervalSince(blendBegan)/0.35))
    }
    return target
  }
  private func beginBlend(from source: IdleFrame?, at now: Date) { blendFrom=source;blendBegan=now }

  private var sequence = 0
  private var observers: [NSObjectProtocol] = []
  var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  func start(playImmediately: Bool = true) {
    guard timer == nil else { return }
    blendFrom = nil
    began = Date(); action = reduceMotion || !playImmediately ? nil : "blink"
    schedule(from: began)
    let nc = NSWorkspace.shared.notificationCenter
    observers = [nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.asleep = true; self?.action = nil }
    }, nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in guard let self else { return }; self.asleep = false; self.schedule(from: Date()) }
    }]
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick(Date()) }
    }
  }
  private func schedule(from date: Date) {
    nextBasic = date.addingTimeInterval(Double.random(in: 20...45))
    nextRare = date.addingTimeInterval(Double.random(in: 1200...2400))
  }
  func tick(_ now: Date) {
    guard !asleep, !reduceMotion else { blendFrom = nil; action = nil; return }
    if blendFrom != nil && now.timeIntervalSince(blendBegan) >= 0.35 { blendFrom = nil; objectWillChange.send() }
    if let action {
      let duration = IdleLibrary.shared.clip(action)?.duration ?? 7
      if now.timeIntervalSince(began) >= duration { let source=frame(at:now); beginBlend(from:source,at:now); self.action = nil; nextBasic = now.addingTimeInterval(Double.random(in: 20...45)) }
      return
    }
    if now >= nextRare {
      play("dance"); nextRare = now.addingTimeInterval(Double.random(in: 1200...2400))
    } else if now >= nextBasic {
      play(Self.basics.filter { $0 != previous }.randomElement() ?? "blink")
    }
  }
  func play(_ id: String, at now: Date = Date()) {
    guard !asleep, !reduceMotion else { return }
    guard IdleLibrary.shared.clip(id) != nil else { return }
    let source=frame(at:now)
    beginBlend(from:source,at:now)
    previous = id; began = now; action = id
    if id == "dance" { nextRare = began.addingTimeInterval(Double.random(in: 1200...2400)) }
  }
  func resume(_ id: String, elapsed: Double, from source: IdleFrame? = nil) {
    guard !reduceMotion, !asleep else { return }
    beginBlend(from:source,at:Date())
    previous = id; action = id; began = Date().addingTimeInterval(-elapsed)
  }
  func tryNext() { play(Self.basics[sequence % Self.basics.count]); sequence += 1 }
  func stop() {
    timer?.invalidate(); timer = nil; action = nil; blendFrom = nil
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observers.removeAll()
  }
}

struct IdleRobotCanvas: View {
  let clip: IdleClip?
  let elapsed: Double
  var visibility: Double = 1
  var entering: Bool = false
  private func color(_ rgb: Int) -> Color {
    Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
  }
  var body: some View {
    let neutralFrame = IdleLibrary.shared.clip("blink")?.frames.first
    return Canvas { context, size in
      guard let clip, !clip.frames.isEmpty else { return }
      // Sampled vector paths are interpolated at display cadence, never enlarged bitmaps.
      let position = min(max(0, elapsed * clip.fps), Double(clip.frames.count - 1))
      let index = Int(position), amount = position - Double(index)
      let a = clip.frames[index], b = clip.frames[min(index + 1, clip.frames.count - 1)]
      let edge = clip.duration > 10 ? min(1, max(0, min(elapsed / 0.35, (clip.duration - elapsed) / 0.45))) : 1
      let danceBlend = edge * edge * (3 - 2 * edge)
      func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * amount }
      func mixedColor(_ x: Int, _ y: Int) -> Color {
        Color(red: mix(Double((x >> 16) & 255), Double((y >> 16) & 255)) / 255,
              green: mix(Double((x >> 8) & 255), Double((y >> 8) & 255)) / 255,
              blue: mix(Double(x & 255), Double(y & 255)) / 255)
      }
      context.translateBy(x: size.width / 2, y: size.height / 2)
      context.scaleBy(x: 40.0 / 280.0, y: 40.0 / 280.0)
      var centerX = 0.0, centerY = 0.0
      for i in a.points.indices {
        let n = neutralFrame?.points[i] ?? a.points[i]
        centerX += mix(a.points[i][0], b.points[i][0]) * danceBlend + n[0] * (1-danceBlend)
        centerY += mix(a.points[i][1], b.points[i][1]) * danceBlend + n[1] * (1-danceBlend)
      }
      centerX /= Double(a.points.count); centerY /= Double(a.points.count)
      var bodyPath = Path()
      for i in a.points.indices {
        let q = a.points[i], r = b.points[i]
        let n = neutralFrame?.points[i] ?? q
        let x = mix(q[0], r[0]) * danceBlend + n[0] * (1 - danceBlend)
        let y = mix(q[1], r[1]) * danceBlend + n[1] * (1 - danceBlend)
        let angle = atan2(y - centerY, x - centerX)
        let radius = (entering ? 2.5 : 9.5) * 280.0 / 40.0
        let point = CGPoint(x: x * visibility + cos(angle) * radius * (1 - visibility),
                            y: y * visibility + sin(angle) * radius * (1 - visibility))
        if i == 0 { bodyPath.move(to: point) } else { bodyPath.addLine(to: point) }
      }
      bodyPath.closeSubpath()
      // Dance begins and ends through the neutral body, retaining original bounce speed.
      let pigment = mixedColor(a.body, b.body)
      var filled = context
      filled.opacity = entering ? 1 : max(0, (visibility - 0.30) / 0.70)
      filled.fill(bodyPath, with: .color(color(0xe5e5e7)))
      var painted = filled; painted.opacity *= danceBlend; painted.fill(bodyPath, with: .color(pigment))
      if !entering && visibility < 1 {
        var outline = context; outline.opacity = min(1, (1 - visibility) * 3) * min(1, visibility * 4)
        func inkChannel(_ shift: Int, _ neutral: Double, _ blue: Double) -> Double {
          let current = mix(Double((a.body >> shift) & 255), Double((b.body >> shift) & 255)) * danceBlend + neutral * (1-danceBlend)
          return (current * visibility + blue * (1-visibility))/255
        }
        let ink = Color(red: inkChannel(16,229,77), green: inkChannel(8,229,107), blue: inkChannel(0,231,254))
        outline.stroke(bodyPath, with: .color(ink), lineWidth: 1.7 * 280/40)
      }
      context.clip(to: bodyPath)
      for i in a.eyes.indices where i < b.eyes.count {
        let rawE = a.eyes[i], rawF = b.eyes[i]
        let neutral = neutralFrame?.eyes[i] ?? rawE
        func blendEye(_ v: IdleEye) -> IdleEye {
          func blend(_ x: Double, _ n: Double) -> Double { x*danceBlend+n*(1-danceBlend) }
          return IdleEye(x:blend(v.x,neutral.x),y:blend(v.y,neutral.y),w:blend(v.w,neutral.w),h:blend(v.h,neutral.h),r:blend(v.r,neutral.r),angle:blend(v.angle,neutral.angle),opacity:blend(v.opacity,neutral.opacity))
        }
        let e = blendEye(rawE), f = blendEye(rawF)
        var eyeContext = context
        eyeContext.translateBy(x: mix(e.x, f.x) * visibility, y: mix(e.y, f.y) * visibility)
        eyeContext.rotate(by: .degrees(mix(e.angle, f.angle)))
        eyeContext.opacity = mix(e.opacity, f.opacity) * max(0, min(1, (visibility - 0.60) / 0.40))
        let w = mix(e.w, f.w), h = mix(e.h, f.h), r = mix(e.r, f.r)
        eyeContext.fill(Path(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerRadius: r), with: .color(mixedColor(a.eye, b.eye)))
      }
    }
    .allowsHitTesting(false)
  }
}

@MainActor
final class IdlePresence: ObservableObject {
  @Published var visibility: Double = 1
  @Published var entering = true
  var frozenFrame: IdleFrame?
  var frozenID = "blink"
  var frozenElapsed = 0.0
  private var timer: Timer?
  private var generation = 0
  func set(_ idle: Bool, director: IdleDirector, animated: Bool = true) {
    timer?.invalidate(); timer = nil
    generation += 1; let current = generation
    if !idle {
      if visibility >= 1 {
      frozenFrame = director.frame(at: Date())
      frozenID = director.action ?? "blink"
      frozenElapsed = director.action == nil ? 0 : max(0, Date().timeIntervalSince(director.began))
      }
      director.stop()
    } else {
      director.start(playImmediately: false)
      // Continue the same geometry when a partially completed transition reverses.
      if visibility == 0 { frozenID = "blink"; frozenElapsed = 0; frozenFrame = IdleLibrary.shared.clip("blink")?.frames.first }
    }
    // Preserve circle geometry when reversing mid-flight.
    if visibility == 0 || visibility == 1 { entering = idle }
    let start = visibility, end = idle ? 1.0 : 0.0
    guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { visibility = end; return }
    let began = ProcessInfo.processInfo.systemUptime
    timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.generation == current else { return }
        let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / (idle ? 0.4 : 0.3))
        let smooth = t*t*t*(t*(t*6-15)+10)
        self.visibility = start + (end-start)*smooth
        if t >= 1 {
          self.timer?.invalidate(); self.timer = nil
          if idle { director.resume(self.frozenID, elapsed: self.frozenElapsed, from:self.frozenFrame) }
        }
      }
    }
  }
  func stop() { generation += 1; timer?.invalidate(); timer = nil }
}

struct IdleStatusSlot: View {
  @ObservedObject var model: BoardModel
  @StateObject private var director = IdleDirector()
  @StateObject private var presence = IdlePresence()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var idle: Bool { !model.needsAction && !model.anyFailed && model.completedUnreadCount == 0 && model.busyCount == 0 && model.statusFlight == nil }
  private var hasStatus: Bool { model.anyFailed || model.completedUnreadCount > 0 || model.busyCount > 0 || model.statusFlight != nil }
  var body: some View {
    ZStack {
      if hasStatus {
        StatusOrbitView(model: model).opacity(1 - presence.visibility)
      }
      if presence.visibility > 0 || idle {
        TimelineView(.animation(minimumInterval: 1/60.0, paused: !director.animating || director.asleep || reduceMotion)) { timeline in
          let stable = idle && presence.visibility >= 1
          let frame = stable ? director.frame(at: timeline.date) : presence.frozenFrame
          let sampled = frame.map { IdleClip(fps:1,duration:7,frames:[$0]) }
          IdleRobotCanvas(clip: sampled, elapsed: 0, visibility: presence.visibility, entering: presence.entering)
        }
        .frame(width: 30, height: 42)
        .accessibilityLabel("待机机器人")
        .contextMenu {
          if idle {
            Button("试试下一个待机动作") { director.tryNext() }
            Button("播放变色跳舞彩蛋") { director.play("dance") }
          }
        }
      }
    }
    .frame(height: !hasStatus && !idle ? 0 : nil)
    .onAppear { presence.set(idle, director: director, animated: false) }
    .onChange(of: idle) { _, value in presence.set(value, director: director) }
    .onDisappear { presence.stop(); director.stop() }
  }
}
