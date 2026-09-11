import AppKit
import Combine
import SwiftUI

// MARK: - Figma Canonical Design Tokens (EDkOOLoBXBuTVsPHmnAvoC)
enum NotchTokens {
  static let amber = Color(red: 0.949, green: 1.0, blue: 0.078)             // #F2FF14
  static let amberGlow = Color(red: 0.949, green: 1.0, blue: 0.078).opacity(0.5)
  static let redFail = Color(red: 1.0, green: 0.251, blue: 0.0)             // #FF4000
  static let redGlow = Color(red: 1.0, green: 0.251, blue: 0.0).opacity(0.5)
  static let greenComplete = Color(red: 0.204, green: 0.780, blue: 0.349)   // #34C759 Apple Emerald Green
  static let greenGlow = Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.5)
  static let deepSeekBlue = Color(red: 0.302, green: 0.420, blue: 0.996)   // #4D6BFE
  static let bodyBackground = Color.black
  /// Pinned to the expanded width and trailing-aligned.
  /// Compact 38pt sits in the last ~12%, so it stays 90–100% black.
  /// Expanded left is 50% black over HUD blur — enough contrast, still reads as glass.
  static let glassFade = LinearGradient(
    stops: [
      .init(color: Color.black.opacity(0.50), location: 0),
      .init(color: Color.black.opacity(0.72), location: 0.40),
      .init(color: Color.black.opacity(0.90), location: 0.82),
      .init(color: Color.black, location: 1),
    ],
    startPoint: UnitPoint.leading,
    endPoint: UnitPoint.trailing
  )
  static let glassRim = LinearGradient(
    stops: [
      .init(color: Color.white.opacity(0.10), location: 0),
      .init(color: Color.white.opacity(0.04), location: 0.28),
      .init(color: Color.clear, location: 0.72),
    ],
    startPoint: UnitPoint.leading,
    endPoint: UnitPoint.trailing
  )
  static let fieldBackground = Color(red: 0.059, green: 0.059, blue: 0.071)// #0F0F12
  static let badgeBackground = Color(red: 0.149, green: 0.149, blue: 0.149)// #262626
  static let chipStroke = Color.white.opacity(0.28)
  static let otherChipStroke = Color.white.opacity(0.20)
}

struct QuestionDraft {
  var selected: [String] = []
  var custom = ""
  var skipped = false

  var done: Bool {
    skipped
      || !selected.isEmpty
      || !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct AskWizard {
  var askId: String
  var sessionId: String
  var index: Int
  var drafts: [String: QuestionDraft]
  var showCustomField = false
}

// MARK: - Model
@MainActor
final class BoardModel: ObservableObject {
  @Published var rows: [NotchRow] = []
  @Published var expanded = false {
    didSet { syncShowingExpanded(from: oldValue) }
  }
  /// Content lags collapse so the window can shrink before lamps replace the panel.
  @Published var showingExpanded = false
  private var contentFold: DispatchWorkItem?
  @Published var selected: String?
  @Published var hovered: String?
  @Published var wizard: AskWizard?
  @Published var error: String?
  @Published var actionError: String?
  private var submitting = false
  @Published var connected = false
  @Published var maximumExpandedHeight: CGFloat = 130
  @Published var measuredContentHeight: CGFloat = 170
  @Published var currentIslandWidth: CGFloat = 32
  @Published var currentIslandHeight: CGFloat = 90
  @Published var isPillHovered: Bool = false

  @Published var orbitLayout = OrbitLayout()
  var retainedBusyCount = 0
  var retainedSuccessCount = 0
  var retainedFailureCount = 0
  private var layoutFrom = OrbitLayout()
  private var layoutTarget = OrbitLayout()
  private var layoutBegan = Date()
  private var layoutFlightID: UUID?
  private var layoutTimer: Timer?
  @Published var statusFlight: StatusFlight?
  private var pendingFlights: [StatusFlight] = []

  private var previousBusyIds = Set<String>()
  private var initialized = false

  var allowExpandOnHover: Bool {
    needsAction
  }

  private func syncShowingExpanded(from old: Bool) {
    contentFold?.cancel()
    contentFold = nil
    if expanded {
      showingExpanded = true
      return
    }
    guard old else {
      showingExpanded = false
      return
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.expanded else { return }
      self.showingExpanded = false
    }
    contentFold = work
    DispatchQueue.main.asyncAfter(deadline: .now() + NotchGeometryAnimation.duration, execute: work)
  }
  var foldEnabled = false
  private var revealed = false

  let client = NotchClient()
  var previewMode = false
  private var timer: Timer?

  var needsAction: Bool { rows.contains(where: \.needsAction) }
  var anyBusy: Bool { rows.contains(where: \.busy) }
  var anyFailed: Bool { !failedRows.isEmpty }

  var busyCount: Int { rows.filter { $0.busy && !$0.needsAction }.count }
  var completedUnreadCount: Int { completedUnreadRows.count }

  var busyRows: [NotchRow] {
    rows.filter(\.busy)
  }

  var completedUnreadRows: [NotchRow] {
    rows.filter { $0.unread && !$0.busy && $0.lastTurn?.failed != true && !$0.needsAction }
  }

  var failedRows: [NotchRow] {
    rows.filter(\.isFailedResult)
  }

  var activeActionRow: NotchRow? {
    rows.first(where: \.needsAction)
  }

  var firstFailedRow: NotchRow? { failedRows.first }

  var firstCompletedRow: NotchRow? {
    completedUnreadRows.first
  }

  func start() {
    if previewMode { return }
    timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
    timer?.tolerance = 0.2
    Task { await refresh() }
  }

  func refresh() async {
    do { applySnapshot(try await client.status()) }
    catch { connected = false; self.error = "等待 Host…" }
  }

  func applySnapshot(_ snap: NotchSnapshot) {
    let coldSnapshot = !initialized
    let beforeBusy = busyCount
    let beforeSuccess = completedUnreadCount
    let beforeFailure = failedRows.count
    let finished = initialized ? snap.rows.filter { previousBusyIds.contains($0.id) && !$0.busy && !$0.needsAction && ($0.unread || $0.lastTurn?.failed == true) } : []
    previousBusyIds = Set(snap.rows.filter(\.busy).map(\.id))
    initialized = true
    let wasAwaitingAction = needsAction
    rows = snap.rows
    if wasAwaitingAction && !needsAction { expanded = false }
    connected = true
    error = nil
    if let wizard, !snap.rows.contains(where: { $0.ask?.id == wizard.askId }) { self.wizard = nil }
    if selected == nil { selected = rows.first?.id }
    if let selected, !rows.contains(where: { $0.id == selected }) { self.selected = rows.first?.id }
    if !rows.isEmpty && !revealed {
      revealed = true
      if needsAction {
        expanded = true
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 3_500_000_000)
          self.foldEnabled = true
        }
      } else { foldEnabled = true }
    }
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { updateOrbitLayout(); return }
    for failed in [false, true] where finished.contains(where: { ($0.lastTurn?.failed == true) == failed }) {
      if !pendingFlights.contains(where: { $0.failed == failed }) {
        pendingFlights.append(StatusFlight(failed: failed, startedAt: Date(), busyBefore: beforeBusy,
                                          destinationBefore: failed ? beforeFailure : beforeSuccess, returnsToRunning: busyCount > 0))
      }
    }
    if busyCount == 0 && completedUnreadCount == 0 && failedRows.isEmpty && !needsAction {
      pendingFlights.removeAll(); statusFlight=nil
    }
    startNextStatusFlight()
    updateOrbitLayout(animateBirth:!coldSnapshot)
  }

  private func startNextStatusFlight() {
    guard statusFlight == nil, !pendingFlights.isEmpty else { return }
    let next = pendingFlights.removeFirst()
    let flight = StatusFlight(failed: next.failed, startedAt: Date(), busyBefore: next.busyBefore,
                              destinationBefore: next.destinationBefore, returnsToRunning: busyCount > 0, angle:decisionAngle(at:Date()))
    decisionSpin=DecisionSpin(began:flight.startedAt,angle:flight.angle,initialVelocity:DecisionSpin.runningVelocity,finalVelocity:DecisionSpin.runningVelocity)
    statusFlight = flight
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(StatusFlight.duration))
      self?.finishStatusFlight(id: flight.id)
    }
  }

  func finishStatusFlight(id: UUID) {
    guard statusFlight?.id == id else { return }
    if let flight=statusFlight { tickOrbitLayout(at:flight.startedAt.addingTimeInterval(StatusFlight.duration)) }
    statusFlight = nil
    startNextStatusFlight()
    updateOrbitLayout()
  }

  var closingDecision:Bool { layoutTarget.decision > 0 && layoutFrom.middle > 0 }
  private var decisionSpin:DecisionSpin?
  var decisionSpinActive:Bool { decisionSpin.map { Date().timeIntervalSince($0.began) < DecisionSpin.duration+$0.delay } ?? false }
  func decisionAngle(at now:Date)->Double { decisionSpin?.position(at:now) ?? now.timeIntervalSinceReferenceDate*DecisionSpin.runningVelocity }
  func decisionVelocity(at now:Date)->Double { decisionSpin?.velocity(at:now) ?? DecisionSpin.runningVelocity }
  func updateOrbitLayout(at now:Date = Date(),animateBirth:Bool = true) {
    let target=OrbitLayout(top:completedUnreadCount > 0 ? 1:0,middle:busyCount > 0 ? 1:0,bottom:failedRows.isEmpty ? 0:1,decision:needsAction ? 1:0)
    if busyCount > 0 { retainedBusyCount=busyCount }
    if completedUnreadCount > 0 { retainedSuccessCount=completedUnreadCount }
    if !failedRows.isEmpty { retainedFailureCount=failedRows.count }
    guard target != layoutTarget || statusFlight?.id != layoutFlightID else { return }
    if target.decision != layoutTarget.decision || target.middle != layoutTarget.middle {
      let birth=animateBirth && orbitLayout.total < 0.0001
      let fromSolid=orbitLayout.decision >= 0.9999 && orbitLayout.middle < 0.0001
      let resetPen=birth || (fromSolid && target.middle > 0)
      let running=target.middle > 0
      let penVelocity=birth && running ? StatusBirth.bluePenVelocity:(fromSolid && running ? DecisionSpin.runningVelocity:0)
      decisionSpin=DecisionSpin(began:now,angle:resetPen ? -.pi/2:decisionAngle(at:now),initialVelocity:resetPen ? penVelocity:decisionVelocity(at:now),finalVelocity:target.decision > 0 && target.middle == 0 ? 0:DecisionSpin.runningVelocity,delay:birth ? RobotDeparture.duration:(fromSolid ? DecisionMorph.resumeDuration:0))
    }
    layoutFrom=orbitLayout;layoutTarget=target;layoutBegan=now;layoutFlightID=statusFlight?.id
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { orbitLayout=target;return }
    layoutTimer?.invalidate()
    layoutTimer=Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] _ in
      Task { @MainActor in self?.tickOrbitLayout() }
    }
  }
  func tickOrbitLayout(at now:Date = Date()) {
    if let flight=statusFlight {
      orbitLayout=OrbitLayout.flight(from:layoutFrom,to:layoutTarget,progress:min(1,max(0,now.timeIntervalSince(flight.startedAt)/StatusFlight.duration)),flight:flight)
    } else {
      let resuming=layoutFrom.decision >= 0.9999 && layoutFrom.middle < 0.0001 && layoutTarget.middle > 0
      let duration=resuming ? DecisionMorph.resumeDuration:(closingDecision ? DecisionClosing.duration:(layoutTarget.total == 0 ? 0.82 : (layoutFrom.decision != layoutTarget.decision && layoutFrom.middle != layoutTarget.middle ? DecisionSpin.duration:0.42)))
      let t=min(1,max(0,now.timeIntervalSince(layoutBegan)/duration))
      orbitLayout=OrbitLayout.mix(layoutFrom,layoutTarget,(resuming || closingDecision) ? t:IdleInterpolation.smooth(t))
      if t >= 1 { layoutTimer?.invalidate();layoutTimer=nil }
    }
    if orbitLayout.top == 0 { retainedSuccessCount=0 }
    if orbitLayout.bottom == 0 { retainedFailureCount=0 }
  }

  func pick(_ id: String) {
    selected = id
    if previewMode { return }
    Task {
      try? await client.seen(sessionId: id)
      try? await client.focus(sessionId: id)
      activateDSH()
      await refresh()
    }
  }

  func allow(_ id: String) {
    let sessionId = activeActionRow?.id ?? selected
    if previewMode {
      expanded = false
      return
    }
    Task {
      try? await client.approve(id: id, outcome: "allowed-once")
      if let sessionId {
        try? await client.focus(sessionId: sessionId)
        activateDSH()
      }
      await refresh()
    }
  }

  func reject(_ id: String) {
    let sessionId = activeActionRow?.id ?? selected
    if previewMode {
      expanded = false
      return
    }
    Task {
      try? await client.approve(id: id, outcome: "rejected")
      if let sessionId {
        try? await client.focus(sessionId: sessionId)
        activateDSH()
      }
      await refresh()
    }
  }

  func readWizard(ask: NotchAsk, sessionId: String) -> AskWizard {
    if let wizard, wizard.askId == ask.id { return wizard }
    var drafts: [String: QuestionDraft] = [:]
    for question in ask.questions { drafts[question.id] = QuestionDraft() }
    return AskWizard(askId: ask.id, sessionId: sessionId, index: 0, drafts: drafts)
  }

  func wizard(for ask: NotchAsk, sessionId: String) -> AskWizard {
    let current = readWizard(ask: ask, sessionId: sessionId)
    if wizard?.askId != current.askId { wizard = current }
    return wizard ?? current
  }

  func tapOption(ask: NotchAsk, sessionId: String, question: NotchQuestion, label: String) {
    var state = wizard(for: ask, sessionId: sessionId)
    var draft = state.drafts[question.id] ?? QuestionDraft()
    if question.multiSelect == true {
      if draft.selected.contains(label) {
        draft.selected.removeAll { $0 == label }
      } else {
        draft.selected.append(label)
      }
      draft.skipped = false
    } else {
      draft.selected = [label]
      draft.custom = ""
      draft.skipped = false
    }
    state.drafts[question.id] = draft
    state.showCustomField = false
    if question.multiSelect != true, state.index < ask.questions.count - 1 {
      state.index += 1
    }
    wizard = state
    if question.multiSelect != true && ask.questions.allSatisfy({ state.drafts[$0.id]?.done == true }) {
      submitAsk(ask: ask, sessionId: sessionId)
    }
  }

  func toggleCustomField(ask: NotchAsk, sessionId: String) {
    var state = wizard(for: ask, sessionId: sessionId)
    state.showCustomField.toggle()
    wizard = state
  }

  func skipQuestion(ask: NotchAsk, sessionId: String) {
    var state = wizard(for: ask, sessionId: sessionId)
    guard let question = ask.questions[safe: state.index] else { return }
    state.drafts[question.id] = QuestionDraft(skipped: true)
    if state.index < ask.questions.count - 1 {
      state.index += 1
      wizard = state
      return
    }
    wizard = state
    submitAsk(ask: ask, sessionId: sessionId)
  }

  func goQuestion(ask: NotchAsk, sessionId: String, delta: Int) {
    var state = wizard(for: ask, sessionId: sessionId)
    state.index = min(max(state.index + delta, 0), ask.questions.count - 1)
    wizard = state
  }

  func setCustom(ask: NotchAsk, sessionId: String, questionId: String, text: String) {
    var state = wizard(for: ask, sessionId: sessionId)
    var draft = state.drafts[questionId] ?? QuestionDraft()
    draft.custom = text
    draft.skipped = false
    if question(ask, questionId)?.multiSelect != true {
      draft.selected = []
    }
    state.drafts[questionId] = draft
    wizard = state
  }

  func submitAsk(ask: NotchAsk, sessionId: String) {
    let state = wizard(for: ask, sessionId: sessionId)
    guard ask.questions.allSatisfy({ state.drafts[$0.id]?.done == true }) else { return }
    guard !submitting else { return }
    if previewMode {
      wizard = nil
      expanded = false
      return
    }
    submitting = true
    actionError = nil
    let answers: [[String: Any]] = ask.questions.map { question in
      let draft = state.drafts[question.id] ?? QuestionDraft()
      if draft.skipped { return ["id": question.id, "selected": [String]()] }
      let custom = draft.custom.trimmingCharacters(in: .whitespacesAndNewlines)
      var item: [String: Any] = [
        "id": question.id,
        "selected": custom.isEmpty || question.multiSelect == true ? draft.selected : [],
      ]
      if !custom.isEmpty { item["custom"] = custom }
      return item
    }
    Task {
      defer { submitting = false }
      do {
        try await client.answer(id: ask.id, answers: answers)
        await refresh()
      } catch {
        self.actionError = "提交失败，请重试；也可以在 DSH 中回答。"
      }
    }
  }

  private func question(_ ask: NotchAsk, _ id: String) -> NotchQuestion? {
    ask.questions.first { $0.id == id }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

// MARK: - PreferenceKey for Hug-Content Height
private struct ContentHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

// MARK: - Root View (Highest UI/UX Standard Dynamic Island)
struct RootView: View {
  @ObservedObject var model: BoardModel
  let panelSize: CGSize
  let restSize: CGSize

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  // Apple Dynamic Island fluid spring: crisp, elastic, settles fast
  private let morphAnimation = Animation.spring(response: 0.32, dampingFraction: 0.78)

  private var restCapsuleHeight: CGFloat {
    let base = model.orbitLayout.height + 24
    return model.isPillHovered ? base - 2 : base
  }

  private var targetWidth: CGFloat {
    if model.expanded {
      return panelSize.width
    }
    return model.isPillHovered ? 42 : 38
  }

  private var targetHeight: CGFloat {
    if model.expanded {
      let floor: CGFloat = model.needsAction ? 280 : 130
      return min(max(model.measuredContentHeight, floor), model.maximumExpandedHeight)
    }
    return restCapsuleHeight
  }

  private var cornerRadius: CGFloat {
    16
  }

  private var shellShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: cornerRadius,
      bottomLeadingRadius: cornerRadius,
      bottomTrailingRadius: 0,
      topTrailingRadius: 0,
      style: .continuous
    )
  }

  private var shellBackground: some View {
    // Overlay only: a 320pt gradient must not become the layout width, or compact
    // content is drawn in the middle of 320pt and clipped out of the 38pt window.
    shellShape
      .fill(reduceTransparency ? Color.black : Color.clear)
      .overlay(alignment: .trailing) {
        if !reduceTransparency {
          NotchTokens.glassFade
            .frame(width: panelSize.width)
        }
      }
      .overlay {
        if !reduceTransparency && model.showingExpanded {
          shellShape.strokeBorder(NotchTokens.glassRim, lineWidth: 0.6)
        }
      }
      .clipShape(shellShape)
      .allowsHitTesting(false)
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.clear

      // One continuous shell: HUD glass fading to black at the trailing screen edge.
      ZStack(alignment: .topTrailing) {
        shellBackground

        // Inside content reveals naturally as the single body blooms
        if model.showingExpanded {
          expandedContent
            .frame(width: panelSize.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
              GeometryReader { geo in
                Color.clear.preference(key: ContentHeightPreferenceKey.self, value: geo.size.height)
              }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .opacity(model.expanded ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: model.expanded)
            .clipped()
        } else {
          compactPillContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topTrailing)
      .clipShape(shellShape)
    }
    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topTrailing)
    // The native panel owns geometry animation; its body fills the same bounds.
    .transaction { $0.animation = nil }
    .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
      guard model.expanded else { return }
      let cap = model.maximumExpandedHeight - 8
      guard height > 40, height < cap else { return }
      model.measuredContentHeight = height
    }
    .onChange(of: CGSize(width: targetWidth, height: targetHeight), initial: true) { _, size in
      model.currentIslandWidth = size.width
      model.currentIslandHeight = size.height
    }
  }

  // MARK: - Rest Capsule Content (Live Multi-Thread Activity Cockpit)
  private var compactPillContent: some View {
    Button {
      // Per spec: Click red pip directly jumps to the session; click green jumps to completed
      if model.anyFailed && !model.needsAction {
        if let failSession = model.firstFailedRow {
          model.pick(failSession.id)
        }
      } else if model.completedUnreadCount > 0 && !model.needsAction {
        if let compSession = model.firstCompletedRow {
          model.pick(compSession.id)
        }
      } else {
        model.expanded.toggle()
      }
    } label: {
      ZStack {
        VStack(spacing: 8) {
          IdleStatusSlot(model: model)
        }
      }
      .scaleEffect(model.isPillHovered && (model.needsAction || model.anyFailed || model.completedUnreadCount > 0 || model.busyCount > 0 || model.statusFlight != nil) ? 1.08 : 1.0)
      .animation(morphAnimation, value: model.isPillHovered)
      .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if !model.expanded {
        model.isPillHovered = hovering
        model.currentIslandWidth = targetWidth
        model.currentIslandHeight = targetHeight
      }
    }
  }

  // MARK: - Expanded Content (Figma ROW B / ROW C / Glance List)
  private var expandedContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let error = model.actionError {
        Text(error).font(.system(size: 11)).foregroundStyle(NotchTokens.redFail)
      }
      if let actionRow = model.activeActionRow {
        if let approval = actionRow.approval {
          // ROW B Approval Morph (Figma #23:70)
          approvalView(approval, row: actionRow)
        } else if let ask = actionRow.ask {
          // ROW C Choices (Figma #23:97 / #22:16)
          choicesView(ask, row: actionRow)
        }
      } else {
        // Quick glance session list with full status overview
        glanceSessionList
      }
    }
    .padding(14)
  }

  // MARK: - ROW B: Approval View (✓ / ✕ Circular Buttons)
  private func approvalView(_ approval: NotchApproval, row: NotchRow) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // Top line: Amber pip + "Allow?"
      HStack(spacing: 6) {
        Circle()
          .fill(NotchTokens.amber)
          .frame(width: 10, height: 10)
          .shadow(color: NotchTokens.amberGlow, radius: 3)

        Text("Allow?")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(NotchTokens.amber)

        Spacer()

        Button {
          model.expanded = false
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
        }
        .buttonStyle(.plain)
      }

      // Reason / Tool Name
      Text(approval.reason ?? approval.toolName)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)

      // Circular 32x32 Buttons: Blue ✓ and Outline ✕ (Figma #23:74 & #23:76)
      HStack(spacing: 12) {
        // ✓ 允许一次 (32x32 Solid Blue Circle)
        Button {
          model.allow(approval.id)
        } label: {
          ZStack {
            Circle()
              .fill(NotchTokens.deepSeekBlue)
              .frame(width: 32, height: 32)

            Text("✓")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.black)
          }
        }
        .buttonStyle(.plain)

        // ✕ 拒绝 (32x32 Outline Circle)
        Button {
          model.reject(approval.id)
        } label: {
          ZStack {
            Circle()
              .stroke(Color.white.opacity(0.35), lineWidth: 1)
              .frame(width: 32, height: 32)

            Text("✕")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.white)
          }
        }
        .buttonStyle(.plain)

        Spacer()
      }
      .padding(.top, 4)
    }
  }

  // MARK: - ROW C: Choices View (Chips & Inline Other Morph)
  private func choicesView(_ ask: NotchAsk, row: NotchRow) -> some View {
    let state = model.readWizard(ask: ask, sessionId: row.id)
    let index = min(state.index, max(ask.questions.count - 1, 0))
    let question = ask.questions[index]
    let draft = state.drafts[question.id] ?? QuestionDraft()
    let last = index == ask.questions.count - 1
    let ready = ask.questions.allSatisfy { state.drafts[$0.id]?.done == true }

    return VStack(alignment: .leading, spacing: 10) {
      // Question Title & Counter
      HStack(alignment: .top) {
        Button { model.pick(row.id) } label: {
          Text(question.question)
            .multilineTextAlignment(.leading)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(NotchInteractiveButtonStyle())
        .help("在 DSH 中查看上下文")

        Spacer()

        if ask.questions.count > 1 {
          Text("\(index + 1)/\(ask.questions.count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(NotchTokens.amber)
            .padding(.top, 2)
        }
      }

      // Supporting detail if present
      if let detail = question.detail, !detail.isEmpty {
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(Color.white.opacity(0.65))
          .fixedSize(horizontal: false, vertical: true)
      }

      // Option Chips (Figma #23:100, #22:21)
      Group {
        VStack(spacing: 6) {
          ForEach(question.options ?? []) { option in
            let on = draft.selected.contains(option.label)
            Button {
              model.tapOption(ask: ask, sessionId: row.id, question: question, label: option.label)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(on ? .black : .white)
                  .fixedSize(horizontal: false, vertical: true)
                  .multilineTextAlignment(.leading)

                if let desc = option.description, !desc.isEmpty {
                  Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(on ? Color.black.opacity(0.7) : Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .fill(on ? NotchTokens.deepSeekBlue : Color.clear)
                  .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                      .stroke(on ? Color.clear : NotchTokens.chipStroke, lineWidth: 1)
                  }
              )
            }
            .buttonStyle(NotchInteractiveButtonStyle())
          }

          // Other… Chip / In-blob Field Morph (Figma K3 #22:34)
          if state.showCustomField || !draft.custom.isEmpty || (question.options ?? []).isEmpty {
            TextField("Type…", text: Binding(
              get: { draft.custom },
              set: { model.setCustom(ask: ask, sessionId: row.id, questionId: question.id, text: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NotchTokens.fieldBackground)
                .overlay {
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NotchTokens.deepSeekBlue.opacity(0.9), lineWidth: 1.5)
                }
            )
            .onSubmit {
              if ready { model.submitAsk(ask: ask, sessionId: row.id) }
            }
          } else {
            Button {
              model.toggleCustomField(ask: ask, sessionId: row.id)
            } label: {
              HStack {
                Text("输入其他答案…")
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(Color.white.opacity(0.65))
                Spacer()
              }
              .padding(.horizontal, 12)
              .frame(height: 28)
              .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .stroke(NotchTokens.otherChipStroke, lineWidth: 1)
              )
            }
            .buttonStyle(NotchInteractiveButtonStyle())
          }
        }
      }

      // Multi-question Stepper / Action buttons
      if !ask.questions.isEmpty {
        HStack(spacing: 8) {
          if ask.questions.count > 1 {
            Button("上一题") { model.goQuestion(ask: ask, sessionId: row.id, delta: -1) }
              .buttonStyle(NotchTinyButtonStyle())
              .opacity(index == 0 ? 0.35 : 1)
              .disabled(index == 0)
          }

          Button("跳过") { model.skipQuestion(ask: ask, sessionId: row.id) }
            .buttonStyle(NotchTinyButtonStyle())

          Spacer()

          if last && (question.multiSelect == true || state.showCustomField || !draft.custom.isEmpty || (question.options ?? []).isEmpty) {
            Button("完成") { model.submitAsk(ask: ask, sessionId: row.id) }
              .buttonStyle(NotchBlueTinyButtonStyle())
              .opacity(ready ? 1 : 0.45)
              .disabled(!ready)
          } else if !last {
            Button("下一题") { model.goQuestion(ask: ask, sessionId: row.id, delta: 1) }
              .buttonStyle(NotchBlueTinyButtonStyle())
          }
        }
        .padding(.top, 4)
      }
    }
  }

  // MARK: - Glance Session List with Running & Completion Overview
  private var glanceSessionList: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header with summary badges and "Clear All" action
      HStack(spacing: 6) {
        if model.busyCount > 0 {
          HStack(spacing: 4) {
            Circle().fill(NotchTokens.deepSeekBlue).frame(width: 6, height: 6)
            Text("\(model.busyCount) 进行中")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(NotchTokens.deepSeekBlue)
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(Capsule().fill(NotchTokens.deepSeekBlue.opacity(0.14)))
        }

        if model.completedUnreadCount > 0 {
          HStack(spacing: 5) {
            Circle().fill(NotchTokens.greenComplete).frame(width: 6, height: 6)
            Text("\(model.completedUnreadCount) 完成")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(NotchTokens.greenComplete)


          }
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(Capsule().fill(NotchTokens.greenComplete.opacity(0.14)))
        }

        Spacer()

        Button {
          model.expanded = false
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
        }
        .buttonStyle(.plain)
      }

      if model.rows.isEmpty {
        Text("无活跃会话")
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.35))
          .padding(.vertical, 6)
      } else {
        ScrollView {
          VStack(spacing: 4) {
            ForEach(model.rows) { row in
              Button {
                model.pick(row.id)
              } label: {
                HStack(spacing: 8) {
                  // Status Pip
                  if row.busy {
                    Circle()
                      .fill(NotchTokens.deepSeekBlue)
                      .frame(width: 6, height: 6)
                      .shadow(color: NotchTokens.deepSeekBlue.opacity(0.8), radius: 2)
                  } else if row.isFailedResult {
                    Circle()
                      .fill(NotchTokens.redFail)
                      .frame(width: 6, height: 6)
                  } else if row.needsAction {
                    Circle()
                      .fill(NotchTokens.amber)
                      .frame(width: 6, height: 6)
                  } else if row.unread {
                    Circle()
                      .fill(NotchTokens.greenComplete)
                      .frame(width: 6, height: 6)
                  } else {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 5, height: 5)
                  }

                  Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                  Spacer()

                  if row.busy {
                    Text("运行中")
                      .font(.system(size: 9))
                      .foregroundStyle(NotchTokens.deepSeekBlue)
                  } else if row.unread && row.lastTurn?.failed != true {
                    Text("完成")
                      .font(.system(size: 9, weight: .medium))
                      .foregroundStyle(NotchTokens.greenComplete)
                  }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(row.id == model.selected ? Color.white.opacity(0.06) : Color.clear)
                )
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(maxHeight: 180)
      }
    }
  }
}

// MARK: - Tiny Button Styles
struct NotchTinyButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(.white.opacity(0.85))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.06))
      .clipShape(Capsule())
  }
}

struct NotchBlueTinyButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(NotchTokens.deepSeekBlue.opacity(configuration.isPressed ? 0.75 : 1.0))
      .clipShape(Capsule())
  }
}

/// Bring the DSH desktop app forward so the focused session is visible.
@MainActor
func activateDSH() {
  let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.dsh.desktop")
  guard let app = apps.first else { return }
  app.unhide()
  _ = app.activate()
  if let url = app.bundleURL {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
  }
}

/// Subtle local feedback without changing which answer is selected.
struct NotchInteractiveButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Feedback(configuration: configuration)
  }
  private final class HoverState: ObservableObject {
    @Published var hovered = false
  }
  private struct Feedback: View {
    let configuration: ButtonStyleConfiguration
    @StateObject private var hover = HoverState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
      configuration.label
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(configuration.isPressed ? 0.16 : hover.hovered ? 0.08 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(hover.hovered ? 0.32 : 0), lineWidth: 1))
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hover.hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        .onHover { hover.hovered = $0 }
    }
  }
}
