struct AuditSurface:View {
 @ObservedObject var loop:LoopModel
 var body:some View {
  LoopRobot(board:loop.board,enlarged:true).frame(width:200,height:390,alignment:.top).background(Color(white:0.15))
 }
}
@main enum AuditMain {
 @MainActor static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  let loop=LoopModel();loop.auto=false
  let host=NSHostingView(rootView:AuditSurface(loop:loop));host.frame=NSRect(x:0,y:0,width:200,height:390)
  let panel=NSPanel(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false);panel.contentView=host
  panel.setFrameOrigin(NSPoint(x:-3000,y:-3000));panel.orderFrontRegardless()
  let base=URL(fileURLWithPath:ProcessInfo.processInfo.environment["NOTCH_AUDIT_OUTPUT"]!)
  Task { @MainActor in
   for item in ReviewCase.allCases where (ProcessInfo.processInfo.environment["NOTCH_AUDIT_CASES"].map { $0.split(separator:",").contains(Substring(String(item.rawValue+1))) } ?? true) {
    let out=base.appendingPathComponent(String(format:"%02d",item.rawValue+1));try! FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
    loop.run(item)
    for i in 0..<180 {
     try? await Task.sleep(for:.milliseconds(50))
     host.layoutSubtreeIfNeeded();host.displayIfNeeded()
     let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:rep)
     try! rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(String(format:"%03d.png",i)))
    }
    print("CAPTURED \(item.title) 180 frames")
   }
   loop.stop();print("ALL_13_CAPTURED");exit(0)
  }
  app.run()
 }
}
