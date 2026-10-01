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
    Table(state.shownRows, selection: $state.selection, columnCustomization: $state.columnCustomization) {
      TableColumn(LogColumn.launch.title) { row in
        tracked(row, Text(row.launch.stamp).font(Self.mono).foregroundStyle(.secondary))
      }
      .width(min: 140, ideal: 170, max: 220)
      .customizationID(LogColumn.launch.customizationID)
      .defaultVisibility(.hidden)
      TableColumn(LogColumn.sequence.title) { row in
        tracked(row, sequenceCell(row))
      }
      .width(min: 32, ideal: 44, max: 90)
      .customizationID(LogColumn.sequence.customizationID)
      TableColumn(LogColumn.time.title) { row in
        tracked(row, Text(row.entry.map { LogTimeText.clock($0.capturedAt) } ?? "").font(Self.mono).foregroundStyle(.secondary))
      }
      .width(min: 86, ideal: 96, max: 140)
      .customizationID(LogColumn.time.customizationID)
      TableColumn(LogColumn.level.title) { row in
        if let entry = row.entry {
          LogLevelBadge(level: entry.level)
        }
      }
      .width(min: 52, ideal: 64, max: 90)
      .customizationID(LogColumn.level.customizationID)
      TableColumn(LogColumn.category.title) { row in
        Text(row.entry?.category.rawValue ?? "").font(Self.mono).foregroundStyle(.secondary)
      }
      .width(min: 64, ideal: 96, max: 160)
      .customizationID(LogColumn.category.customizationID)
      TableColumn(LogColumn.message.title) { row in
        tracked(row, messageCell(row))
      }
      .customizationID(LogColumn.message.customizationID)
      TableColumn(LogColumn.source.title) { row in
        Text(row.entry?.source ?? "").font(Self.mono).foregroundStyle(.secondary).lineLimit(1)
      }
      .width(min: 90, ideal: 160, max: 320)
      .customizationID(LogColumn.source.customizationID)
      .defaultVisibility(.hidden)
      TableColumnForEach(state.contextColumns, id: \.self) { key in
        TableColumn(key) { row in
          Text(row.entry?.context[key]?.displayText ?? "").font(Self.mono).lineLimit(1)
        }
        .width(min: 50, ideal: 100, max: 320)
        .customizationID("context.\(key)")
      }
    }
    .tableStyle(.inset(alternatesRowBackgrounds: true))
    .onChange(of: state.columnCustomization) { state.keepOneColumnShown() }
    .contextMenu(forSelectionType: LogRow.ID.self) { ids in
      Button("Copy") { state.copy(rowsWithIDs: ids) }
        .disabled(!state.shownRows.contains { ids.contains($0.id) && !$0.isSeparator })
      Divider()
      LogColumnsMenu(state: state)
    }
  }

  /// Notes the row on and off the screen. Several columns note it, so the
  /// tail can be followed whichever of them is showing.
  private func tracked(_ row: LogRow, _ content: some View) -> some View {
    content
      .onAppear { visibility.appeared(row.id) }
      .onDisappear { visibility.disappeared(row.id) }
  }

  @ViewBuilder
  private func sequenceCell(_ row: LogRow) -> some View {
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

  /// Counted per cell: a row is on screen while any of its cells is.
  func appeared(_ id: LogRow.ID) {
    onScreen[id, default: 0] += 1
  }

  func disappeared(_ id: LogRow.ID) {
    guard let count = onScreen[id] else { return }
    onScreen[id] = count > 1 ? count - 1 : nil
  }

  func isOnScreen(_ id: LogRow.ID) -> Bool {
    onScreen[id] != nil
  }

  // MARK: Private

  private var onScreen = [LogRow.ID: Int]()

}
