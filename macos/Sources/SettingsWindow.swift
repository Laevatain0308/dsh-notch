//
//  SettingsWindow.swift
//  DshNotch
//
//  Notch's own interface, which is not the island.
//
//  Everything the specs describe as happening "from Notch's own surface" happens
//  here: reviewing and revoking what the user allowed, clearing a refusal, asking
//  a program again, and the two facts a user needs when something says it cannot
//  find Notch — whether the overlay is running and where providers reach it.
//
//  It is a separate window because the island is a surface providers are shown
//  on, and a surface that also hosts configuration would be a surface a provider
//  could plausibly imitate. The visual language is shared; the space is not.
//

import AppKit
import ServiceManagement
import SwiftUI

/// The settings window, and the status item that opens it.
///
/// An accessory application has no menu bar of its own, so its interface is
/// reached from a status item — which is also the honest place to put "quit",
/// now that nothing else starts or stops this program.
@MainActor
final class SettingsWindowController: NSObject {
  private let service: NotchService
  private var window: NSWindow?
  private var statusItem: NSStatusItem?

  init(service: NotchService) {
    self.service = service
    super.init()
  }

  /// Put the status item up, which is the only way in and out of this program.
  func install() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(systemSymbolName: "capsule.portrait", accessibilityDescription: "Notch")
    item.button?.image?.isTemplate = true

    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "设置…", action: #selector(show), keyEquivalent: ","))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "退出 Notch", action: #selector(quit), keyEquivalent: "q"))
    for entry in menu.items where entry.action != nil { entry.target = self }
    item.menu = menu
    statusItem = item
  }

  /// Open the window, which the status item does and `--settings` does at launch.
  @objc func show() {
    if window == nil {
      let hosting = NSHostingController(rootView: SettingsView(service: service))
      let window = NSWindow(contentViewController: hosting)
      window.title = "Notch"
      window.styleMask = [.titled, .closable, .miniaturizable]
      window.isReleasedWhenClosed = false
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}

/// What the user can decide about Notch itself.
struct SettingsView: View {
  @ObservedObject var service: NotchService
  @State private var loginFailure: String?
  @State private var reconsiderRefusal: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        providers
        Divider()
        overlay
        Divider()
        startup
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520, height: 520)
    .background(NotchTokens.bodyBackground)
  }

  // MARK: - Who may speak

  private var providers: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("程序", "谁能在这里显示东西，以及你允许了什么。")

      if service.decisions.isEmpty {
        Text("还没有任何程序被允许过。一个程序第一次想显示东西时，这里会问你。")
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.5))
      }

      ForEach(service.decisions, id: \.id) { decision in
        record(decision)
      }
    }
  }

  private func record(_ decision: ConsentDesk.Decision) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Circle()
          .fill(decision.denied ? NotchTokens.redFail : NotchTokens.greenComplete)
          .frame(width: 6, height: 6)
        Text(decision.displayName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
        Spacer(minLength: 0)
        Text(decision.denied ? "已拒绝" : "已允许")
          .font(.system(size: 11))
          .foregroundStyle(decision.denied ? NotchTokens.redFail : NotchTokens.greenComplete)
      }
      Text(decision.path)
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white.opacity(0.4))
        .lineLimit(1)
        .truncationMode(.head)
      if !decision.classes.isEmpty {
        Text(decision.classes.map { ConsentPrompt.wording(for: $0) }.joined(separator: " · "))
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.7))
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 8) {
        if decision.denied {
          Button("允许它再问一次") {
            reconsiderRefusal = service.reconsider(decision.id) ? nil : Self.floorMessage(decision)
          }
          Button("删除这条记录") { service.clearDenial(decision.id) }
        } else {
          Button("撤销授权") { service.revoke(decision.id) }
        }
        Spacer(minLength: 0)
      }
      .buttonStyle(.link)
      .font(.system(size: 11))
      if reconsiderRefusal != nil, service.decisions.first(where: { $0.id == decision.id })?.denied == true {
        Text(reconsiderRefusal ?? "")
          .font(.system(size: 11))
          .foregroundStyle(NotchTokens.amber)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NotchTokens.fieldBackground))
  }

  /// Why a refusal cannot be reopened yet, said in terms of when rather than why.
  private static func floorMessage(_ decision: ConsentDesk.Decision) -> String {
    let elapsed = Int((Date().timeIntervalSince1970 * 1000 - Double(decision.decidedAt)) / 1000)
    let remaining = max(0, Limits.reRequestFloorMs / 1000 - elapsed)
    return "拒绝后 \(Limits.reRequestFloorMs / 60_000) 分钟内不能重新询问；还有约 \(remaining / 60) 分钟。"
  }

  // MARK: - This overlay

  private var overlay: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionTitle("这个 overlay", "它是不是在运行，以及别的程序该连到哪里。")
      HStack(spacing: 8) {
        Circle()
          .fill(service.listening ? NotchTokens.greenComplete : NotchTokens.redFail)
          .frame(width: 6, height: 6)
        Text(service.listening ? "正在监听" : "没有在监听")
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.85))
        Spacer(minLength: 0)
      }
      HStack(spacing: 8) {
        Text(service.address)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.white.opacity(0.6))
          .textSelection(.enabled)
        Button("拷贝") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(service.address, forType: .string)
        }
        .buttonStyle(.link)
        .font(.system(size: 11))
        Spacer(minLength: 0)
      }
      if let failure = service.failure {
        Text(failure)
          .font(.system(size: 11))
          .foregroundStyle(NotchTokens.redFail)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text("Notch 只由你启动。任何程序都不能启动它，也不能要求系统打开它。")
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.42))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Starting it

  private var startup: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionTitle("登录时启动", "让这个 overlay 在你登录后就在，而不用记着打开它。")
      Toggle("登录时启动 Notch", isOn: Binding(
        get: { SMAppService.mainApp.status == .enabled },
        set: { wanted in
          do {
            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginFailure = nil
          } catch {
            // A login item is the system's to grant, and a refusal is worth
            // reporting rather than silently reverting the switch.
            loginFailure = error.localizedDescription
          }
        }
      ))
      .toggleStyle(.switch)
      .font(.system(size: 12))
      .foregroundStyle(.white.opacity(0.85))

      if let loginFailure {
        Text("系统没有接受这个设置：\(loginFailure)")
          .font(.system(size: 11))
          .foregroundStyle(NotchTokens.amber)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func sectionTitle(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
      Text(detail)
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.45))
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
