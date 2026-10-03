// MARK: - RowKey

/// One hand-arranged row, named by what survives a restart.
///
/// A window-server id names a row exactly while it lives and means
/// nothing after a restart, so an override kept across launches names
/// its rows by bundle identifier and title instead. The match is
/// best-effort: a row whose application or title changed falls back to
/// the order it would have had without any override.
struct RowKey: Hashable, Sendable {
  /// The owning application's bundle identifier, lowercased, or the
  /// display name when the identifier is missing.
  let owner: String
  /// The window title exactly as reported.
  let title: String
}

// MARK: - RowOrderEntry

/// One row-order entry as spelled in the config file: the manual group
/// number with its row keys in order.
struct RowOrderEntry: Hashable, Sendable {
  /// The manual group number, 1 through 9.
  let group: Int
  /// The row keys in order. Each key spells the owner, a newline, then
  /// the title.
  let keys: [String]
}

// MARK: - ManualRowOrder

/// Hand-arranged row orders by manual group, as overrides over the
/// order rows would otherwise draw in.
///
/// The order applies within one group only and never crosses a group
/// boundary. Rows the override does not name keep their places after
/// the named ones, so a new window neither vanishes nor scrambles what
/// was arranged.
struct ManualRowOrder: Equatable, Sendable {

  // MARK: Lifecycle

  init(groups: [Int: [RowKey]]) {
    self.groups = groups
  }

  /// Builds an override from file entries. Later entries for a group
  /// already named are left out by the reader, so the first entry wins.
  init(entries: [RowOrderEntry]) {
    var groups = [Int: [RowKey]]()
    for entry in entries {
      groups[entry.group] = entry.keys.compactMap { Self.key(from: $0) }
    }
    self.groups = groups
  }

  // MARK: Internal

  /// No overrides: every row draws where it otherwise would.
  static let none = ManualRowOrder(groups: [:])

  /// The row key for one row.
  static func key(for window: WindowItem) -> RowKey {
    RowKey(
      owner: (window.bundleIdentifier ?? window.appName).lowercased(),
      title: window.windowTitle
    )
  }

  /// The stored keys for one group, in order, or nothing when the group
  /// has no override.
  func keys(forGroup group: Int) -> [RowKey]? {
    groups[group]
  }

  /// Lays rows out with one group's override applied: the named rows
  /// first in the stored order, then every unnamed row where it stood.
  /// Names matching nothing are ignored.
  func applying(keys: [RowKey], to rows: [WindowItem]) -> [WindowItem] {
    var remaining = rows
    var arranged = [WindowItem]()
    arranged.reserveCapacity(rows.count)
    for key in keys {
      guard let index = remaining.firstIndex(where: { Self.key(for: $0) == key }) else { continue }
      arranged.append(remaining.remove(at: index))
    }
    return arranged + remaining
  }

  // MARK: Private

  private var groups: [Int: [RowKey]]

  /// Reads one stored key back apart: the owner, a newline, then the
  /// title. A key with no newline names nothing.
  private static func key(from stored: String) -> RowKey? {
    guard let breakIndex = stored.firstIndex(of: "\n") else { return nil }
    let owner = String(stored[..<breakIndex])
    let title = String(stored[stored.index(after: breakIndex)...])
    guard !owner.isEmpty, !title.isEmpty else { return nil }
    return RowKey(owner: owner, title: title)
  }

}
