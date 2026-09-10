import AppKit
import SwiftUI
@main enum IdleProbe {
 @MainActor static func main() {
  let app=NSApplication.shared; app.setActivationPolicy(.accessory)
  let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["NOTCH_IDLE_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("notch-idle-proof")
  try! FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  var failures=0
  func check(_ ok:Bool,_ label:String){if !ok {failures += 1;print("FAIL \(label)")}}
  for id in IdleDirector.basics + ["dance"] {
   guard let clip=IdleLibrary.shared.clip(id) else {check(false,"resource \(id)");continue}
   check(clip.frames.count > 100,"frames \(id)")
   for frame in clip.frames {
    check(frame.points.count == 192,"path topology")
    check(frame.points.flatMap{$0}.allSatisfy{$0.isFinite},"finite geometry")
    check(frame.points.allSatisfy{abs($0[0])*40/280 < 15 && abs($0[1])*40/280 < 21},"fits native bounds \(id)")
   }
   // Every intermediate outline must preserve area: a shifted SVG start index
   // used to collapse the robot by joining unrelated boundary vertices.
   func area(_ p:[[Double]]) -> Double {
     abs(p.indices.reduce(0.0) { sum,i in
       let a=p[i], b=p[(i+1)%p.count]
       return sum + a[0]*b[1]-a[1]*b[0]
     })/2
   }
   for i in 1..<clip.frames.count {
     let a=clip.frames[i-1], b=clip.frames[i]
     let mid=IdleInterpolation.mix(a,b,0.5)
     check(area(mid.points) >= min(area(a.points),area(b.points))*0.98,"contour does not collapse \(id) frame \(i)")
   }
   // Interruption visuals from each action's non-neutral middle pose.
   for step in 0...15 {
    let visibility=step <= 10 ? 1-Double(step)/10 : 1
    let suspect=["tilt":33,"scan":37,"balance":129,"sneeze":88,"stretch":72,"nod":64,"dance":612][id] ?? 60
    let elapsed=step <= 10 ? 2.0 : (Double(suspect)+Double(step-13)*0.25)/clip.fps
    let rendered=IdleInterpolation.sample(clip,at:elapsed*clip.fps)
    let view=IdleRobotCanvas(clip:IdleClip(fps:1,duration:7,frames:[rendered]),elapsed:0,visibility:visibility,entering:false)
      .frame(width:30,height:42).scaleEffect(4).frame(width:180,height:190).background(Color.black)
    let hosting=NSHostingView(rootView:view);hosting.frame=NSRect(x:0,y:0,width:180,height:190)
    let panel=NSPanel(contentRect:hosting.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=hosting
    hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
    let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds)!;hosting.cacheDisplay(in:hosting.bounds,to:rep)
    try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(id)-\(step).png"));panel.close()
   }
  }
  let ids = IdleDirector.basics + ["dance"]
  for from in ids { for to in ids {
    let director = IdleDirector()
    let start = Date()
    director.play(from, at:start)
    let interrupt = start.addingTimeInterval(2.13)
    let before = director.frame(at:interrupt)!
    let previous=director.frame(at:interrupt.addingTimeInterval(-1.0/240))!
    director.play(to, at:interrupt)
    let after = director.frame(at:interrupt)!
    check(before.points == after.points && before.body == after.body, "switch continuity \(from) -> \(to)")
    check(zip(before.eyes,after.eyes).allSatisfy{$0.x == $1.x && $0.h == $1.h && $0.angle == $1.angle}, "eye continuity")
    let dt=0.0001
    let next=director.frame(at:interrupt.addingTimeInterval(dt))!
    let error=after.points.indices.map { i in
      hypot((next.points[i][0]-after.points[i][0])/dt-(before.points[i][0]-previous.points[i][0])*240,
            (next.points[i][1]-after.points[i][1])/dt-(before.points[i][1]-previous.points[i][1])*240)
    }.max()!
    check(error < 1,"switch carries velocity \(from) -> \(to)")
    director.stop()
  }}
  for entering in [false,true] {
    let id=entering ? "cube-in":"satellite-out"
    let clip=IdleLibrary.shared.clip(id)!
    let neutral=IdleLibrary.shared.clip("blink")!.frames[0]
    for i in 0...20 {
      let t=Double(i)/20
      let target=IdleInterpolation.sample(clip,at:t*clip.duration*clip.fps)
      let sample=entering ? target:IdleInterpolation.mix(neutral,target,IdleInterpolation.smooth(t*clip.duration/0.22))
      let visibility=entering ? IdleInterpolation.smooth(t/0.32):1-IdleInterpolation.smooth((t-0.65)/0.35)
      let view=IdleRobotCanvas(clip:IdleClip(fps:1,duration:7,frames:[sample]),elapsed:0,visibility:visibility,entering:entering)
        .frame(width:30,height:42).scaleEffect(4).frame(width:180,height:190).background(Color.black)
      let hosting=NSHostingView(rootView:view);hosting.frame=NSRect(x:0,y:0,width:180,height:190)
      let panel=NSPanel(contentRect:hosting.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=hosting
      hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
      let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds)!;hosting.cacheDisplay(in:hosting.bounds,to:rep)
      try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(id)-\(i).png"));panel.close()
    }
  }
  for i in 0...16 {
    let t=Double(i)/16,model=BoardModel()
    model.rows=[NotchRow(id:"done",title:"done",child:false,busy:false,unread:true),NotchRow(id:"failed",title:"failed",child:false,busy:false,unread:true,lastTurn:NotchLastTurn(at:0,kind:"error",failed:true))]
    let flight=StatusFlight(failed:false,startedAt:Date().addingTimeInterval(-t*StatusFlight.duration),busyBefore:1,destinationBefore:1,returnsToRunning:false)
    model.statusFlight=flight
    model.orbitLayout=OrbitLayout.flight(from:OrbitLayout(top:1,middle:1,bottom:1),to:OrbitLayout(top:1,middle:0,bottom:1),progress:t,flight:flight)
    let view=RootView(model:model,panelSize:CGSize(width:320,height:460),restSize:CGSize(width:38,height:44))
      .frame(width:38,height:model.orbitLayout.height+24).scaleEffect(3,anchor:.top)
      .frame(width:160,height:340,alignment:.top).background(Color.gray.opacity(0.3))
    let hosting=NSHostingView(rootView:view);hosting.frame=NSRect(x:0,y:0,width:160,height:340)
    let panel=NSPanel(contentRect:hosting.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=hosting
    hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
    let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds)!;hosting.cacheDisplay(in:hosting.bounds,to:rep)
    try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("layout-\(i).png"));panel.close()
  }
  for i in 0...100 {
    let t=Double(i)/100
    let q=OrbitLayout.mix(OrbitLayout(middle:1),OrbitLayout(decision:1),IdleInterpolation.smooth(t))
    check(abs(q.height-20)<0.00001,"single doing-to-decision keeps shell height")
    check(abs(q.middleY-10)<0.00001,"single doing-to-decision stays at same center")
  }
  let cube=IdleLibrary.shared.clip("cube-in")!
  check(cube.frames.allSatisfy{$0.points.count==192 && $0.eyes.count==2},"cube keeps contour and eye slots across back-facing poses")
  var closures=0
  for i in 1..<3000 {
    if IdleDirector.blinkClosure(at:Double(i)/100)>0.9 && IdleDirector.blinkClosure(at:Double(i-1)/100)<=0.9 { closures+=1 }
  }
  check(closures >= 5 && closures <= 9,"natural blinks recur independently of gestures")
  for failed in [false,true] {
    let flight=StatusFlight(failed:failed,startedAt:Date(),busyBefore:1,destinationBefore:1,returnsToRunning:false)
    let initial=OrbitLayout(top:1,middle:1,bottom:1),final=OrbitLayout(top:1,middle:0,bottom:1)
    var previous=initial
    for i in 0...160 {
      let layout=OrbitLayout.flight(from:initial,to:final,progress:Double(i)/160,flight:flight)
      check(abs((layout.bottomY-previous.bottomY)-(layout.height-previous.height)) < 0.00001,"red disk and shell share displacement")
      check(abs(layout.bottomY-previous.bottomY)<2,"no last-task layout snap")
      previous=layout
    }
    check(previous==final,"last task settles into exact two-light layout")
  }
  let director=IdleDirector(),presence=IdlePresence()
  presence.set(true,director:director,animated:false)
  director.play("hop")
  presence.set(false,director:director)
  check(director.action == nil,"work cancels idle immediately")
  let frozen=presence.frozenID
  RunLoop.current.run(until:Date().addingTimeInterval(0.1))
  let before=presence.visibility
  presence.set(true,director:director)
  check(presence.visibility==before && presence.frozenID==frozen,"reverse retains geometry")
  RunLoop.current.run(until:Date().addingTimeInterval(1.2))
  check(presence.visibility == 1,"reverse finishes idle")
  presence.stop();director.stop()
  print("FAILURES=\(failures)");exit(failures==0 ? 0:1)
 }
}
