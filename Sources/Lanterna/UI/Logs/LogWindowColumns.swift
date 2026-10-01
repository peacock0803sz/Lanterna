import SwiftUI

// MARK: - LogColumn

/// The table's fixed columns. Every field of a line can be one; the
/// context keys add columns of their own.
enum LogColumn: String, CaseIterable, Sendable {
  case launch
  case sequence
  case time
  case level
  case category
  case message
  case source

  // MARK: Internal

  /// The five a fresh window shows.
  static let defaults: Set<LogColumn> = [.sequence, .time, .level, .category, .message]

  var title: String {
    switch self {
    case .launch: "Launch"
    case .sequence: "#"
    case .time: "Time"
    case .level: "Level"
    case .category: "Category"
    case .message: "Message"
    case .source: "Source"
    }
  }

  /// What the table's own column menu keeps the column under.
  var customizationID: String {
    rawValue
  }

  var isShownByDefault: Bool {
    Self.defaults.contains(self)
  }
}

// MARK: - LogWindowState + columns

/// Choosing the table's columns. The choice only changes the table:
/// copying and exporting keep every field.
extension LogWindowState {

  /// How many columns show, fixed and context together.
  var shownColumnCount: Int {
    LogColumn.allCases.count(where: isShown) + contextColumns.count
  }

  /// The context keys the lines in range carry, with the ones already
  /// chosen, in name order.
  var availableContextKeys: [String] {
    var keys = Set(contextColumns)
    for row in rows {
      if let context = row.entry?.context {
        keys.formUnion(context.keys)
      }
    }
    return keys.sorted()
  }

  func isShown(_ column: LogColumn) -> Bool {
    switch columnCustomization[visibility: column.customizationID] {
    case .visible: true
    case .hidden: false
    default: column.isShownByDefault
    }
  }

  /// Whether the column can be taken away: never the last one showing.
  func canHide(_ column: LogColumn) -> Bool {
    !isShown(column) || shownColumnCount > 1
  }

  func setShown(_ column: LogColumn, _ shown: Bool) {
    guard shown || canHide(column) else { return }
    columnCustomization[visibility: column.customizationID] = shown ? .visible : .hidden
  }

  func isShownContext(_ key: String) -> Bool {
    contextColumns.contains(key)
  }

  func setShownContext(_ key: String, _ shown: Bool) {
    if shown {
      guard !contextColumns.contains(key) else { return }
      contextColumns = (contextColumns + [key]).sorted()
    } else {
      guard contextColumns.contains(key), shownColumnCount > 1 else { return }
      contextColumns.removeAll { $0 == key }
    }
  }

  /// Back to the five a fresh window shows, with no context columns.
  func resetColumns() {
    columnCustomization = TableColumnCustomization<LogRow>()
    contextColumns = []
  }

  /// Puts back a column if the table's own menu hid the last one.
  func keepOneColumnShown() {
    guard shownColumnCount == 0 else { return }
    columnCustomization[visibility: LogColumn.message.customizationID] = .visible
  }

}
