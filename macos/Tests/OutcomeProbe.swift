import AppKit
import SwiftUI

@main enum OutcomeProbe {
 @MainActor static func main() {
  NSApplication.shared.setActivationPolicy(.accessory)
  var failures=0
  func check(_ value:Bool,_ label:String) { if !value { failures += 1; print("FAIL \(label)") } }
  for count in [1,2] { for kind in ["approval","success","failure"] {
   let model=BoardModel();model.previewMode=true
   var rows=(0..<count).map { NotchRow(id:"fixture-\($0)",title:"Local fixture",child:false,busy:true,unread:false) }
   func snap()->NotchSnapshot {NotchSnapshot(ok:true,generatedAt:0,origin:"offline",rows:rows)}
   model.applySnapshot(snap());model.tickOrbitLayout(at:Date().addingTimeInterval(2))
   check(model.statusFlight == nil,"cold state has no result replay")
   if kind == "approval" {rows[0].approval=NotchApproval(id:"local-approval",toolName:"offline")}
   else {rows[0].busy=false;rows[0].unread=true;rows[0].lastTurn=NotchLastTurn(at:1,kind:kind,failed:kind == "failure")}
   model.applySnapshot(snap())
   // The state change is stated by the snapshot and interpreted by the library,
   // which is the two halves the island actually runs: a provider says what is,
   // and Notch decides what that looks like.
   model.playTransition(from:.running,to:kind == "approval" ? .deciding:(kind == "failure" ? .failed:.succeeded),count:count)
   guard let flight=model.statusFlight else {check(false,"\(count) task \(kind): a state change must start a travelling brush");continue}
   check(flight.outcome == (kind == "approval" ? .decision:(kind == "failure" ? .failure:.success)),"\(kind): correct destination colour")
   check(flight.returnsToRunning == (count > 1),"\(count) task \(kind): return only if work remains")
   check(flight.busyBefore==count,"source count retained until departure")
   let id=flight.id;model.applySnapshot(snap());check(model.statusFlight?.id==id,"polling does not restart brush")
   let start=OrbitMotionFrame(progress:0,failed:flight.failed,returns:flight.returnsToRunning,angle:flight.angle)
   check(start.tint==0 && start.resultOpacity==0 && start.tailLength>20,"\(kind): starts as visible blue arc")
   let draw=OrbitMotionFrame(progress:0.72,failed:flight.failed,returns:flight.returnsToRunning,angle:flight.angle)
   check(draw.tailLength>0,"\(kind): drawing phase contains ink")
   let end=OrbitMotionFrame(progress:1,failed:flight.failed,returns:flight.returnsToRunning,angle:flight.angle)
   check(end.resultOpacity==1,"\(kind): result is solid at end")
   // Both readings are computed floats, so a fully settled arc lands on ~1e-14
  // rather than exactly zero — zero for anything that can be drawn, and not a
  // reason to fail a run.
  let settledTolerance = 1e-6
  let settled = count > 1 ? end.tint <= settledTolerance : end.tailLength < settledTolerance
  if !settled { print("DIAG count=\(count) kind=\(kind) angle=\(flight.angle) tint=\(end.tint) tail=\(end.tailLength)") }
  check(settled,"\(kind): returning blue or settled result")
   model.finishStatusFlight(id:id)
   check(model.statusFlight==nil,"\(kind): flight ends")
   check(model.busyCount==count-1,"\(kind): exact remaining work")
   check(kind == "approval" ? model.needsAction : (kind == "failure" ? model.failedRows.count==1 : model.completedUnreadCount==1),"\(kind): final result retained")
   print("CHECKED \(count) task \(kind)")
  }}
  func busyRows(_ count:Int)->[NotchRow] {(0..<count).map {NotchRow(id:"action-\($0)",title:"Local",child:false,busy:true,unread:false)}}
  func snapshot(_ rows:[NotchRow])->NotchSnapshot {NotchSnapshot(ok:true,generatedAt:0,origin:"offline",rows:rows)}
  for cancel in [false,true] {
    let m=BoardModel();var rows=busyRows(1)
    m.applySnapshot(snapshot(rows));m.tickOrbitLayout(at:Date().addingTimeInterval(2))
    rows[0].approval=NotchApproval(id:"approval",toolName:"offline")
    m.applySnapshot(snapshot(rows))
    // The flight is asked for by naming the transition, which is how the island
    // starts one now: a snapshot states state, and the library decides what that
    // state change looks like.
    m.playTransition(from:.running,to:.deciding)
    guard let decisionFlight=m.statusFlight else {check(false,"a question arriving starts a stroke");continue}
    let id=decisionFlight.id
    check(!m.expanded && !m.showingExpanded,"automatic panel must preserve travelling stroke")
    if cancel {rows[0].approval=nil;m.applySnapshot(snapshot(rows))}
    m.finishStatusFlight(id:id)
    check(m.expanded == !cancel,"only current approval may open after ink arrives")
    check(m.needsAction == !cancel,"cancelled question cannot reappear")
  }
  // A result queued before an approval must retain its own identity and order.
  let queued=BoardModel();queued.previewMode=true;var rows=busyRows(2)
  queued.applySnapshot(snapshot(rows));queued.tickOrbitLayout(at:Date().addingTimeInterval(2))
  rows[0].busy=false;rows[0].unread=true
  queued.applySnapshot(snapshot(rows));queued.playTransition(from:.running,to:.succeeded)
  guard let successStroke=queued.statusFlight else {print("FAIL a finished task starts a stroke");exit(1)}
  let first=successStroke.id
  rows[1].approval=NotchApproval(id:"queued-approval",toolName:"offline")
  queued.applySnapshot(snapshot(rows));queued.playTransition(from:.running,to:.deciding)
  check(queued.statusFlight?.id==first,"decision does not replace moving success stroke")
  queued.finishStatusFlight(id:first)
  guard let secondStroke=queued.statusFlight else {print("FAIL the queued decision takes the next slot");exit(1)}
  let second=secondStroke.id
  check(queued.statusFlight?.decision == true,"decision uses next brush slot")
  queued.finishStatusFlight(id:first);check(queued.statusFlight?.id==second,"old callback cannot clear current stroke")
  queued.finishStatusFlight(id:second)
  check(queued.completedUnreadCount==1 && queued.needsAction,"green result survives yellow arrival")
  // A decision reply resumes the same task; never increment the visible blue
  // count before the yellow lamp has returned to it.
  for count in [1,2] {
    let m=BoardModel();m.previewMode=true;var rows=busyRows(count)
    m.applySnapshot(snapshot(rows));m.tickOrbitLayout(at:Date().addingTimeInterval(2))
    rows[0].approval=NotchApproval(id:"roundtrip",toolName:"offline")
    m.applySnapshot(snapshot(rows));m.playTransition(from:.running,to:.deciding)
    guard let arrival=m.statusFlight else {print("FAIL a question arriving starts a stroke");exit(1)}
    m.finishStatusFlight(id:arrival.id)
    m.tickOrbitLayout(at:Date().addingTimeInterval(2))
    check(m.busyCount==count-1 && m.needsAction,"awaiting preserves remaining task count")
    rows[0].approval=nil;m.applySnapshot(snapshot(rows))
    if count==2 {check(m.retainedBusyCount==1,"yellow reply must not show blue 2 before merging")}
    guard let reply=m.decisionReturn else {check(false,"reply must own a continuous return timeline");continue}
    check(reply.travelling == (count==2),"reply draws locally or travels to remaining blue")
    m.applySnapshot(snapshot(rows));check(m.decisionReturn?.id==reply.id,"polling does not restart reply")
    m.tickOrbitLayout(at:reply.startedAt.addingTimeInterval(reply.duration*0.1))
    if count==2 {check(m.orbitLayout.decision==1 && m.retainedBusyCount==1,"yellow clears before shell closes and count merges")}
    let finalAngle=m.decisionAngle(at:reply.startedAt.addingTimeInterval(reply.duration))
    m.finishDecisionReturn(id:reply.id)
    check(m.decisionReturn==nil,"reply releases presentation state")
    check(abs(m.decisionAngle(at:reply.startedAt.addingTimeInterval(reply.duration))-finalAngle)<0.00001,"spin phase survives reply handoff")
    m.tickOrbitLayout(at:Date().addingTimeInterval(2))
    check(m.busyCount==count && !m.needsAction,"reply returns original task count")
    check(m.orbitLayout==OrbitLayout(middle:1),"reply leaves one blue lamp without yellow slot")
  }
  for count in [1,2] {
    let m=BoardModel();m.previewMode=true;var rows=busyRows(count)
    m.applySnapshot(snapshot(rows));m.tickOrbitLayout(at:Date().addingTimeInterval(2))
    rows[0].approval=NotchApproval(id:"fast",toolName:"offline")
    m.applySnapshot(snapshot(rows));m.playTransition(from:.running,to:.deciding)
    guard let fast=m.statusFlight else {print("FAIL a question arriving starts a stroke");exit(1)}
    let outward=fast.id
    rows[0].approval=nil;m.applySnapshot(snapshot(rows))
    check(m.statusFlight?.id==outward && m.decisionReturn==nil,"fast reply finishes its outgoing ink first")
    check(m.orbitBusyCount==count-1,"fast reply cannot prematurely change outgoing blue count")
    m.finishStatusFlight(id:outward)
    guard let reply=m.decisionReturn else {check(false,"fast reply starts return after arrival");continue}
    m.finishStatusFlight(id:outward);check(m.decisionReturn?.id==reply.id,"old outbound callback cannot erase reply")
    m.finishDecisionReturn(id:reply.id)
    check(m.orbitLayout==OrbitLayout(middle:1) && m.busyCount==count,"fast reply ends on original blue count")
  }
  // A folded panel must reveal the beginning of the return, not its last frame.
  let panel=BoardModel();var panelRows=busyRows(2)
  panel.applySnapshot(snapshot(panelRows));panel.tickOrbitLayout(at:Date().addingTimeInterval(2))
  panelRows[0].approval=NotchApproval(id:"panel",toolName:"offline")
  panel.applySnapshot(snapshot(panelRows));panel.playTransition(from:.running,to:.deciding)
  guard let panelArrival=panel.statusFlight else {print("FAIL a question arriving starts a stroke");exit(1)}
  panel.finishStatusFlight(id:panelArrival.id)
  check(panel.expanded && panel.showingExpanded,"approval expanded after arrival")
  panelRows[0].approval=nil;let replyTime=Date();panel.applySnapshot(snapshot(panelRows))
  check(!panel.expanded && panel.showingExpanded,"reply folds panel")
  check((panel.decisionReturn?.startedAt.timeIntervalSince(replyTime) ?? 0)>=NotchGeometryAnimation.duration-0.02,"return waits for folded lamp surface")
  // Cancelling a question without resuming that row must not increment unrelated work.
  let cancel=BoardModel();cancel.previewMode=true;var cancelRows=busyRows(2)
  cancelRows[0].approval=NotchApproval(id:"cancel",toolName:"offline")
  cancel.applySnapshot(snapshot(cancelRows));cancel.tickOrbitLayout(at:Date().addingTimeInterval(2))
  cancelRows[0].approval=nil;cancelRows[0].busy=false;cancel.applySnapshot(snapshot(cancelRows))
  check(cancel.decisionReturn==nil && cancel.busyCount==1,"cancel is not a task resume")
  for angle in stride(from:0.0,to:2 * Double.pi,by:Double.pi/4) {
    let route=OrbitBrushRoute(failed:false,angle:angle)
    var previous=DecisionReturnFrame(progress:0,angle:angle)
    check(previous.fill==1 && previous.countMix==0,"return starts as existing yellow and existing count")
    for i in 1...240 {
      let frame=DecisionReturnFrame(progress:Double(i)/240,angle:angle)
      check(frame.distance>=previous.distance && frame.distance-previous.distance<3,"return brush advances continuously")
      check(frame.tint<=previous.tint+0.00001 && abs(frame.tint-previous.tint)<0.08,"return colour blends into blue")
      check(frame.collapse==0 || frame.fill==0,"yellow solid clears before lamps converge")
      check(frame.countMix==0 || frame.distance>=route.returned,"count changes only after ink enters blue ring")
      previous=frame
    }
    check(previous.fill==0 && previous.tint==0 && previous.countMix==1,"return settles on blue new count")
    let near=DecisionReturnFrame(progress:0.9999,angle:angle)
    let velocity=(previous.distance-near.distance)/(StatusFlight.duration*0.0001)
    check(abs(velocity-9.5*DecisionSpin.runningVelocity)<0.05,"pen speed matches final rotating ring")
  }
  print("FAILURES=\(failures)");exit(failures==0 ? 0:1)
 }
}
