import SwiftUI

struct StatusFlight: Identifiable {
  let id = UUID()
  let failed: Bool
  let startedAt: Date
  let busyBefore: Int
  let destinationBefore: Int
  let returnsToRunning: Bool
  init(failed: Bool, startedAt: Date, busyBefore: Int, destinationBefore: Int, returnsToRunning: Bool = true) {
    self.failed = failed
    self.startedAt = startedAt
    self.busyBefore = busyBefore
    self.destinationBefore = destinationBefore
    self.returnsToRunning = returnsToRunning
  }
  static let duration: TimeInterval = 1.6
}

struct OrbitMotionFrame {
  let progress: Double
  let failed: Bool
  let returns: Bool
  let distance: CGFloat
  let tailLength: CGFloat
  let tint: Double
  let resultOpacity: Double
  let sourceOpacity: Double
  let arrived: Bool
  let returning: Bool
  let returned: Bool
  static func ease(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
  }
  init(progress: Double, failed: Bool, returns: Bool, angle: Double = 0) {
    self.progress = min(1, max(0, progress))
    self.failed = failed
    self.returns = returns
    let route = OrbitBrushRoute(failed: failed, angle: angle)
    let end = returns ? route.total : route.resultDrawn + 18
    let head = route.departure + (end - route.departure) * Self.ease(self.progress)
    distance = min(head, returns ? route.total : route.resultDrawn)
    let outbound = Self.ease((head - route.sourceExit) / (route.arrival - route.sourceExit))
    let inbound = Self.ease((head - route.resultDrawn + 8) / (route.returned - route.resultDrawn + 16))
    let tintStart = max(route.departure, route.sourceExit - 8)
    let outgoingTint = Self.ease((head - tintStart) / (route.arrival + 8 - tintStart))
    tint = returns && head > route.resultDrawn - 8 ? 1 - inbound : outgoingTint
    resultOpacity = Self.ease((head - route.arrival - 0.55 * (route.resultDrawn - route.arrival)) / (0.35 * (route.resultDrawn - route.arrival)))
    arrived = resultOpacity > 0
    returning = returns && head > route.resultDrawn
    returned = returns && head >= route.returned
    sourceOpacity = returns ? 1 : 1 - outbound
    if head < route.arrival { tailLength = route.departure + (18 - route.departure) * outbound }
    else if !returns && head > route.resultDrawn { tailLength = max(0, 18 - (head - route.resultDrawn)) }
    else if head > route.returned {
      let t = (head - route.returned) / (route.total - route.returned)
      tailLength = 18 + (route.departure - 18) * t
    } else { tailLength = 18 }
  }
}

/// An arc-length trail: the head draws forward and the tail follows on the same route.
struct OrbitBrushRoute {
  private(set) var points: [CGPoint] = []
  private(set) var lengths: [CGFloat] = []
  private(set) var departure: CGFloat = 0
  private(set) var sourceExit: CGFloat = 0
  private(set) var arrival: CGFloat = 0
  private(set) var resultDrawn: CGFloat = 0
  private(set) var returned: CGFloat = 0
  var total: CGFloat { lengths.last ?? 0 }

  init(failed: Bool, angle: Double) {
    let r: CGFloat = 9.5
    let direction: CGFloat = failed ? 1 : -1
    let y = direction * 28
    arc(center: .zero, from: angle, sweep: 1.4 * .pi, radius: r)
    departure = total
    let exitAngle = failed ? Double.pi / 2 : -Double.pi / 2
    let sourceHead = angle + 1.4 * .pi
    let extra = (exitAngle - sourceHead).truncatingRemainder(dividingBy: 2 * .pi)
    arc(center: .zero, from: sourceHead, sweep: extra < 0 ? extra + 2 * .pi : extra, radius: r)
    sourceExit = total
    let start = points.last!
    curve(from: start, c1: CGPoint(x: start.x - 4 * sin(exitAngle), y: start.y + 4 * cos(exitAngle)),
          c2: CGPoint(x: -r, y: y + 10), to: CGPoint(x: -r, y: y))
    arrival = total
    arc(center: CGPoint(x: 0, y: y), from: .pi, sweep: 2 * .pi, radius: r)
    resultDrawn = total
    let finalAngle = angle + StatusFlight.duration * 2 * .pi / 3
    let end = CGPoint(x: r * cos(exitAngle), y: r * sin(exitAngle))
    curve(from: points.last!, c1: CGPoint(x: -r, y: y - 10),
          c2: CGPoint(x: end.x + 4 * sin(exitAngle), y: end.y - 4 * cos(exitAngle)), to: end)
    returned = total
    let resume = (finalAngle - exitAngle).truncatingRemainder(dividingBy: 2 * .pi)
    arc(center: .zero, from: exitAngle, sweep: (resume < 0 ? resume + 2 * .pi : resume) + 1.4 * .pi, radius: r)
  }

  func range(for frame: OrbitMotionFrame) -> ClosedRange<CGFloat> {
    max(0, frame.distance - frame.tailLength)...frame.distance
  }

  func path(in range: ClosedRange<CGFloat>) -> Path {
    var path = Path()
    guard range.upperBound - range.lowerBound > 0.01 else { return path }
    var began = false
    for i in 1..<points.count {
      let a = lengths[i - 1], b = lengths[i]
      guard b > a, b >= range.lowerBound, a <= range.upperBound else { continue }
      let lo = max(a, range.lowerBound), hi = min(b, range.upperBound)
      func point(_ d: CGFloat) -> CGPoint {
        let t = (d - a) / (b - a)
        return CGPoint(x: points[i-1].x + (points[i].x-points[i-1].x)*t,
                       y: points[i-1].y + (points[i].y-points[i-1].y)*t)
      }
      if !began { path.move(to: point(lo)); began = true }
      path.addLine(to: point(hi))
    }
    return path
  }

  private mutating func append(_ point: CGPoint) {
    let distance = points.last.map { hypot(point.x - $0.x, point.y - $0.y) } ?? 0
    lengths.append(total + distance)
    points.append(point)
  }
  private mutating func arc(center: CGPoint, from: Double, sweep: Double, radius: CGFloat) {
    for i in 0...96 {
      let a = from + sweep * Double(i) / 96
      append(CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
    }
  }
  private mutating func curve(from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint) {
    for i in 1...64 {
      let t = CGFloat(i) / 64, u = 1 - t
      append(CGPoint(x: u*u*u*from.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*to.x,
                     y: u*u*u*from.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*to.y))
    }
  }
}

struct OrbitStroke: Shape {
  let frame: OrbitMotionFrame
  let angle: Double
  func path(in rect: CGRect) -> Path {
    let route = OrbitBrushRoute(failed: frame.failed, angle: angle)
    return route.path(in: route.range(for: frame)).offsetBy(dx: rect.midX, dy: rect.midY)
  }
}

struct StatusOrbitView: View {
  @ObservedObject var model: BoardModel
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  var reduceMotionOverride: Bool? = nil
  private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

  private var showTop: Bool { model.completedUnreadCount > 0 || model.statusFlight?.failed == false }
  private var showBottom: Bool { model.failedRows.count > 0 || model.statusFlight?.failed == true }
  private var showMiddle: Bool { model.busyCount > 0 || model.statusFlight != nil }
  private var lampCount: Int { [showTop, showMiddle, showBottom].filter { $0 }.count }
  private var totalHeight: CGFloat { 20 + CGFloat(max(0, lampCount - 1)) * 28 }
  private var originY: CGFloat { showTop ? 38 : 10 }
  private var bottomY: CGFloat { 10 + (showTop ? 28 : 0) + (showMiddle ? 28 : 0) }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || (model.busyCount == 0 && model.statusFlight == nil))) { context in
      let flight = reduceMotion ? nil : model.statusFlight
      let progress = flight.map { context.date.timeIntervalSince($0.startedAt) / StatusFlight.duration } ?? 1
      let motion = flight.map { OrbitMotionFrame(progress: progress, failed: $0.failed, returns: $0.returnsToRunning, angle: $0.startedAt.timeIntervalSinceReferenceDate * 2 * .pi / 3) }
      let angle = context.date.timeIntervalSinceReferenceDate * 2 * .pi / 3
      ZStack(alignment: .topLeading) {
        if showTop {
          let count = flight?.failed == false && motion?.arrived == false ? flight!.destinationBefore : model.completedUnreadCount
          statusDisk(count: count, color: NotchTokens.greenComplete, opacity: flight?.failed == false && flight?.destinationBefore == 0 ? (motion?.resultOpacity ?? 1) : 1)
            .position(x: 15, y: 10)
        }
        if showMiddle {
          let count = flight != nil && motion?.returned == false ? flight!.busyBefore : model.busyCount
          ZStack {
            Circle().fill(Color.black).frame(width: 15, height: 15)
            if flight == nil && model.busyCount > 0 {
              Circle().trim(from: 0, to: 0.70)
                .stroke(NotchTokens.deepSeekBlue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.radians(reduceMotion ? 0 : angle))
            }
            Text("\(count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(NotchTokens.deepSeekBlue)
              .opacity(count > 0 ? (motion?.sourceOpacity ?? 1) : 0)
          }
          .frame(width: 19, height: 19)
          .position(x: 15, y: originY)
        }
        if showBottom {
          let count = flight?.failed == true && motion?.arrived == false ? flight!.destinationBefore : model.failedRows.count
          statusDisk(count: count, color: NotchTokens.redFail, opacity: flight?.failed == true && flight?.destinationBefore == 0 ? (motion?.resultOpacity ?? 1) : 1)
            .position(x: 15, y: bottomY)
        }
        if let flight, let motion {
          let target = flight.failed ? (1.0, 0.251, 0.0) : (0.204, 0.780, 0.349)
          let color = Color(red: 0.302 + (target.0 - 0.302) * motion.tint,
                            green: 0.420 + (target.1 - 0.420) * motion.tint,
                            blue: 0.996 + (target.2 - 0.996) * motion.tint)
          // Colour belongs to the visible trail: its tail stays the result colour
          // as the head returns towards the source rim, even behind the solid disk.
          let resultColor = flight.failed ? NotchTokens.redFail : NotchTokens.greenComplete
          let direction: CGFloat = flight.failed ? 1 : -1
          let returnInk = LinearGradient(stops: [
            .init(color: resultColor, location: 0),
            .init(color: resultColor, location: 0.52),
            .init(color: NotchTokens.deepSeekBlue, location: 1),
          ], startPoint: UnitPoint(x: 0.5, y: 0.5 + direction * 28 / 20),
             endPoint: UnitPoint(x: 0.5, y: 0.5 + direction * 9.5 / 20))
          let ink = motion.returning ? AnyShapeStyle(returnInk) : AnyShapeStyle(color)
          OrbitStroke(frame: motion, angle: flight.startedAt.timeIntervalSinceReferenceDate * 2 * .pi / 3)
            .stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 30, height: 20)
            .position(x: 15, y: originY)
            .allowsHitTesting(false)
            .zIndex(-1)
        }
      }
      .frame(width: 30, height: totalHeight)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: lampCount)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: showTop)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("运行中 \(model.busyCount)，完成 \(model.completedUnreadCount)，失败 \(model.failedRows.count)")
  }

  private func statusDisk(count: Int, color: Color, opacity: Double) -> some View {
    ZStack {
      Circle().fill(color)
      Text("\(count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(color == NotchTokens.greenComplete ? Color.black : Color.white)
    }
    .frame(width: 19, height: 19)
    .opacity(count > 0 ? opacity : 0)
  }
}
