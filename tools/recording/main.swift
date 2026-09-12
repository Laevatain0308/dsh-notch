import AppKit
import SwiftUI

struct RecordingTileView:View {
  let tile:DemoTile
  let solo:Bool
  @ObservedObject var board:BoardModel
  init(tile:DemoTile,solo:Bool) {self.tile=tile;self.solo=solo;board=tile.board}
  var body:some View {
    GeometryReader {geo in
      let scale:CGFloat=solo ? min(5.4,(geo.size.height-140)/110):min(2.65,(geo.size.height-104)/104)
      VStack(spacing:0) {
        VStack(spacing:5) {
          Text(tile.scene.title).font(.system(size:solo ? 40:24,weight:.semibold))
            .foregroundStyle(Color(white:0.14))
          Text(tile.scene.englishTitle).font(.system(size:solo ? 27:17,weight:.medium))
            .foregroundStyle(Color(white:0.34))
        }.lineLimit(1).minimumScaleFactor(0.7)
          .frame(height:solo ? 130:82)
        ZStack {
          RootView(model:board,panelSize:CGSize(width:340,height:260),restSize:CGSize(width:38,height:44))
            .frame(width:38,height:max(44,board.orbitLayout.height+24))
            .scaleEffect(scale).allowsHitTesting(false)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
      }.frame(width:geo.size.width,height:geo.size.height)
    }
  }
}

struct RecordingView:View {
  @ObservedObject var model:RecordingModel
  var body:some View {
    GeometryReader {geo in
      ZStack(alignment:.bottom) {
        Color(white:0.965)
        if model.solo {
          if let tile=model.tiles.first {
            RecordingTileView(tile:tile,solo:true).id(tile.id).padding(.horizontal,60).padding(.top,22).padding(.bottom,80)
          }
        } else {
          VStack(spacing:16) {
            ForEach(0..<2,id:\.self) {row in
              HStack(spacing:26) {
                ForEach(Array(model.tiles.dropFirst(row*3).prefix(3))) {tile in
                  RecordingTileView(tile:tile,solo:false).id(tile.id)
                }
              }
            }
          }.padding(.horizontal,38).padding(.top,16).padding(.bottom,68)
        }
        HStack(spacing:18) {
          Button {model.move(-1)} label:{Image(systemName:"chevron.left")}.keyboardShortcut(.leftArrow,modifiers:[]).help("上一组")
          Text("\(model.page+1) / \(model.count)").monospacedDigit().foregroundStyle(.secondary)
          Button {model.move(1)} label:{Image(systemName:"chevron.right")}.keyboardShortcut(.rightArrow,modifiers:[]).help("下一组")
          Divider().frame(height:18)
          Button {model.replay()} label:{Image(systemName:"arrow.counterclockwise")}.keyboardShortcut("r",modifiers:[]).help("重播")
          Toggle("全部连播",isOn:$model.autoplay).toggleStyle(.checkbox)
          Button {model.controls.toggle()} label:{Image(systemName:"eye.slash")}.keyboardShortcut("h",modifiers:[]).help("显示 / 隐藏控制栏")
          Button {model.toggleLayout()} label:{Image(systemName:model.solo ? "square.grid.3x2":"rectangle")}.keyboardShortcut("s",modifiers:[]).help("并排 / 单场景")
          Button {NSApp.keyWindow?.toggleFullScreen(nil)} label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.keyboardShortcut("f",modifiers:[.command,.control]).help("全屏")
        }.font(.system(size:14)).buttonStyle(.plain)
          .padding(.horizontal,22).padding(.vertical,14).background(.regularMaterial,in:Capsule())
          .padding(.bottom,15).opacity(model.controls ? 1:0).allowsHitTesting(model.controls)
          .animation(.easeOut(duration:0.15),value:model.controls)
      }.onContinuousHover {phase in
        switch phase {case .active(let p):model.controls=p.y > geo.size.height-70
        case .ended:model.controls=false}
      }
    }.frame(minWidth:900,minHeight:620)
  }
}

@MainActor final class RecordingDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
  let model=RecordingModel()
  var window:NSWindow?
  func applicationDidFinishLaunching(_ notification:Notification) {
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
    window.title="DSH Notch · Demo"
    window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true
    window.contentView=NSHostingView(rootView:RecordingView(model:model))
    window.backgroundColor=NSColor(white:0.965,alpha:1)
    window.isReleasedWhenClosed=false;window.delegate=self
    window.collectionBehavior=[.fullScreenPrimary]
    window.center();window.makeKeyAndOrderFront(nil);self.window=window
    NSApp.activate(ignoringOtherApps:true);model.replay()
  }
  func windowWillClose(_ notification:Notification) {model.stop();NSApp.terminate(nil)}
  func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
}

@main enum RecordingMain {
  @MainActor static func main() {
    let app=NSApplication.shared;app.setActivationPolicy(.regular)
    let menu=NSMenu(),item=NSMenuItem(),sub=NSMenu()
    sub.addItem(withTitle:"退出演示",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
    item.submenu=sub;menu.addItem(item);app.mainMenu=menu
    let delegate=RecordingDelegate();app.delegate=delegate
    withExtendedLifetime(delegate) {app.run()}
  }
}
