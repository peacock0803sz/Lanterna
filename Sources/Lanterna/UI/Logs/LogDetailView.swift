import AppKit
import SwiftUI

// MARK: - LogDetailView

/// One line in full: its level, date and time, category, where it was
/// written, the whole message, and the context it carried.
struct LogDetailView: View {

  // MARK: Internal

  let entry: Diagnostics.LogEntry
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Text(entry.message)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Message")
          fields
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.background)
  }

  /// The rows under the message: the launch and the source on every line,
  /// then the context keys in name order.
  static func fieldRows(for entry: Diagnostics.LogEntry) -> [(key: String, value: String)] {
    let launch = "\(entry.launch.stamp)\(entry.launch.isCurrent ? " (this launch)" : "") · #\(entry.sequence)"
    return [("launch", launch), ("source", entry.source)]
  }

  static func contextRows(for entry: Diagnostics.LogEntry) -> [(key: String, value: String)] {
    entry.context.sorted { $0.key < $1.key }.map { ($0.key, $0.value.displayText) }
  }

  // MARK: Private

  private var header: some View {
    HStack(spacing: 10) {
      LogLevelBadge(level: entry.level)
      Text(LogTimeText.full(entry.capturedAt))
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
      Text(entry.category.rawValue)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Button("Copy Entry") { Self.copy(LogExport.copyLine(entry)) }
        .controlSize(.small)
      Button("Copy Message") { Self.copy(entry.message) }
        .controlSize(.small)
      Divider()
        .frame(height: 16)
      Button(action: close) {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .keyboardShortcut(.cancelAction)
      .help("Close (esc)")
      .accessibilityLabel("Close detail")
    }
  }

  private var fields: some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(Self.fieldRows(for: entry), id: \.key) { row in
        FieldRow(key: row.key, value: row.value)
      }
      let context = Self.contextRows(for: entry)
      if !context.isEmpty {
        Text("Context")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .padding(.top, 6)
          .accessibilityAddTraits(.isHeader)
        ForEach(context, id: \.key) { row in
          FieldRow(key: row.key, value: row.value)
        }
      }
    }
  }

  private static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

}

// MARK: - FieldRow

/// One key and its value, the value selectable.
private struct FieldRow: View {
  let key: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text(key)
        .foregroundStyle(.secondary)
        .frame(width: 120, alignment: .leading)
      Text(value)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.system(size: 11, design: .monospaced))
    .accessibilityElement(children: .combine)
  }
}
