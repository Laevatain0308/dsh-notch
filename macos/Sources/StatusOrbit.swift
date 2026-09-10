import SwiftUI

struct OrbitLayout: Equatable {
  var top: Double = 0
  var middle: Double = 0
  var bottom: Double = 0
  var decision: Double = 0
  var total: Double { top+middle+bottom+decision }
  var height: CGFloat { 20+28*max(0,total-1) }
  var middleY: CGFloat { 10+28*(top+max(0,decision+middle-1)) }
  var bottomY: CGFloat { 10+28*(top+middle+decision) }
  static func mix(_ a:Self,_ b:Self,_ t:Double)->Self {
    Self(top:a.top+(b.top-a.top)*t,middle:a.middle+(b.middle-a.middle)*t,bottom:a.bottom+(b.bottom-a.bottom)*t,decision:a.decision+(b.decision-a.decision)*t)
  }
  static func flight(from a:Self,to b:Self,progress:Double,flight:StatusFlight)->Self {
    let growth=OrbitMotionFrame.ease(progress/0.48)
    var result=mix(a,b,growth)
    if !flight.returnsToRunning {
      let source=OrbitMotionFrame(progress:progress,failed:flight.failed,returns:false,angle:flight.angle).sourceOpacity
      // Existing result: close the vacated slot as ink leaves it. A new result
      // first needs room for its drawn circle, then releases the source slot.
      let remaining=flight.destinationBefore > 0 ? source:1-OrbitMotionFrame.ease((progress-0.72)/0.28)
      result.middle=max(a.middle,1)*remaining
    }
    return result
  }
}

struct StatusFlight: Identifiable {
  let id = UUID()
  let failed: Bool
  let startedAt: Date
  let busyBefore: Int
  let destinationBefore: Int
  let returnsToRunning: Bool
  let angle: Double
  init(failed: Bool, startedAt: Date, busyBefore: Int, destinationBefore: Int, returnsToRunning: Bool = true, angle:Double? = nil) {
    self.failed = failed
    self.startedAt = startedAt
    self.busyBefore = busyBefore
    self.destinationBefore = destinationBefore
    self.returnsToRunning = returnsToRunning
    self.angle=angle ?? startedAt.timeIntervalSinceReferenceDate*2 * .pi/3
  }
  static let duration: TimeInterval = 0.95
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
  private static func pacedHead(_ t:Double,_ values:[CGFloat])->CGFloat {
    let times=[0.0,0.18,0.56,0.94,1.0]
    func slope(_ i:Int)->CGFloat {
      guard i > 0 && i < 4 else { return 0 }
      let a=(values[i]-values[i-1])/(times[i]-times[i-1])
      let b=(values[i+1]-values[i])/(times[i+1]-times[i])
      return a*b > 0 ? 2*a*b/(a+b):0
    }
    let i=(0..<4).first { t <= times[$0+1] } ?? 3
    let dt=times[i+1]-times[i],u=min(1,max(0,(t-times[i])/dt)),u2=u*u,u3=u2*u
    return (2*u3-3*u2+1)*values[i]+(u3-2*u2+u)*dt*slope(i)+(-2*u3+3*u2)*values[i+1]+(u3-u2)*dt*slope(i+1)
  }
  init(progress: Double, failed: Bool, returns: Bool, angle: Double = 0) {
    self.progress = min(1, max(0, progress))
    self.failed = failed
    self.returns = returns
    let route = OrbitBrushRoute(failed: failed, angle: angle)
    let end = returns ? route.total : route.resultDrawn + 18
    let head = returns ? route.departure + (end - route.departure) * Self.ease(self.progress) : Self.pacedHead(self.progress,[route.departure,route.sourceExit,route.arrival,route.resultDrawn,route.resultDrawn+18])
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

  init(failed: Bool, angle: Double, gap: CGFloat = 28) {
    let r: CGFloat = 9.5
    let direction: CGFloat = failed ? 1 : -1
    let y = direction * gap
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
  var gap: CGFloat = 28
  func path(in rect: CGRect) -> Path {
    let route = OrbitBrushRoute(failed: frame.failed, angle: angle, gap:gap)
    let canonical=OrbitBrushRoute(failed:frame.failed,angle:angle)
    let source=[CGFloat(0),canonical.departure,canonical.sourceExit,canonical.arrival,canonical.resultDrawn,canonical.returned,canonical.total]
    let dest=[CGFloat(0),route.departure,route.sourceExit,route.arrival,route.resultDrawn,route.returned,route.total]
    func map(_ d:CGFloat)->CGFloat {
      for i in 1..<source.count where d <= source[i] {
        let w=(d-source[i-1])/max(0.00001,source[i]-source[i-1])
        return dest[i-1]+w*(dest[i]-dest[i-1])
      }
      return route.total
    }
    let range=canonical.range(for:frame)
    return route.path(in: map(range.lowerBound)...map(range.upperBound)).offsetBy(dx: rect.midX, dy: rect.midY)
  }
}

struct DecisionSpin {
  let began:Date
  let angle:Double
  let initialVelocity:Double
  let finalVelocity:Double
  static let duration=0.62
  static let runningVelocity=2 * Double.pi/3
  func velocity(at now:Date)->Double {
    let u=min(1,max(0,now.timeIntervalSince(began)/Self.duration))
    return initialVelocity+(finalVelocity-initialVelocity)*(3*u*u-2*u*u*u)
  }
  func position(at now:Date)->Double {
    let elapsed=max(0,now.timeIntervalSince(began)),t=min(elapsed,Self.duration),u=t/Self.duration
    return angle+initialVelocity*t+(finalVelocity-initialVelocity)*Self.duration*(u*u*u-0.5*u*u*u*u)+finalVelocity*max(0,elapsed-Self.duration)
  }
}
struct DecisionMorph {
  let amount:Double
  private var q:Double { min(1,max(0,amount)) }
  // Shared reversible path: the symbol resolves before the brush leaves the disk.
  var draw:Double { IdleInterpolation.smooth(((1-q)-0.28)/0.72) }
  var tint:Double { 1-draw }
  var trim:Double { 0.70*draw }
  var fill:Double { 1-draw }
  var flip:Double { 1-IdleInterpolation.smooth((1-q)/0.36) }
}

/// Two halves hinge at the glyph's equator, like a split-flap calendar.
struct DecisionFlipGlyph:View {
  let number:Int
  let progress:Double
  let color:Color
  var body:some View {
    Canvas { context,size in
      func half(_ text:String,top:Bool,scale:Double,exposed:Double? = nil) {
        guard scale > 0.001 else { return }
        var c=context
        c.translateBy(x:size.width/2,y:size.height/2)
        if let exposed {
          let y=top ? -size.height/2:exposed
          let height=top ? size.height/2-exposed:size.height/2-exposed
          c.clip(to:Path(CGRect(x:-size.width/2,y:y,width:size.width,height:max(0,height))))
        }
        c.scaleBy(x:1,y:scale)
        c.clip(to:Path(CGRect(x:-size.width/2,y:top ? -size.height/2:0,width:size.width,height:size.height/2)))
        c.draw(Text(text).font(.system(size:10,weight:.bold,design:.rounded)).foregroundStyle(color),at:.zero,anchor:.center)
      }
      if progress < 0.5 {
        let scale=max(0,cos(.pi*progress))
        half("!",top:true,scale:1,exposed:size.height/2*scale)
        half("\(number)",top:false,scale:1)
        half("\(number)",top:true,scale:scale)
      } else {
        let scale=max(0,cos(.pi*(1-progress)))
        half("!",top:true,scale:1)
        half("\(number)",top:false,scale:1,exposed:size.height/2*scale)
        half("!",top:false,scale:scale)
      }
    }.frame(width:12,height:14)
  }
}

struct WorkingDecisionGlyph:View {
  let amount:Double
  let number:Int
  let angle:Double
  var body:some View {
    let m=DecisionMorph(amount:amount)
    let blue=Color(red:0.302,green:0.420,blue:0.996)
    let yellow=Color(red:0.949,green:1,blue:0.078)
    let glyphInk=Color(red:0.302*m.draw,green:0.420*m.draw,blue:0.996*m.draw)
    ZStack {
      // Keep the disk's silhouette stable; transfer its weight to a growing stroke.
      Circle().fill(yellow).opacity(m.fill)
      Circle().stroke(yellow,lineWidth:1.5).opacity(m.fill)
      Circle().trim(from:0,to:m.trim).stroke(blue,style:StrokeStyle(lineWidth:1.5,lineCap:.round))
        .opacity(min(1,m.draw/0.08)).rotationEffect(.radians(angle))
      DecisionFlipGlyph(number:number,progress:m.flip,color:glyphInk)
    }.frame(width:19,height:19)
  }
}

struct StatusOrbitView: View {
  @ObservedObject var model: BoardModel
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  var reduceMotionOverride: Bool? = nil
  var workReveal:Double = 1
  private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

  private var layout: OrbitLayout { model.orbitLayout }
  private var showTop: Bool { layout.top > 0.0001 }
  private var showBottom: Bool { layout.bottom > 0.0001 }
  private var showMiddle: Bool { layout.middle > 0.0001 }
  private var totalHeight: CGFloat { layout.height }
  private var originY: CGFloat { layout.middleY }
  private var bottomY: CGFloat { layout.bottomY }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || (model.busyCount == 0 && model.statusFlight == nil && !model.decisionSpinActive))) { context in
      let flight = reduceMotion ? nil : model.statusFlight
      let progress = flight.map { context.date.timeIntervalSince($0.startedAt) / StatusFlight.duration } ?? 1
      let motion = flight.map { OrbitMotionFrame(progress: progress, failed: $0.failed, returns: $0.returnsToRunning, angle: $0.angle) }
      let angle = model.decisionAngle(at:context.date)
      let morphing = flight == nil && layout.top < 0.0001 && layout.bottom < 0.0001 && abs(layout.middle+layout.decision-1) < 0.001
      ZStack(alignment: .topLeading) {
        if morphing {
          WorkingDecisionGlyph(amount:layout.decision,number:max(1,max(model.busyCount,model.retainedBusyCount)),angle:reduceMotion ? 0:model.decisionAngle(at:context.date))
            .scaleEffect(workReveal).position(x:15,y:10)
        }
        if layout.decision > 0.0001 && !morphing {
          ZStack {
            Circle().fill(NotchTokens.amber)
            Text("!").font(.system(size:11,weight:.bold,design:.rounded)).foregroundStyle(.black)
          }.frame(width:19,height:19)
            .scaleEffect((0.8+0.2*layout.decision)*workReveal).opacity(layout.decision)
            .position(x:15,y:10)
        }
        if showTop {
          let count = flight?.failed == false && motion?.arrived == false ? flight!.destinationBefore : max(model.completedUnreadCount,model.retainedSuccessCount)
          statusDisk(count: count, color: NotchTokens.greenComplete, opacity: flight?.failed == false && flight?.destinationBefore == 0 ? (motion?.resultOpacity ?? 1) : 1)
            .position(x: 15, y: 10+28*layout.decision)
            .opacity(layout.top)
        }
        if showMiddle && !morphing {
          let count = flight != nil && motion?.returned == false ? flight!.busyBefore : model.busyCount
          ZStack {
            Circle().fill(Color.black).frame(width: 15, height: 15)
            if flight == nil && model.busyCount > 0 {
              Circle().trim(from: 0, to: 0.70)
                .stroke(NotchTokens.deepSeekBlue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.radians(reduceMotion ? 0 : angle))
            }
            Text("\(count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(NotchTokens.deepSeekBlue)
              .opacity(count > 0 ? (flight?.returnsToRunning == false ? layout.middle : (motion?.sourceOpacity ?? 1)) : 0)
          }
          .frame(width: 19, height: 19)
          .scaleEffect(workReveal).opacity(layout.middle)
          .position(x: 15, y: originY)
        }
        if showBottom {
          let count = flight?.failed == true && motion?.arrived == false ? flight!.destinationBefore : max(model.failedRows.count,model.retainedFailureCount)
          statusDisk(count: count, color: NotchTokens.redFail, opacity: flight?.failed == true && flight?.destinationBefore == 0 ? (motion?.resultOpacity ?? 1) : 1)
            .position(x: 15, y: bottomY)
            .opacity(layout.bottom)
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
          OrbitStroke(frame: motion, angle: flight.angle, gap:28*(flight.failed ? layout.middle : layout.top))
            .stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 30, height: 20)
            .position(x: 15, y: originY)
            .allowsHitTesting(false)
            .zIndex(-1)
        }
      }
      .frame(width: 30, height: totalHeight)
    }

    .accessibilityElement(children: .ignore)
    .accessibilityLabel("运行中 \(model.busyCount)，完成 \(model.completedUnreadCount)，失败 \(model.failedRows.count)，等待决定 \(model.needsAction ? 1:0)")
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
