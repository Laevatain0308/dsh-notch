import AppKit
import SwiftUI

final class PreviewIdleCue: @unchecked Sendable {
  static let notification=Notification.Name("NotchRecordingIdleCue")
  let boardID:ObjectIdentifier
  let action:String
  init(board:BoardModel,action:String) {boardID=ObjectIdentifier(board);self.action=action}
}

enum DemoState {case running, decision, success, failure}
struct DemoBeat {
  let at:Double
  var rows:[NotchRow]? = nil
  var action:String? = nil
}
struct DemoScene: Identifiable {
  let id:String
  let title:String
  var englishTitle:String {DemoCatalog.english[id] ?? id}
  let initial:[NotchRow]
  let beats:[DemoBeat]
  var duration:Double=7.8
}

enum DemoCatalog {
  static let english:[String:String] = [
    "birth-blue":"Idle → Running",
    "birth-yellow":"Idle → Decision",
    "one-yellow":"Running → Decision",
    "one-return":"Decision → Running",
    "one-green":"Running → Done",
    "one-red":"Running → Failed",
    "two-yellow":"Two Tasks → Decision",
    "two-return":"Decision → Two Tasks",
    "two-green":"Two Tasks → One Done",
    "two-red":"Two Tasks → One Failed",
    "one-roundtrip":"One Task · Decision & Resume",
    "two-roundtrip":"Two Tasks · Decision & Resume",
    "green-idle":"Done → Idle",
    "red-idle":"Failed → Idle",
    "green-blue":"Read Result → Keep Running",
    "red-blue":"Read Failure → Keep Running",
    "clear-green":"Read Result → Keep Failure",
    "clear-red":"Read Failure → Keep Result",
    "add-work":"One Task → Many Tasks",
    "all-green":"More Tasks Done",
    "all-red":"More Tasks Failed",
    "mixed-green":"Last Task → Done",
    "mixed-red":"Last Task → Failed",
    "clear-all":"All Read → Idle",
    "idle-blink":"Blink",
    "idle-scan":"Look Around",
    "idle-tilt":"Head Tilt",
    "idle-nod":"Nod",
    "idle-stretch":"Stretch",
    "idle-hop":"Hop",
    "idle-balance":"Balance",
    "idle-sneeze":"Sneeze",
    "idle-sleep":"Doze",
    "idle-dance":"Chameleon",
    "idle-flow":"Motion → Motion",
    "dance-flow":"Chameleon Transitions",
  ]
  static func rows(_ states:[DemoState])->[NotchRow] {
    states.enumerated().map {index,state in
      var row=NotchRow(id:"demo-task-\(index)",title:"本地任务",child:false,busy:state == .running || state == .decision,unread:state == .success || state == .failure)
      if state == .decision {row.approval=NotchApproval(id:"demo-approval-\(index)",toolName:"本地演示")}
      if state == .success || state == .failure {row.lastTurn=NotchLastTurn(at:1,kind:"demo",failed:state == .failure)}
      return row
    }
  }
  static func scene(_ id:String,_ title:String,_ from:[DemoState],_ to:[DemoState],at:Double=2.3)->DemoScene {
    DemoScene(id:id,title:title,initial:rows(from),beats:[DemoBeat(at:at,rows:rows(to))])
  }
  static func clear(_ id:String,_ title:String,_ from:[DemoState],index:Int)->DemoScene {
    let source=rows(from)
    return DemoScene(id:id,title:title,initial:source,beats:[DemoBeat(at:2.3,rows:source.filter {$0.id != "demo-task-\(index)"})])
  }
  static func idle(_ action:String,_ title:String)->DemoScene {
    DemoScene(id:"idle-\(action)",title:title,initial:[],beats:[DemoBeat(at:0.65,action:action)],duration:action == "sleep" ? 10.5:9)
  }
  static let groups:[[DemoScene]] = [
    [scene("birth-blue","待机 → 运行",[],[.running]),
     scene("birth-yellow","待机 → 决策",[],[.decision]),
     scene("one-yellow","运行 → 决策",[.running],[.decision]),
     scene("one-return","决策 → 运行",[.decision],[.running]),
     scene("one-green","运行 → 完成",[.running],[.success]),
     scene("one-red","运行 → 失败",[.running],[.failure])],
    [scene("two-yellow","两个任务 → 决策",[.running,.running],[.decision,.running]),
     scene("two-return","决策 → 两个任务",[.decision,.running],[.running,.running]),
     scene("two-green","两个任务 → 完成",[.running,.running],[.success,.running]),
     scene("two-red","两个任务 → 失败",[.running,.running],[.failure,.running]),
     DemoScene(id:"one-roundtrip",title:"一个任务 · 决策往返",initial:rows([.running]),beats:[DemoBeat(at:1.6,rows:rows([.decision])),DemoBeat(at:4.5,rows:rows([.running]))]),
     DemoScene(id:"two-roundtrip",title:"两个任务 · 决策往返",initial:rows([.running,.running]),beats:[DemoBeat(at:1.6,rows:rows([.decision,.running])),DemoBeat(at:4.5,rows:rows([.running,.running]))])],
    [clear("green-idle","完成 → 待机",[.success],index:0),
     clear("red-idle","失败 → 待机",[.failure],index:0),
     clear("green-blue","已读完成 → 继续运行",[.success,.running],index:0),
     clear("red-blue","已读失败 → 继续运行",[.failure,.running],index:0),
     clear("clear-green","已读完成 → 保留失败",[.success,.failure],index:0),
     clear("clear-red","已读失败 → 保留完成",[.success,.failure],index:1)],
    [scene("add-work","一个任务 → 多个任务",[.running],[.running,.running,.running]),
     scene("all-green","继续完成 → 完成累积",[.success,.running],[.success,.success]),
     scene("all-red","继续失败 → 失败累积",[.failure,.running],[.failure,.failure]),
     scene("mixed-green","最后任务 → 完成",[.success,.failure,.running],[.success,.failure,.success]),
     scene("mixed-red","最后任务 → 失败",[.success,.failure,.running],[.success,.failure,.failure]),
     DemoScene(id:"clear-all",title:"全部已读 → 待机",initial:rows([.success,.failure]),beats:[DemoBeat(at:1.6,rows:rows([.success,.failure]).filter {$0.id != "demo-task-0"}),DemoBeat(at:4.1,rows:[])])],
    [idle("blink","眨眼"),idle("scan","左右看看"),idle("tilt","歪头"),idle("nod","点头"),idle("stretch","伸懒腰"),idle("hop","蹦一蹦")],
    [idle("balance","保持平衡"),idle("sneeze","打喷嚏"),idle("sleep","打个盹"),idle("dance","变色龙"),
     DemoScene(id:"idle-flow",title:"动作自然衔接",initial:[],beats:[DemoBeat(at:0.65,action:"nod"),DemoBeat(at:4.4,action:"stretch")],duration:12),
     DemoScene(id:"dance-flow",title:"彩蛋自然衔接",initial:[],beats:[DemoBeat(at:0.65,action:"dance"),DemoBeat(at:5.3,action:"scan")],duration:13)]
  ]
  static var all:[DemoScene] {groups.flatMap {$0}}
}

@MainActor final class DemoTile:ObservableObject,Identifiable {
  let id=UUID()
  let scene:DemoScene
  let board=BoardModel()
  init(_ scene:DemoScene) {
    self.scene=scene;board.previewMode=true
    apply(scene.initial);board.tickOrbitLayout(at:Date().addingTimeInterval(3))
  }
  func apply(_ rows:[NotchRow]) {
    board.applySnapshot(NotchSnapshot(ok:true,generatedAt:0,origin:"offline-recording",rows:rows))
  }
  func apply(_ beat:DemoBeat) {
    if let rows=beat.rows {apply(rows)}
    if let action=beat.action {NotificationCenter.default.post(name:PreviewIdleCue.notification,object:PreviewIdleCue(board:board,action:action))}
  }
}

@MainActor final class RecordingModel:ObservableObject {
  @Published var tiles:[DemoTile]=[]
  @Published var group=0
  @Published var selected=0
  @Published var solo=false
  @Published var autoplay=true
  @Published var controls=false
  private var job:Task<Void,Never>?
  private var epoch=0
  var count:Int {solo ? DemoCatalog.all.count:DemoCatalog.groups.count}
  var page:Int {solo ? selected:group}
  var scenes:[DemoScene] {solo ? [DemoCatalog.all[selected]]:DemoCatalog.groups[group]}
  func move(_ direction:Int) {
    if solo {selected=(selected+direction+count)%count} else {group=(group+direction+count)%count}
    replay()
  }
  func toggleLayout() {
    if !solo {selected=group*6} else {group=selected/6}
    solo.toggle();replay()
  }
  func replay() {
    job?.cancel();epoch += 1;let token=epoch
    job=Task { @MainActor in
      while !Task.isCancelled,token==epoch {
        let batch=scenes.map(DemoTile.init);tiles=batch
        let duration=scenes.map(\.duration).max() ?? 8
        let events=batch.flatMap {tile in tile.scene.beats.map {(tile,$0)}}.sorted {$0.1.at < $1.1.at}
        var last=0.0
        for (tile,beat) in events {
          do {try await Task.sleep(for:.seconds(max(0,beat.at-last)))} catch {return}
          guard token==epoch else {return};tile.apply(beat);last=beat.at
        }
        do {try await Task.sleep(for:.seconds(max(0,duration-last)))} catch {return}
        guard token==epoch else {return}
        if autoplay {
          if solo {selected=(selected+1)%count} else {group=(group+1)%count}
        }
      }
    }
  }
  func stop() {job?.cancel();job=nil;epoch += 1}
}
