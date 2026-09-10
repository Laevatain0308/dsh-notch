import AppKit
import SwiftUI

enum ReviewCase:Int,CaseIterable,Identifiable {
  case idleWork,success,failure,lastSuccess,lastFailure,greenIdle,redIdle,idleDecision,workDecision,decisionWork,decisionIdle,mixed,approval,idleTour
  var id:Int { rawValue }
  var title:String {
    ["01 机器人 → 运行","02 运行 → 成功（还有任务）","03 运行 → 失败（还有任务）","04 三灯 → 最后任务成功","05 三灯 → 最后任务失败","06 读掉最后绿点 → 机器人","07 读掉最后红点 → 机器人","08 机器人 → 黄色决策","09 运行 → 黄色决策","10 黄色决策 → 继续运行","11 黄色决策 → 待机","12 黄、蓝、绿、红混合 → 逐个清除","13 工具审批 → 继续运行","14 全部待机动作与变色龙"][rawValue]
  }
}
@MainActor final class LoopModel:ObservableObject {
  @Published var board=BoardModel()
  @Published var label="准备开始"
  @Published var round=0
  @Published var enlarged=true
  @Published var selectedCase=ReviewCase.idleWork
  @Published var auto=true
  private var job:Task<Void,Never>?
  private func rows(_ busy:Int=0,_ done:Int=0,_ failed:Int=0,_ decision:Bool=false,_ approval:Bool=false)->[NotchRow] {
    var rows=(0..<busy).map{NotchRow(id:"work-\($0)",title:"本地模拟任务",child:false,busy:true,unread:false)}
    rows += (0..<done).map{NotchRow(id:"done-\($0)",title:"本地模拟完成",child:false,busy:false,unread:true)}
    rows += (0..<failed).map{NotchRow(id:"error-\($0)",title:"本地模拟失败",child:false,busy:false,unread:true,lastTurn:NotchLastTurn(at:0,kind:"error",failed:true))}
    if decision || approval {
      var question=NotchRow(id:"decision",title:"本地模拟决策",child:false,busy:false,unread:false)
      if approval {question.approval=NotchApproval(id:"local-approval",toolName:"本地演示",reason:"不会执行任何真实操作")}
      else {question.ask=NotchAsk(id:"local-question",questions:[NotchQuestion(id:"choice",question:"选择演示配色",options:[NotchOption(label:"深色"),NotchOption(label:"浅色")])])}
      rows.append(question)
    }
    return rows
  }
  private func show(_ rows:[NotchRow],_ title:String) {
    label=title;board.applySnapshot(NotchSnapshot(ok:true,generatedAt:0,origin:"local-review",rows:rows));board.expanded=false
  }
  private func wait(_ seconds:Double)async->Bool {
    do{try await Task.sleep(for:.seconds(seconds));return !Task.isCancelled}catch{return false}
  }
  func start(){run(selectedCase)}
  func run(_ item:ReviewCase){
    job?.cancel();selectedCase=item
    job=Task { @MainActor in
      var current=item
      repeat {
        selectedCase=current;round+=1;board=BoardModel()
        var initial:[NotchRow]=[]
        switch current {
        case .idleWork,.idleDecision,.idleTour:initial=[]
        case .success,.failure:initial=rows(2)
        case .lastSuccess,.lastFailure:initial=rows(1,1,1)
        case .greenIdle:initial=rows(0,1,1)
        case .redIdle:initial=rows(0,1,1)
        case .workDecision:initial=rows(1)
        case .decisionWork,.decisionIdle:initial=rows(0,0,0,true)
        case .mixed:initial=rows(1,1,1,true)
        case .approval:initial=rows(0,0,0,false,true)
        }
        show(initial,"起始状态")
        guard await wait(1.3) else{return}
        switch current {
        case .idleTour:
          let names=["blink":"眨眼回神","scan":"左右巡视","tilt":"歪头琢磨","nod":"点头招呼","stretch":"伸个懒腰","hop":"果冻小跳","balance":"摇摇平衡","sneeze":"憋个喷嚏","sleep":"打盹 · 闭眼约 4 秒","dance":"变色龙彩蛋"]
          for id in ["dance"]+IdleDirector.basics {
            guard let director=IdleDirector.previewInstance else {return}
            director.automaticActions=false;director.play(id)
            label=names[id] ?? id
            let duration=IdleLibrary.shared.clip(id)?.duration ?? 7
            guard await wait(duration) else{return}
            director.tick(Date());label="普通待机 · 自然眨眼 · 4 秒"
            guard await wait(4) else{return}
          }
        case .idleWork:
          IdleDirector.previewInstance?.play("balance")
          guard await wait(1.7) else{return}
          show(rows(1),"后仰缩小 → 蓝圈和数字")
        case .success,.failure,.lastSuccess,.lastFailure:
          var next=initial
          next[0].busy=false;next[0].unread=true
          if current == .failure || current == .lastFailure {next[0].lastTurn=NotchLastTurn(at:0,kind:"error",failed:true)}
          show(next,"笔划送出结果 · 外壳同步")
        case .greenIdle:
          show(rows(0,1),"先读掉红点 · 只剩绿点")
          guard await wait(1.6) else{return}
          show([],"读掉最后绿点 → cube 旋转出场")
        case .redIdle:
          show(rows(0,0,1),"先读掉绿点 · 只剩红点")
          guard await wait(1.6) else{return}
          show([],"读掉最后红点 → cube 旋转出场")
        case .idleDecision,.workDecision:show(rows(0,0,0,true),"需要用户决定 → 黄色 !")
        case .decisionWork,.approval:show(rows(1),"已作决定 → 蓝色运行")
        case .decisionIdle:show([],"取消决策 → 待机")
        case .mixed:
          show(rows(1,1,1),"决策已处理 · 黄灯消退")
          guard await wait(1.6) else{return}
          show(rows(1,0,1),"读掉绿点")
          guard await wait(1.6) else{return}
          show(rows(1),"读掉红点 · 仍有任务")
        }
        guard await wait(3.6) else{return}
        if !auto {label+=" · 可重播或切换案例";return}
        current=ReviewCase(rawValue:(current.rawValue+1)%ReviewCase.allCases.count)!
      } while !Task.isCancelled
    }
  }
  func next(){run(ReviewCase(rawValue:(selectedCase.rawValue+1)%ReviewCase.allCases.count)!)}
  func stop(){job?.cancel();job=nil}
}
struct LoopView: View {
  @ObservedObject var loop: LoopModel
  var body: some View {
    VStack(spacing:16) {
      Text("Notch 转场审阅 · \(loop.selectedCase.rawValue+1) / \(ReviewCase.allCases.count)").font(.system(size:15,weight:.medium)).foregroundStyle(.primary)
      Picker("审阅案例",selection:Binding(get:{loop.selectedCase},set:{loop.run($0)} )) {
        ForEach(ReviewCase.allCases){item in Text(item.title).tag(item)}
      }
      Text(loop.label).font(.system(size:13)).foregroundStyle(.secondary)
      LoopRobot(board:loop.board,enlarged:loop.enlarged).frame(width:200,height:390,alignment:.top)
      HStack {
        Button(loop.enlarged ? "实际大小" : "放大 3 倍") {loop.enlarged.toggle()}
        Button("重播本项") {loop.start()}
        Button("下一项") {loop.next()}
        Toggle("连续播放",isOn:$loop.auto).toggleStyle(.checkbox)
        Button("结束预览") {loop.stop();NSApplication.shared.terminate(nil)}
      }
      Text("本地模拟 · 无模型调用 · 不修改真实任务").font(.system(size:11)).foregroundStyle(.secondary)
    }.padding(24).frame(width:620,height:720)
      .background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
  }
}
struct LoopRobot:View {
  @ObservedObject var board:BoardModel
  let enlarged:Bool
  var body:some View {
    RootView(model:board,panelSize:CGSize(width:320,height:460),restSize:CGSize(width:38,height:44))
      .frame(width:board.currentIslandWidth,height:board.currentIslandHeight)
      .animation(board.expanded ? NotchGeometryAnimation.animation : nil, value: CGSize(width:board.currentIslandWidth,height:board.currentIslandHeight))
      .scaleEffect(enlarged ? 3 : 1,anchor:.top)
      .allowsHitTesting(false)
      .id(ObjectIdentifier(board))
  }
}
@main enum LoopMain {
 @MainActor static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.regular)
  let delegate=LoopDelegate();app.delegate=delegate;app.run()
 }
}
@MainActor final class LoopDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
 let loop=LoopModel();var panel:NSWindow?
 func applicationDidFinishLaunching(_ notification:Notification){
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:720),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  window.delegate=self;window.title="Notch 独立循环预览";window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=true;window.level = .floating
  window.isMovableByWindowBackground=true;window.contentView=NSHostingView(rootView:LoopView(loop:loop));window.center();window.makeKeyAndOrderFront(nil);appActivate();panel=window;loop.start()
 }
 func appActivate(){NSApplication.shared.activate(ignoringOtherApps:true)}
 func windowWillClose(_ notification:Notification){loop.stop();NSApplication.shared.terminate(nil)}
 func applicationWillTerminate(_ notification:Notification){loop.stop()}
}
