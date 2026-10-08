/// The shortcut memory: one chosen row per query, kept while running.
///
/// A value with no system behind it: recording and lookup are calculations
/// over the table, so every row of the contract below can be held to
/// without a panel. Kept by `PanelFilter` across appearances, unlike
/// `FilterState`, which starts over with every appearance. Gating a hit
/// against the shown list and the current matcher belongs to the keeper,
/// not here: this only answers what was recorded.
struct ShortcutMemory: Equatable, Sendable {

  // MARK: Internal

  /// The recorded choices, keyed by the whole query folded to lowercase.
  /// A newer commit overwrites an older one under the same key.
  private(set) var entries = [String: WindowItem.Identifier]()
  /// How many characters (`Character`) of a query are covered. Longer
  /// queries are neither recorded nor applied. 0 means off and behaves
  /// as an empty table.
  var maxLength: Int
  /// How many queries are remembered at most. Past it the longest-ago
  /// recorded query leaves first. Apart from `maxLength`, which caps the
  /// length of one query rather than the number of them.
  var maxEntries = 256

  /// Records one commit. Empty queries, queries longer than the cap, and
  /// a zero cap record nothing. Recording again moves the query newest,
  /// so a hit often used is not the one that leaves.
  mutating func record(query: String, id: WindowItem.Identifier) {
    guard inScope(query) else { return }
    let key = query.lowercased()
    entries[key] = id
    order.removeAll { $0 == key }
    order.append(key)
    while order.count > maxEntries {
      entries.removeValue(forKey: order.removeFirst())
    }
  }

  /// The recorded row for one query, if any. Empty queries, queries
  /// longer than the cap, and a zero cap answer nothing.
  func lookup(query: String) -> WindowItem.Identifier? {
    guard inScope(query) else { return nil }
    return entries[query.lowercased()]
  }

  // MARK: Private

  /// The recorded keys oldest first. The table itself keeps no order, so
  /// the count cap is aged on this side.
  private var order = [String]()

  /// Whether a query takes part at all: non-empty and within the cap.
  private func inScope(_ query: String) -> Bool {
    !query.isEmpty && query.count <= maxLength
  }

}
