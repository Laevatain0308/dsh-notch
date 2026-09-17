import AppKit
import SwiftUI
import Combine
@main enum GeometryProbe {
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let model = BoardModel()
  model.maximumExpandedHeight = 460
  let panel = NotchPanel(size: NSSize(width: 32,height:90))
  let host = NotchHostingView(rootView: RootView(model:model,service:NotchService(),consent:ConsentInbox(),onConsentAllow:{},onConsentDeny:{},onConsentDismiss:{},onAnswer:{_,_ in},onAction:{_,_,_ in},onDismiss:{},panelSize:CGSize(width:320,height:460),restSize:CGSize(width:32,height:110)))
  host.sizingOptions = []
  panel.embedHost(host)
  panel.setFrame(NSRect(x:400,y:400,width:32,height:90),display:true)
  panel.orderFrontRegardless()
  var subscriptions = Set<AnyCancellable>()
  Publishers.CombineLatest(model.$currentIslandWidth,model.$currentIslandHeight).receive(on:DispatchQueue.main).sink { w,h in
   panel.resizeAnchored(to: NSSize(width:w,height:h))
  }.store(in:&subscriptions)
  var failures=0
  /// Renders the host and measures the black shell inside it.
  ///
  /// The window is a transparent container that stays larger than the island
  /// while the island animates, and the island is anchored to its top-right and
  /// grows down and left. So the shell is located from the trailing edge rather
  /// than assumed to fill the host: the container's size and the island's
  /// current size differ for the whole length of an animation.
  func sample(_ tag:String, settled:Bool = false) {
   host.layoutSubtreeIfNeeded()
   guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { return }
   host.cacheDisplay(in:host.bounds,to:rep)
   let scale = CGFloat(rep.pixelsWide) / max(1, host.bounds.width)
   func isBlack(_ x:Int,_ y:Int) -> Bool {
    guard x>=0, y>=0, x<rep.pixelsWide, y<rep.pixelsHigh else { return false }
    guard let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { return false }
    return c.alphaComponent>0.9 && c.redComponent<0.05 && c.greenComponent<0.05 && c.blueComponent<0.05
   }
   // Vertical extent down the trailing edge, which the shell always reaches.
   let edgeX = max(0, rep.pixelsWide - 2)
   var top = -1, bottom = -1
   for y in 0..<rep.pixelsHigh where isBlack(edgeX,y) {
    if top < 0 { top = y }
    bottom = y
   }
   if abs(panel.frame.maxX - 432) > 0.01 { failures += 1 }
   guard top >= 0 else { failures += 1; print("\(tag) NO_SHELL"); return }
   let midY=(top+bottom)/2
   var blacks=[Int]()
   for x in 0..<rep.pixelsWide where isBlack(x,midY) { blacks.append(x) }
   let gap=rep.pixelsWide-1-(blacks.last ?? -1)
   if gap>1 { failures += 1 }
   // The leading edge must be rounded: a few points below the top it has to sit
   // further right than it does at the island's middle. Below twice the corner
   // radius the radius is clamped and the shell is a capsule by design, so there
   // is no straight middle to compare against.
   let cornerY=min(bottom, top + max(1, Int((3*scale).rounded())))
   var cornerLeft = -1
   for x in 0..<rep.pixelsWide where isBlack(x,cornerY) { cornerLeft = x; break }
   // Only on a settled island: while the content branches swap, one frame can
   // render before the shell has taken its shape, and the requirement being
   // checked is what the user ends up looking at.
   if settled, bottom - top >= Int(32 * scale), cornerLeft >= 0, cornerLeft <= (blacks.first ?? 0) {
    failures += 1; print("\(tag) LEFT_CORNER_CLIPPED cornerLeft=\(cornerLeft) midLeft=\(blacks.first ?? -1) cornerY=\(cornerY) span=\(top)...\(bottom)")
   }
   print("\(tag) width=\(rep.pixelsWide) island=\(Int(panel.islandSize.width))x\(Int(panel.islandSize.height)) shell=\(top)...\(bottom) black=\(blacks.first ?? -1)...\(blacks.last ?? -1) rightGap=\(gap)")
  }
  Task { @MainActor in
   try? await Task.sleep(for:.milliseconds(300));sample("rest", settled:true)
   for hover in [true,false,true,false] {
    model.isPillHovered=hover
    model.currentIslandWidth=hover ? 42:38
    model.currentIslandHeight=hover ? 66:68
    for i in 0..<10 {try? await Task.sleep(for:.milliseconds(20));sample("hover-\(hover)-\(i)")}
   }
   for hover in [true,false,true,false,true,false] {
    model.isPillHovered=hover
    try? await Task.sleep(for:.milliseconds(35));sample("rapid-hover")
   }
   for expanded in [true,false,true,false] {
    model.expanded=expanded
    for i in 0..<15 {try? await Task.sleep(for:.milliseconds(20));sample("expanded-\(expanded)-\(i)")}
   }
   for available in [100.0, 768.0, 1080.0, 1600.0] {
    let layout = NotchScreenLayout(availableHeight: available)
    if abs(layout.maximumHeight + 2 * layout.edgeInset - available) > 0.01 { failures += 1 }
    if layout.maximumHeight <= 0 { failures += 1 }
   }
   @MainActor func setQuestion(description: String) {
    let row: [String: Any] = ["id":"height-test", "title":"height test", "child":false, "busy":false, "unread":false, "ask":["id":"height-ask", "questions":[["id":"height-q", "question":"Height regression", "options":[["label":"Test option", "description":description]]]]]]
    model.rows = [try! JSONDecoder().decode(NotchRow.self, from: JSONSerialization.data(withJSONObject:row))]
   }
   model.maximumExpandedHeight = 900
   setQuestion(description: String(repeating: "Long content for measuring the expanded panel. ", count:100))
   model.expanded = true
   try? await Task.sleep(for:.milliseconds(500))
   sample("long-content-900", settled:true)
   // Assert the island, which is what the user sees. The window is a
   // transparent container that shrinks on a delay after the island settles, so
   // it is the wrong thing to time against; its settling is covered by the lamp
   // sequence below.
   if abs(panel.islandSize.height - 900) > 1 { failures += 1; print("LONG_HEIGHT=\(panel.islandSize.height) EXPECTED=900") }
   model.maximumExpandedHeight = 560
   try? await Task.sleep(for:.milliseconds(500))
   sample("screen-resized-560", settled:true)
   if abs(panel.islandSize.height - 560) > 1 { failures += 1; print("SCREEN_HEIGHT=\(panel.islandSize.height) EXPECTED=560") }
   model.maximumExpandedHeight = 900
   setQuestion(description:"Short content.")
   try? await Task.sleep(for:.milliseconds(500))
   sample("short-content", settled:true)
   if panel.islandSize.height >= 460 { failures += 1; print("SHORT_HEIGHT=\(panel.islandSize.height) EXPECTED<460") }
   model.expanded=false
   model.isPillHovered=false
   for (busy,done,failed,expected) in [(1,0,0,44.0),(1,1,0,72.0),(1,0,1,72.0),(1,1,1,100.0),(0,1,0,44.0)] {
    var rows: [[String:Any]] = []
    if busy>0 { rows.append(["id":"busy", "title":"Busy", "child":false,"busy":true,"unread":false]) }
    if done>0 { rows.append(["id":"done", "title":"Done", "child":false,"busy":false,"unread":true]) }
    if failed>0 { rows.append(["id":"failed", "title":"Failed", "child":false,"busy":false,"unread":true,"lastTurn":["at":0,"kind":"error","failed":true]]) }
    // Exercise the production snapshot entry point so lamp layout advances too.
    model.applySnapshot(NotchSnapshot(ok:true,generatedAt:0,origin:"offline",rows:try! JSONDecoder().decode([NotchRow].self,from:JSONSerialization.data(withJSONObject:rows))))
    try? await Task.sleep(for:.milliseconds(1500))
    sample("lamps-\(busy)-\(done)-\(failed)", settled:true)
    print("LAMP_HEIGHT=\(panel.frame.height) EXPECTED=\(expected)")
    if abs(panel.frame.height-expected)>1 { failures += 1 }
   }
   print("HEIGHT=\(panel.frame.height)")
   print("FAILURES=\(failures)")
   exit(failures == 0 ? 0 : 1)
  }
  app.run()
  withExtendedLifetime(subscriptions) {}
  exit(failures == 0 ? 0 : 1)
 }
}
