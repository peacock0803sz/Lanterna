import Foundation

// MARK: - PanelLayout

/// The switcher list as it draws: headings and rows, in drawing order.
///
/// The filter, the view and the panel height each used to split the rows
/// on their own and agreed only because they passed the same arguments.
/// They now all read this one value, so a rule about where a row goes is
/// written once and cannot be applied differently in one of the three.
struct PanelLayout {

  // MARK: Internal

  /// One line of the list.
  enum Block {
    /// The heading over one subgroup of special rows. `nested` draws it
    /// indented, under a group of its own.
    case subgroupHeading(DisplaySubgroup, nested: Bool)
    /// One row; `isInSubgroup` draws it dimmed, under a subgroup heading.
    case row(WindowItem, isInSubgroup: Bool)

    // MARK: Internal

    /// Identity for drawing. A row is identified by its own identity, so
    /// scrolling to a chosen row by that identity finds it.
    var key: AnyHashable {
      switch self {
      case .subgroupHeading(let subgroup, let nested):
        AnyHashable(HeadingKey(subgroup: subgroup, nested: nested))
      case .row(let window, _):
        AnyHashable(window.id)
      }
    }
  }

  let blocks: [Block]

  /// The rows in drawing order, which is the order the arrows step through.
  var rows: [WindowItem] {
    blocks.compactMap { block in
      if case .row(let window, _) = block {
        window
      } else {
        nil
      }
    }
  }

  var rowIDs: [WindowItem.Identifier] {
    rows.map(\.id)
  }

  /// How many lines the list draws: every row and every heading. The list
  /// gives each one at least a row's height.
  var drawnRowCount: Int {
    blocks.count
  }

  /// How many window rows the list draws. Headings are not windows.
  var windowCount: Int {
    rows.count(where: { !$0.isWindowless })
  }

  /// The list for these rows under this query.
  ///
  /// Exclusions run first, then matching, then the display modes place
  /// each row, then each section is ranked on its own. The remembered row
  /// moves to the front of whichever section it landed in, so parking and
  /// hiding stand for it as for any other row.
  static func make(
    rows: [WindowItem],
    modes: DisplayModes,
    query: String,
    exclusions: [ExclusionRule] = [],
    fuzzy: Bool = false,
    ordering: SearchOrdering = .mru,
    memory: WindowItem.Identifier? = nil
  ) -> PanelLayout {
    var (ordinary, subgroups) = DisplayModes.sections(
      of: rows,
      modes: modes,
      query: query,
      exclusions: exclusions,
      fuzzy: fuzzy,
      ordering: ordering
    )
    if let memory {
      moveToFront(memory, ordinary: &ordinary, subgroups: &subgroups)
    }
    var blocks = ordinary.map { Block.row($0, isInSubgroup: false) }
    for (subgroup, members) in subgroups {
      blocks.append(.subgroupHeading(subgroup, nested: false))
      blocks += members.map { Block.row($0, isInSubgroup: true) }
    }
    return PanelLayout(blocks: blocks)
  }

  // MARK: Private

  private struct HeadingKey: Hashable {
    let subgroup: DisplaySubgroup
    let nested: Bool
  }

  /// Moves the remembered row to the front of its own section, leaving
  /// every other row where the ranking put it.
  private static func moveToFront(
    _ remembered: WindowItem.Identifier,
    ordinary: inout [WindowItem],
    subgroups: inout [(DisplaySubgroup, [WindowItem])]
  ) {
    if let index = ordinary.firstIndex(where: { $0.id == remembered }) {
      ordinary.insert(ordinary.remove(at: index), at: 0)
      return
    }
    for section in subgroups.indices {
      if let index = subgroups[section].1.firstIndex(where: { $0.id == remembered }) {
        subgroups[section].1.insert(subgroups[section].1.remove(at: index), at: 0)
        return
      }
    }
  }

}
