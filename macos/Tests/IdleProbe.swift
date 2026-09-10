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
    check(frame.points.count == 64,"path topology")
    check(frame.points.flatMap{$0}.allSatisfy{$0.isFinite},"finite geometry")
    check(frame.points.allSatisfy{abs($0[0])*40/280 < 15 && abs($0[1])*40/280 < 21},"fits native bounds \(id)")
   }
   // Interruption visuals from each action's non-neutral middle pose.
   for step in 0...10 {
    let visibility=1-Double(step)/10
    let view=IdleRobotCanvas(clip:clip,elapsed:2.0,visibility:visibility,entering:false)
      .frame(width:30,height:42).scaleEffect(4).frame(width:180,height:190).background(Color.black)
    let hosting=NSHostingView(rootView:view);hosting.frame=NSRect(x:0,y:0,width:180,height:190)
    let panel=NSPanel(contentRect:hosting.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=hosting
    hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
    let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds)!;hosting.cacheDisplay(in:hosting.bounds,to:rep)
    try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(id)-\(step).png"));panel.close()
   }
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
  RunLoop.current.run(until:Date().addingTimeInterval(0.5))
  check(presence.visibility == 1,"reverse finishes idle")
  presence.stop();director.stop()
  print("FAILURES=\(failures)");exit(failures==0 ? 0:1)
 }
}
