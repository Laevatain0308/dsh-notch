import AppKit
import SwiftUI
@main enum MotionProbe {
 @MainActor static func main() {
  let app=NSApplication.shared
  app.setActivationPolicy(.accessory)
  let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_MOTION_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("notch-motion-proof")
  try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  var failures=0
  func check(_ value:Bool,_ label:String) { if !value { failures += 1; print("FAIL \(label)") } }
  func snapshot(_ busy:Int,_ done:Int,_ failed:Int) -> NotchSnapshot {
   let rows=(0..<busy).map { NotchRow(id:"busy-\($0)",title:"running",child:false,busy:true,unread:false) }
     + (0..<done).map { NotchRow(id:"done-\($0)",title:"done",child:false,busy:false,unread:true) }
     + (0..<failed).map { NotchRow(id:"failed-\($0)",title:"failed",child:false,busy:false,unread:true,lastTurn:NotchLastTurn(at:0,kind:"error",failed:true)) }
   return NotchSnapshot(ok:true,generatedAt:0,origin:"local-test",rows:rows)
  }
  for failed in [false,true] {
   for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 4) {
    let route = OrbitBrushRoute(failed: failed, angle: angle)
    check(route.points.allSatisfy { abs($0.x) + 0.75 <= 15 }, "brush stays inside shell")
    for returns in [false,true] {
     var previous = OrbitMotionFrame(progress:0,failed:failed,returns:returns,angle:angle)
     check(previous.tint==0 && previous.resultOpacity==0,"blue start")
     for i in 1...160 {
      let frame = OrbitMotionFrame(progress:Double(i)/160,failed:failed,returns:returns,angle:angle)
      check(frame.distance >= previous.distance,"brush head never reverses")
      check(abs(frame.distance-previous.distance)<5,"continuous brush travel")
      check(abs(frame.tint-previous.tint)<0.15,"continuous colour")
      let range = route.range(for:frame)
      check(range.lowerBound >= 0 && range.upperBound <= route.total + 0.01,"trail range")
      previous=frame
     }
     check(previous.resultOpacity==1,"solid result appears")
     check(returns ? previous.tint==0 : previous.tint==1,"final colour")
     check(returns ? previous.tailLength>35 : previous.tailLength<0.01,"returning arc or settled dot")
    }
   }
  }
  let model=BoardModel()
  var snap=snapshot(2,0,0);model.applySnapshot(snap)
  check(model.statusFlight==nil,"cold snapshot has no flight")
  snap.rows[0].busy=false;snap.rows[0].unread=true;model.applySnapshot(snap)
  model.playTransition(from: .running, to: .succeeded)
  check(model.statusFlight?.failed==false,"successful completion moves upward")
  let first=model.statusFlight!.id
  model.applySnapshot(snap);check(model.statusFlight?.id==first,"polling does not replay")
  snap.rows[1].busy=false;snap.rows[1].unread=true;snap.rows[1].lastTurn=NotchLastTurn(at:0,kind:"error",failed:true);model.applySnapshot(snap)
  model.playTransition(from: .running, to: .failed)
  check(model.statusFlight?.id==first,"second outcome does not interrupt flight")
  model.finishStatusFlight(id:first)
  check(model.statusFlight?.failed==true,"failure queued next")
  model.finishStatusFlight(id:first)
  check(model.statusFlight?.failed==true,"stale completion cannot clear new flight")
  model.finishStatusFlight(id:model.statusFlight!.id)
  check(model.statusFlight==nil && model.busyCount==0 && model.completedUnreadCount==1 && model.failedRows.count==1,"final counts")
  let panel=NotchPanel(size:NSSize(width:60,height:110))
  let host=NotchHostingView(rootView:StatusOrbitView(model:model, reduceMotionOverride:false).frame(width:60,height:110).background(Color.black))
  host.sizingOptions=[];panel.contentView=host
  panel.setFrame(NSRect(x:-2000,y:-2000,width:60,height:110),display:true)
  panel.orderFrontRegardless()
  Task { @MainActor in
   for failed in [false,true] {
    model.rows=snapshot(1,failed ? 0:1,failed ? 1:0).rows
    for (i,phase) in [0.0,0.12,0.24,0.38,0.50,0.62,0.76,0.90,0.99].enumerated() {
     model.statusFlight=StatusFlight(failed:failed,startedAt:Date().addingTimeInterval(-phase*StatusFlight.duration),busyBefore:2,destinationBefore:0)
     try? await Task.sleep(for:.milliseconds(16))
     host.layoutSubtreeIfNeeded()
     if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
      host.cacheDisplay(in:host.bounds,to:rep)
      try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(output.path)/\(failed ? "failure":"success")-\(i).png"))
     }
    }
   }
   for failed in [false,true] {
    model.statusFlight=nil
    var replay=snapshot(2,0,0)
    model.applySnapshot(replay)
    replay.rows[0].busy=false;replay.rows[0].unread=true
    if failed { replay.rows[0].lastTurn=NotchLastTurn(at:0,kind:"error",failed:true) }
    model.applySnapshot(replay)
    for i in 0..<100 {
     try? await Task.sleep(for:.milliseconds(16))
     host.layoutSubtreeIfNeeded()
     if let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
      host.cacheDisplay(in:host.bounds,to:rep)
      let path="\(output.path)/replay-\(failed ? "failure":"success")-\(String(format:"%03d",i)).png"
      try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
     }
    }
   }
   model.statusFlight=nil;model.updateOrbitLayout();model.tickOrbitLayout(at:Date().addingTimeInterval(2))
   host.rootView = StatusOrbitView(model:model, reduceMotionOverride:true).frame(width:60,height:110).background(Color.black)
   try? await Task.sleep(for:.milliseconds(60))
   @MainActor func pixels() -> Data {
    host.layoutSubtreeIfNeeded()
    let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
    host.cacheDisplay(in:host.bounds,to:rep)
    return rep.representation(using:.png,properties:[:])!
   }
   let firstPixels=pixels()
   try? await Task.sleep(for:.milliseconds(160))
   check(firstPixels==pixels(),"reduced motion stays still")
   try! firstPixels.write(to:URL(fileURLWithPath:"\(output.path)/reduced-motion.png"))
   print("FAILURES=\(failures)");exit(failures==0 ? 0:1)
  }
  app.run()
 }
}
