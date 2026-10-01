import SwiftUI

// MARK: - LogLaunchSection

/// One launch group in the table, oldest first.
struct LogLaunchSection: Equatable {
  var launchID: String?
  var isCurrent: Bool
  var startMilliseconds: Int64
  var rows: [DiagnosticRow]
}

// MARK: - LogLevelBadge

/// Colored severity token, readable in both appearances.
struct LogLevelBadge: View {

  // MARK: Internal

  var level: String

  var body: some View {
    Text(level.uppercased())
      .font(.caption.monospaced())
      .fontWeight(.semibold)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(badgeColor.opacity(0.18))
      .foregroundStyle(badgeColor)
      .clipShape(Capsule())
      .accessibilityLabel("Level \(level)")
  }

  // MARK: Private

  private var badgeColor: Color {
    switch level.lowercased() {
    case "error":
      .red
    case "warning":
      .orange
    case "debug":
      .secondary
    default:
      .blue
    }
  }

}

// MARK: - LogTableView

/// Five-column log list with launch separators.
///
/// Columns stay aligned through fixed leading widths and one flexible
/// message column. Long messages wrap inside their row without moving
/// neighbours, and selection follows the row rather than the text.
struct LogTableView: View {

  // MARK: Internal

  var sections: [LogLaunchSection]
  @Binding var selection: Set<String>

  var autoScroll: Bool
  var jumpTargetID: String?

  var body: some View {
    ScrollViewReader { proxy in
      List(selection: $selection) {
        header
        ForEach(sections.indices, id: \.self) { index in
          Section(header: separator(for: sections[index])) {
            ForEach(sections[index].rows, id: \.rowID) { row in
              rowView(for: row)
                .tag(row.rowID)
                .id(row.rowID)
            }
          }
        }
      }
      .listStyle(.plain)
      .onChange(of: lastRowID) { _, next in
        guard autoScroll, let next else { return }
        withAnimation(.none) {
          proxy.scrollTo(next, anchor: .bottom)
        }
      }
      .onChange(of: jumpTargetID) { _, next in
        guard let next else { return }
        withAnimation(.none) {
          proxy.scrollTo(next, anchor: .center)
        }
      }
    }
    .accessibilityLabel("Log entries")
  }

  // MARK: Private

  private var header: some View {
    HStack(spacing: 8) {
      Text("#")
        .frame(width: 48, alignment: .trailing)
      Text("Time")
        .frame(width: 96, alignment: .leading)
      Text("Level")
        .frame(width: 68, alignment: .leading)
      Text("Category")
        .frame(width: 88, alignment: .leading)
      Text("Message")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .accessibilityLabel("Log columns: number, time, level, category, message")
  }

  private var lastRowID: String? {
    sections.last?.rows.last?.rowID
  }

  private func separator(for section: LogLaunchSection) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(separatorTitle(for: section))
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
      if section.isCurrent, let first = section.rows.first {
        Text("#\(first.sequence) onward")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(separatorTitle(for: section))
  }

  private func separatorTitle(for section: LogLaunchSection) -> String {
    let stamp = LogExport.fullTime(milliseconds: section.startMilliseconds).prefix(19)
    if section.isCurrent {
      return "This launch · \(stamp)"
    }
    return "Launch · \(stamp)"
  }

  private func rowView(for row: DiagnosticRow) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text("#\(row.sequence)")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 48, alignment: .trailing)
      Text(LogExport.displayTime(milliseconds: row.recordedAtMilliseconds))
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 96, alignment: .leading)
      LogLevelBadge(level: row.level)
        .frame(width: 68, alignment: .leading)
      Text(row.category ?? "—")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 88, alignment: .leading)
      Text(row.message)
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .padding(.vertical, 1)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("#\(row.sequence) \(row.level) \(row.category ?? "no category") \(row.message)")
  }

}

// MARK: - DiagnosticRowID

extension DiagnosticRow {
  /// Stable across launches: the launch plus the per-launch number.
  var rowID: String {
    "\(launchID ?? "current")-\(sequence)-\(recordedAtMilliseconds)"
  }
}
