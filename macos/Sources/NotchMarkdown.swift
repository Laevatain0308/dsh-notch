import AppKit
import SwiftUI

/// Block Markdown using DSH body type: 14pt system, 12pt SF Mono.
enum NotchMarkdown {
  static let bodySize: CGFloat = 14
  static let headingSize: CGFloat = 17
  static let codeSize: CGFloat = 12
}

struct NotchMarkdownView: View {
  let source: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var blocks: [Block] { Block.parse(source) }

  @ViewBuilder
  private func blockView(_ block: Block) -> some View {
    switch block {
    case .heading(let level, let text):
      inline(text)
        .font(.system(size: level <= 1 ? 18 : level == 2 ? 16 : 15, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.top, level <= 2 ? 8 : 4)
    case .paragraph(let text):
      inline(text)
        .font(.system(size: NotchMarkdown.bodySize))
        .foregroundStyle(Color.white.opacity(0.9))
        .lineSpacing(6)
    case .list(let items, let ordered):
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
          HStack(alignment: .top, spacing: 8) {
            Text(ordered ? "\(i + 1)." : "•")
              .font(.system(size: NotchMarkdown.bodySize, weight: .medium))
              .foregroundStyle(Color.white.opacity(0.55))
              .frame(width: 18, alignment: .trailing)
            inline(item)
              .font(.system(size: NotchMarkdown.bodySize))
              .foregroundStyle(Color.white.opacity(0.9))
              .lineSpacing(5)
          }
        }
      }
    case .table(let headers, let rows):
      table(headers: headers, rows: rows)
    case .code(let text):
      Text(text)
        .font(.system(size: NotchMarkdown.codeSize, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.07))
        )
    case .quote(let text):
      inline(text)
        .font(.system(size: NotchMarkdown.bodySize))
        .foregroundStyle(Color.white.opacity(0.7))
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
          Rectangle().fill(Color.white.opacity(0.28)).frame(width: 2)
        }
    case .rule:
      Divider().overlay(Color.white.opacity(0.18))
    }
  }

  private func inline(_ markdown: String) -> Text {
    var options = AttributedString.MarkdownParsingOptions()
    options.interpretedSyntax = .inlineOnlyPreservingWhitespace
    options.failurePolicy = .returnPartiallyParsedIfPossible
    if let parsed = try? AttributedString(markdown: markdown, options: options) {
      var styled = parsed
      for run in styled.runs {
        if run.inlinePresentationIntent?.contains(.code) == true {
          styled[run.range].font = .system(size: NotchMarkdown.codeSize, design: .monospaced)
          styled[run.range].backgroundColor = NSColor.white.withAlphaComponent(0.1)
        }
      }
      return Text(styled)
    }
    return Text(markdown)
  }

  private func table(headers: [String], rows: [[String]]) -> some View {
    let columns = max(headers.count, rows.map(\.count).max() ?? 0)
    return VStack(alignment: .leading, spacing: 0) {
      if !headers.isEmpty {
        tableRow(cells: headers, header: true, columns: columns)
        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
      }
      ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
        tableRow(cells: row, header: false, columns: columns)
        if i < rows.count - 1 {
          Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
      }
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.white.opacity(0.16), lineWidth: 1)
    )
  }

  private func tableRow(cells: [String], header: Bool, columns: Int) -> some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(0..<columns, id: \.self) { i in
        let cell = i < cells.count ? cells[i] : ""
        Text(cell)
          .font(.system(size: 12, weight: header ? .semibold : .regular))
          .foregroundStyle(Color.white.opacity(header ? 0.95 : 0.82))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 5)
          .padding(.horizontal, 6)
        if i < columns - 1 {
          Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
        }
      }
    }
  }
}

private enum Block {
  case heading(Int, String)
  case paragraph(String)
  case list([String], Bool)
  case table([String], [[String]])
  case code(String)
  case quote(String)
  case rule

  static func parse(_ source: String) -> [Block] {
    let lines = source.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var blocks: [Block] = []
    var i = 0
    while i < lines.count {
      let raw = lines[i]
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { i += 1; continue }
      if line.hasPrefix("```") {
        i += 1
        var body: [String] = []
        while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
          body.append(lines[i])
          i += 1
        }
        if i < lines.count { i += 1 }
        blocks.append(.code(body.joined(separator: "\n")))
        continue
      }
      if line == "---" || line == "***" || line == "___" {
        blocks.append(.rule)
        i += 1
        continue
      }
      if let heading = heading(line) {
        blocks.append(heading)
        i += 1
        continue
      }
      if line.hasPrefix("|") && i + 1 < lines.count, isTableDivider(lines[i + 1]) {
        let headers = cells(line)
        i += 2
        var rows: [[String]] = []
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
          rows.append(cells(lines[i]))
          i += 1
        }
        blocks.append(.table(headers, rows))
        continue
      }
      if line.hasPrefix("> ") || line == ">" {
        var quoted: [String] = []
        while i < lines.count {
          let t = lines[i].trimmingCharacters(in: .whitespaces)
          if t.hasPrefix("> ") { quoted.append(String(t.dropFirst(2))) }
          else if t == ">" { quoted.append("") }
          else { break }
          i += 1
        }
        blocks.append(.quote(quoted.joined(separator: "\n")))
        continue
      }
      if isBullet(line) || isOrdered(line) {
        let ordered = isOrdered(line)
        var items: [String] = []
        while i < lines.count {
          let t = lines[i].trimmingCharacters(in: .whitespaces)
          if ordered, let item = orderedItem(t) { items.append(item) }
          else if !ordered, let item = bulletItem(t) { items.append(item) }
          else { break }
          i += 1
        }
        blocks.append(.list(items, ordered))
        continue
      }
      var para: [String] = [line]
      i += 1
      while i < lines.count {
        let t = lines[i].trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("|") || t.hasPrefix("```") || t.hasPrefix("> ") || isBullet(t) || isOrdered(t) || t == "---" { break }
        para.append(t)
        i += 1
      }
      blocks.append(.paragraph(para.joined(separator: " ")))
    }
    return blocks
  }

  private static func heading(_ line: String) -> Block? {
    guard line.hasPrefix("#") else { return nil }
    var level = 0
    for ch in line {
      if ch == "#" { level += 1 } else { break }
    }
    guard level > 0, level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else { return nil }
    return .heading(level, String(line.dropFirst(level + 1)))
  }

  private static func isTableDivider(_ line: String) -> Bool {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("|") else { return false }
    return t.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").isEmpty
  }

  private static func cells(_ line: String) -> [String] {
    var parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    if parts.first == "" { parts.removeFirst() }
    if parts.last == "" { parts.removeLast() }
    return parts
  }

  private static func isBullet(_ line: String) -> Bool {
    line.hasPrefix("- ") || line.hasPrefix("* ")
  }

  private static func bulletItem(_ line: String) -> String? {
    if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
    if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
    return nil
  }

  private static func isOrdered(_ line: String) -> Bool {
    orderedItem(line) != nil
  }

  private static func orderedItem(_ line: String) -> String? {
    guard let dot = line.firstIndex(of: ".") else { return nil }
    let n = line[..<dot]
    guard !n.isEmpty, n.allSatisfy(\.isNumber) else { return nil }
    let rest = line[line.index(after: dot)...]
    guard rest.first == " " else { return nil }
    return String(rest.dropFirst())
  }
}
