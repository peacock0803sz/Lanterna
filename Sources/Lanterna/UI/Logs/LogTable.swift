import SwiftUI

/// The log lines as a table: number, time, level, category and message,
/// one line per row however long the message is.
struct LogTable: View {

  // MARK: Internal

  @Bindable var state: LogWindowState

  var body: some View {
    Table(state.shownRows, selection: $state.selection) {
      TableColumn("#") { row in
        if let entry = row.entry {
          Text(String(entry.sequence))
            .font(Self.mono)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
          Image(systemName: "arrow.turn.down.right")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
      }
      .width(min: 32, ideal: 44, max: 90)
      TableColumn("Time") { row in
        if let entry = row.entry {
          Text(LogTimeText.clock(entry.capturedAt))
            .font(Self.mono)
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 86, ideal: 96, max: 140)
      TableColumn("Level") { row in
        if let entry = row.entry {
          LogLevelBadge(level: entry.level)
        }
      }
      .width(min: 52, ideal: 64, max: 90)
      TableColumn("Category") { row in
        if let entry = row.entry {
          Text(entry.category.rawValue)
            .font(Self.mono)
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 64, ideal: 96, max: 160)
      TableColumn("Message") { row in
        if let entry = row.entry {
          Text(entry.oneLineMessage)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(entry.message)
        } else {
          Text(Self.separatorText(row.launch))
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
        }
      }
    }
    .tableStyle(.inset(alternatesRowBackgrounds: true))
  }

  /// `This launch · …` for the run reading it, `Launch · …` for the rest.
  static func separatorText(_ launch: LaunchID) -> String {
    "\(launch.isCurrent ? "This launch" : "Launch") · \(launch.stamp)"
  }

  // MARK: Private

  private static let mono = Font.system(size: 11, design: .monospaced)

}
