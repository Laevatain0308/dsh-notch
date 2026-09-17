//
//  SurfaceView.swift
//  DshNotch
//
//  What the providers are showing, drawn.
//
//  The island's own content, as opposed to the board's: this draws what Core
//  holds, in the order Core composed it, with nothing here deciding importance,
//  order or size. A provider that sent a position, an order or a size sent
//  something this file has no field to read.
//
//  A decision is answered here, which is the whole point of the surface: the
//  answer travels back to whoever asked, and the same path serves every provider
//  because the question is described in the protocol's terms rather than in any
//  one provider's.
//

import SwiftUI

/// The providers' content, as the island presents it.
struct SurfaceView: View {
  let surface: Surface
  let onAnswer: (String, [String: [String]]) -> Void
  /// Ask a provider to do something with an entity the user activated.
  let onAction: (String, String, String) -> Void

  /// What the user has chosen so far, by question.
  ///
  /// A one-question decision is answered by the tap that chooses it, because that
  /// is what a question with two answers means. A decision with more than one
  /// question collects them and sends when the last is answered — sending early
  /// would answer a question the user has not reached.
  @State private var chosen: [String: [String]] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let decision = surface.decision {
        decisionPanel(decision)
      }
      ForEach(Array(surface.slots.enumerated()), id: \.offset) { _, slot in
        slotRow(slot)
      }
      if surface.overflow > 0 {
        Text("另有 \(surface.overflow) 项未显示")
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.42))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
    // A new decision starts unanswered: keeping the previous choices would answer
    // a question with the answer to a different one.
    .onChange(of: surface.decision?.interaction?.id) { _, _ in chosen = [:] }
  }

  // MARK: - A decision

  @ViewBuilder private func decisionPanel(_ decision: Presented) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(decision.title ?? decision.provider)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)

      if let interaction = decision.interaction {
        ForEach(interaction.questions, id: \.id) { question in
          questionPanel(decision: decision, interaction: interaction, question: question)
        }
      }
    }
    .padding(.bottom, 2)
  }

  @ViewBuilder private func questionPanel(
    decision: Presented,
    interaction: Interaction,
    question: Question
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if let header = question.header {
        Text(header)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.white.opacity(0.4))
      }
      Text(question.question)
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.86))
        .fixedSize(horizontal: false, vertical: true)
      if let detail = question.detail {
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.45))
          .fixedSize(horizontal: false, vertical: true)
      }

      if !question.options.isEmpty {
        // Every option is a button: a `Button` inside a list of rows is what the
        // island already uses for its own questions, and the tap is the answer.
        HStack(spacing: 6) {
          ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
            Button {
              choose(decision: decision, interaction: interaction, question: question, label: option.label)
            } label: {
              Text(option.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(chosen[question.id]?.contains(option.label) == true ? Color.black : .white.opacity(0.88))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(chosen[question.id]?.contains(option.label) == true ? NotchTokens.amber : NotchTokens.badgeBackground)
                )
            }
            .buttonStyle(.plain)
          }
          Spacer(minLength: 0)
        }
      }
    }
  }

  /// Record a choice, and send it when the decision is fully answered.
  private func choose(decision: Presented, interaction: Interaction, question: Question, label: String) {
    if question.multiSelect == true {
      var selected = chosen[question.id] ?? []
      if let index = selected.firstIndex(of: label) { selected.remove(at: index) } else { selected.append(label) }
      chosen[question.id] = selected
      return
    }

    chosen[question.id] = [label]
    // One question is answered by the tap that answers it.
    if interaction.questions.count == 1 {
      onAnswer(interaction.id, chosen)
      chosen = [:]
    }
  }

  // MARK: - What is being shown

  @ViewBuilder private func slotRow(_ slot: Slot) -> some View {
    switch slot {
    case .entity(let presented):
      // A row is a button only when its provider offered something to do with it.
      // Notch does not know what `open` means; it knows the provider said it would
      // interpret it, and that the user pointed at this row.
      let actionable = presented.actions?.isEmpty == false
      let row = HStack(spacing: 8) {
        Circle()
          .fill(colour(for: presented))
          .frame(width: 6, height: 6)
        Text(presented.title ?? presented.provider)
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.86))
          .lineLimit(1)
        Spacer(minLength: 0)
        if presented.unread == true {
          Text("未读")
            .font(.system(size: 10))
            .foregroundStyle(NotchTokens.greenComplete)
        }
      }
      if actionable, let action = presented.actions?.first {
        Button {
          onAction(presented.provider, action, presented.key)
        } label: {
          row.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        row
      }
    case .aggregate(let aggregate):
      HStack(spacing: 8) {
        Circle()
          .fill(aggregate.behaviourClass == .awaiting ? NotchTokens.deepSeekBlue : Color.white.opacity(0.35))
          .frame(width: 6, height: 6)
        Text(Self.describe(aggregate))
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.8))
        Spacer(minLength: 0)
      }
    }
  }

  private func colour(for presented: Presented) -> Color {
    switch presented.behaviourClass {
    case .result: return presented.state == "failed" ? NotchTokens.redFail : NotchTokens.greenComplete
    case .awaiting: return NotchTokens.deepSeekBlue
    case .activity, .progress: return NotchTokens.amber
    case .ambient: return Color.white.opacity(0.35)
    }
  }

  /// One affordance standing for however many providers are reporting it.
  private static func describe(_ aggregate: Aggregate) -> String {
    let class_: String
    switch aggregate.behaviourClass {
    case .activity: class_ = "正在运行"
    case .progress: class_ = "进行中"
    case .ambient: class_ = "状态"
    case .result: class_ = "已完成"
    case .awaiting: class_ = "待处理"
    }
    if aggregate.providers > 1 {
      return "\(class_) · \(aggregate.providers) 个来源共 \(aggregate.entities) 项"
    }
    return "\(class_) · \(aggregate.entities) 项"
  }
}
