import AppKit
import SwiftUI
import Combine

@main enum ScrollbarProbe {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let model = BoardModel()
    model.previewMode = true
    model.maximumExpandedHeight = 800
    let panel = NotchPanel(size:NSSize(width:38,height:44))
    let host = NotchHostingView(rootView:RootView(model:model,panelSize:CGSize(width:480,height:800),restSize:CGSize(width:38,height:44)))
    host.sizingOptions = []
    panel.embedHost(host)
    panel.setFrame(NSRect(x:-2000,y:-2000,width:38,height:44),display:true)
    panel.orderFrontRegardless()
    var subscriptions = Set<AnyCancellable>()
    Publishers.CombineLatest(model.$currentIslandWidth,model.$currentIslandHeight)
      .receive(on:DispatchQueue.main).sink {w,h in panel.resizeAnchored(to:NSSize(width:w,height:h))}
      .store(in:&subscriptions)
    @MainActor func scrollViews(_ view:NSView)->[NSScrollView] {
      ((view as? NSScrollView).map {[$0]} ?? []) + view.subviews.flatMap(scrollViews)
    }
    Task { @MainActor in
      let rows=(0..<5).map {NotchRow(id:"fixture-\($0)",title:"Running task \($0+1)",child:false,busy:true,unread:false)}
      model.applySnapshot(NotchSnapshot(ok:true,generatedAt:0,origin:"offline",rows:rows))
      try? await Task.sleep(for:.milliseconds(800))
      var failures=0, samples=0, flashFrames=0
      @MainActor func check(_ condition:Bool,_ message:String) {
        if !condition {failures += 1;print("FAIL \(message)")}
      }
      @MainActor func inspectShortExpansion(_ scenario:String) async {
        model.expanded=true
        for frame in 0..<45 {
          try? await Task.sleep(for:.milliseconds(16))
          host.layoutSubtreeIfNeeded()
          let scrolls=scrollViews(host)
          for (i,scroll) in scrolls.enumerated() {
            guard let bar=scroll.verticalScroller else {continue}
            let visible=scroll.hasVerticalScroller && !bar.isHiddenOrHasHiddenAncestor && bar.alphaValue>0 && bar.bounds.height>0 && bar.knobProportion<0.999
            if visible {failures += 1;flashFrames += 1}
            if frame<4 || visible || frame==44 {
              print("SCENARIO=\(scenario) FRAME=\(frame) SCROLL=\(i) PANEL=\(Int(panel.frame.height)) DOCUMENT=\(Int(scroll.documentView?.frame.height ?? 0)) VIEWPORT=\(Int(scroll.contentView.bounds.height)) HAS_BAR=\(scroll.hasVerticalScroller) HIDDEN=\(bar.isHiddenOrHasHiddenAncestor) ALPHA=\(bar.alphaValue) KNOB=\(bar.knobProportion) VISIBLE=\(visible)")
            }
          }
          samples += scrolls.count
        }
      }
      await inspectShortExpansion("five-tasks")
      model.expanded=false
      try? await Task.sleep(for:.milliseconds(600))
      await inspectShortExpansion("reopen")
      model.expanded=false
      try? await Task.sleep(for:.milliseconds(70))
      await inspectShortExpansion("reverse-collapse")
      check(samples>0,"no native scroll views reached")

      // A real overflow must keep both its indicator and a movable viewport.
      model.maximumExpandedHeight=400
      let question=NotchQuestion(id:"long",question:"Long question",options:[NotchOption(label:"Option",description:String(repeating:"Long offline content. ",count:150))])
      let row=NotchRow(id:"question",title:"Local fixture",child:false,busy:true,unread:false,ask:NotchAsk(id:"ask",questions:[question]))
      model.applySnapshot(NotchSnapshot(ok:true,generatedAt:0,origin:"offline",rows:[row]))
      try? await Task.sleep(for:.milliseconds(850))
      host.layoutSubtreeIfNeeded()
      check(abs(panel.frame.height-400)<2,"long content reaches the screen cap")
      if let scroll=scrollViews(host).first,let document=scroll.documentView {
        let overflow=document.frame.height-scroll.contentView.bounds.height
        check(overflow>20,"long fixture actually overflows")
        check(scroll.hasVerticalScroller,"real overflow retains its indicator")
        let before=scroll.contentView.bounds.origin.y
        scroll.contentView.scroll(to:NSPoint(x:0,y:overflow))
        scroll.reflectScrolledClipView(scroll.contentView)
        check(scroll.contentView.bounds.origin.y>before+20,"long content remains scrollable")
        print("LONG_OVERFLOW=\(Int(overflow)) SCROLLED=\(Int(scroll.contentView.bounds.origin.y)) INDICATOR=\(scroll.hasVerticalScroller)")
      } else {check(false,"long fixture has a native scroll view")}
      model.maximumExpandedHeight=800
      model.applySnapshot(NotchSnapshot(ok:true,generatedAt:0,origin:"offline",rows:rows))
      try? await Task.sleep(for:.milliseconds(850))
      check(panel.frame.height<400,"short content shrinks after long content")
      model.expanded=false
      try? await Task.sleep(for:.milliseconds(600))
      await inspectShortExpansion("after-long-content")
      print("SCROLLBAR_FLASH_FRAMES=\(flashFrames)")
      print("FAILURES=\(failures)")
      exit(failures==0 ? 0:1)
    }
    app.run()
    withExtendedLifetime(subscriptions) {}
  }
}
