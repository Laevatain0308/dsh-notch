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
  for i in 0...100 {
    let departure=RobotDeparture(progress:Double(i)/100)
    if departure.statusOpacity > 0 { check(departure.scale <= 0.061,"status cannot appear before robot reaches tiny point") }
    if Double(i)/100*RobotDeparture.duration <= 0.666 { check(departure.statusScale <= 0.0001,"status remains a tiny point until colour handoff finishes") }
  }
  for i in 0...20 {
    let t=Double(i)/20,departure=RobotDeparture(progress:t)
    let model=BoardModel()
    model.rows=[NotchRow(id:"ask",title:"local",child:false,busy:false,unread:false,ask:NotchAsk(id:"ask",questions:[]))]
    model.orbitLayout=OrbitLayout(decision:1)
    let clip=IdleLibrary.shared.clip("satellite-out")!
    let target=IdleInterpolation.sample(clip,at:t*RobotDeparture.duration*clip.fps)
    let neutral=IdleLibrary.shared.clip("blink")!.frames[0]
    let frame=IdleInterpolation.mix(neutral,target,IdleInterpolation.smooth(t*RobotDeparture.duration/0.22))
    let view=ZStack {
      StatusOrbitView(model:model,workReveal:departure.statusScale).opacity(departure.statusOpacity)
      IdleRobotCanvas(clip:IdleClip(fps:1,duration:7,frames:[frame]),elapsed:0)
        .frame(width:30,height:42).scaleEffect(departure.scale).opacity(departure.opacity)
    }.frame(width:38,height:44).background(Color.black).scaleEffect(4).frame(width:180,height:200).background(Color.gray.opacity(0.2))
    let hosting=NSHostingView(rootView:view);hosting.frame=NSRect(x:0,y:0,width:180,height:200)
    let panel=NSPanel(contentRect:hosting.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=hosting
    hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
    let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds)!;hosting.cacheDisplay(in:hosting.bounds,to:rep)
    try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("tiny-handoff-\(i).png"));panel.close()
  }
  check(DecisionMorph(amount:0).trim==0.7 && DecisionMorph(amount:0).fill==0,"blue starts hollow with gap")
  check(DecisionMorph(amount:1).trim==0 && DecisionMorph(amount:1).fill==1,"yellow ends closed and solid")
  for text in ["!","1","3","8","12","99","100"] {
    let bounds=CenteredStatusGlyph.path(text).boundingRect
    check(abs(bounds.midX)<0.00001 && (text == "!" || abs(bounds.midY)<0.00001),"visible glyph ink centered: \(text)")
    check(bounds.width<=12.00001,"multi-digit glyph fits the shared clipping width")
  }
  let step=0.000001
  let penEndSpeed=(DecisionMorph(amount:0).trim-DecisionMorph(amount:step).trim)*2 * Double.pi/(step*DecisionMorph.resumeDuration)
  check(abs(penEndSpeed-DecisionSpin.runningVelocity)<0.0001,"resume pen ends at running angular velocity")
  let blueEndSpeed=(StatusBirth(progress:1).blueDraw-StatusBirth(progress:1-step).blueDraw)*2 * Double.pi*0.7/(step*(RobotDeparture.duration-0.666))
  check(abs(blueEndSpeed-StatusBirth.bluePenVelocity)<0.0001,"birth pen hands its exact velocity to rotation")
  for i in 25...99 {
    let a=StatusBirth(progress:Double(i)/100).blueDraw,b=StatusBirth(progress:Double(i+1)/100).blueDraw
    check(abs((b-a)-0.01/0.76)<0.00001,"blue appearance draws at constant speed")
  }
  let epoch=Date()
  let stop=DecisionSpin(began:epoch,angle:1.2,initialVelocity:DecisionSpin.runningVelocity,finalVelocity:0)
  let reversal=epoch.addingTimeInterval(0.24)
  let resume=DecisionSpin(began:reversal,angle:stop.position(at:reversal),initialVelocity:stop.velocity(at:reversal),finalVelocity:DecisionSpin.runningVelocity)
  check(abs(stop.position(at:reversal)-resume.position(at:reversal))<0.00001,"reverse preserves ring position")
  check(abs(stop.velocity(at:reversal)-resume.velocity(at:reversal))<0.00001,"reverse preserves ring velocity")
  for i in 1...100 {
    let a=epoch.addingTimeInterval(Double(i-1)/100),b=epoch.addingTimeInterval(Double(i)/100)
    check(stop.position(at:b)>=stop.position(at:a),"ring never reverses while stopping")
    check(resume.velocity(at:b)>=0,"ring resumes forward")
  }
  check(DecisionMorph(amount:0.64).flip < 0.00001,"number resolves before most of the brush is drawn")
  check(DecisionMorph(amount:0.99).fill == 1,"disk supports the early symbol flip")
  for i in 0...100 {
    let m=DecisionMorph(amount:Double(i)/100)
    check(m.draw == 0 || m.fill < 0.00001,"blue pen starts only after yellow fill clears")
    let birth=StatusBirth(progress:Double(i)/100)
    check(birth.draw == 0 || birth.travel > 0.99999,"pen reaches rim before drawing")
    check(birth.fill == 0 || birth.draw > 0.99999,"yellow ring closes before filling")
    check(birth.text == 0 || birth.draw > 0.99999,"text follows completed stroke")
  }
  for i in 0...12 {
    let t=Double(i)/12
    let view=WorkingDecisionGlyph(amount:t,number:3,angle:-Double.pi/2).scaleEffect(6).frame(width:160,height:160).background(Color.black)
    let hosting=NSHostingView(rootView:view);hosting.frame=NSRect(x:0,y:0,width:160,height:160)
    let panel=NSPanel(contentRect:hosting.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=hosting
    hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
    let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds)!;hosting.cacheDisplay(in:hosting.bounds,to:rep)
    try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("decision-flip-\(i).png"));panel.close()
  }
  for decision in [false,true] {
    for i in 0...12 {
      let view=StatusBirthGlyph(progress:Double(i)/12,decision:decision,number:3,angle:-Double.pi/2).scaleEffect(6).frame(width:160,height:160).background(Color.black)
      let hosting=NSHostingView(rootView:view);hosting.frame=NSRect(x:0,y:0,width:160,height:160)
      let panel=NSPanel(contentRect:hosting.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=hosting
      hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
      let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds)!;hosting.cacheDisplay(in:hosting.bounds,to:rep)
      try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("birth-\(decision ? "yellow":"blue")-\(i).png"));panel.close()
    }
  }
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
