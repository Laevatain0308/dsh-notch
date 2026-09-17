//
//  ConsentView.swift
//  DshNotch
//
//  The one decision the island asks on its own behalf.
//
//  A program wants to be allowed to show things. The user answers on the island,
//  as a decision, in the same motion as any other — but this one is Notch's, and
//  it is drawn so that it cannot be mistaken for a provider's:
//
//  - Every word on it comes from Notch. The program's own name for itself never
//    appears; what appears is the executable the operating system reported, which
//    is a fact rather than a claim.
//  - The classes are Notch's own sentences, from its own catalogue. A provider
//    supplies the request, never its wording.
//  - It occupies the region an expanded decision uses, and no entity is presented
//    there while it does — so there is nothing for a provider to overlap, cover,
//    or blend into. That is the structural half of "cannot be imitated": the rest
//    of it is this file, which reads no provider-supplied string at all.
//

import AppKit
import SwiftUI

/// The consent decision, as the island presents it.
struct ConsentView: View {
  let prompt: ConsentPrompt
  let allow: () -> Void
  let deny: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      program
      classes
      Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 12)
      choices
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  /// Notch's own voice, marked as its own.
  private var header: some View {
    HStack(spacing: 8) {
      // A mark provider content cannot produce: it is drawn here, from Notch's
      // own tokens, and it never takes text from anywhere.
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(NotchTokens.amber)
        .frame(width: 10, height: 10)
      Text("Notch")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(NotchTokens.amber)
      Text("有一个程序想显示信息")
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.55))
      Spacer(minLength: 0)
    }
    .padding(.bottom, 10)
  }

  /// The program, as the operating system reported it.
  private var program: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(prompt.program)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.middle)
      Text(prompt.path)
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white.opacity(0.42))
        .lineLimit(1)
        .truncationMode(.head)
      if let identifier = prompt.identifier {
        Text("签名 \(identifier)")
          .font(.system(size: 10))
          .foregroundStyle(.white.opacity(0.32))
      }
    }
  }

  /// What would be allowed, in Notch's words.
  private var classes: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(prompt.classes, id: \.rawValue) { behaviourClass in
        HStack(spacing: 8) {
          Circle()
            .fill(behaviourClass == .awaiting ? NotchTokens.deepSeekBlue : Color.white.opacity(0.35))
            .frame(width: 5, height: 5)
          Text(ConsentPrompt.wording(for: behaviourClass))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.82))
          Spacer(minLength: 0)
        }
      }
      // The adjudicative class is the one that can put a question in front of the
      // user, so it is called out rather than listed as one more thing to show.
      if prompt.asksToAsk {
        Text("它提出的问题会以你的名义出现在这里；不允许这一类，它就只能显示状态。")
          .font(.system(size: 11))
          .foregroundStyle(NotchTokens.deepSeekBlue.opacity(0.9))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 2)
      }
    }
    .padding(.top, 10)
  }

  private var choices: some View {
    HStack(spacing: 8) {
      Button(action: allow) {
        Text("允许")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.black)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 7)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NotchTokens.amber))
      }
      .buttonStyle(.plain)

      Button(action: deny) {
        Text("拒绝")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.white.opacity(0.85))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 7)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NotchTokens.badgeBackground))
      }
      .buttonStyle(.plain)

      Button(action: dismiss) {
        Text("稍后")
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.5))
          .padding(.vertical, 7)
          .padding(.horizontal, 10)
      }
      .buttonStyle(.plain)
    }
  }
}
