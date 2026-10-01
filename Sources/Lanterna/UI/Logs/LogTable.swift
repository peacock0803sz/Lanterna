import SwiftUI

// MARK: - LogTable

/// The log lines as a table: number, time, level, category and message,
/// one line per row however long the message is.
///
/// Follows new lines only while the last row is on screen, so a reader
/// partway up keeps their place.
struct LogTable: View {

  // MARK: Internal

  @Bindable var state: LogWindowState

  var body: some View {
    ScrollViewReader { proxy in
      table
        .onAppear {
          if let last = state.shownRows.last?.id {
            proxy.scrollTo(last, anchor: .bottom)
          }
        }
        .onChange(of: state.shownRows.last?.id) { previous, last in
          guard
            !state.isPaused,
            let previous,
            let last,
            visibility.isOnScreen(previous)
          else { return }
          proxy.scrollTo(last, anchor: .bottom)
        }
    }
  }

  /// `This launch · …` for the run reading it, `Launch · …` for the rest.
  static func separatorText(_ launch: LaunchID) -> String {
    "\(launch.isCurrent ? "This launch" : "Launch") · \(launch.stamp)"
  }

  // MARK: Private

  private static let mono = Font.system(size: 11, design: .monospaced)

  @State private var visibility = RowVisibility()

  private var table: some View {
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
        messageCell(row)
          .onAppear { visibility.appeared(row.id) }
          .onDisappear { visibility.disappeared(row.id) }
      }
    }
    .tableStyle(.inset(alternatesRowBackgrounds: true))
    .contextMenu(forSelectionType: LogRow.ID.self) { ids in
      Button("Copy") { state.copy(rowsWithIDs: ids) }
        .disabled(!state.shownRows.contains { ids.contains($0.id) && !$0.isSeparator })
    }
  }

  @ViewBuilder
  private func messageCell(_ row: LogRow) -> some View {
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

// MARK: - RowVisibility

/// Which rows the table has on screen, kept outside observation so that
/// scrolling does not redraw the table.
@MainActor
final class RowVisibility {

  // MARK: Internal

  func appeared(_ id: LogRow.ID) {
    onScreen.insert(id)
  }

  func disappeared(_ id: LogRow.ID) {
    onScreen.remove(id)
  }

  func isOnScreen(_ id: LogRow.ID) -> Bool {
    onScreen.contains(id)
  }

  // MARK: Private

  private var onScreen = Set<LogRow.ID>()

}
