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

  /// What a group's heading says.
  struct GroupHeading: Hashable, Sendable {
    /// The group's number, drawn beside the title, when the group has one.
    let number: Int?
    let title: String
    let detail: String?
  }

  /// One line of the list.
  enum Block {
    /// The heading over one group of rows. `order` is the group's place.
    case groupHeading(GroupHeading, order: Int)
    /// The heading over one subgroup of special rows. With a group order
    /// it belongs to that group and draws indented under it; without one
    /// it draws after every group.
    case subgroupHeading(DisplaySubgroup, group: Int?)
    /// One row; `isInSubgroup` draws it dimmed, under a subgroup heading.
    case row(WindowItem, isInSubgroup: Bool)

    // MARK: Internal

    /// Identity for drawing. A row is identified by its own identity, so
    /// scrolling to a chosen row by that identity finds it.
    var key: AnyHashable {
      switch self {
      case .groupHeading(_, let order):
        AnyHashable(HeadingKey(subgroup: nil, group: order))
      case .subgroupHeading(let subgroup, let group):
        AnyHashable(HeadingKey(subgroup: subgroup, group: group))
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

  /// How many lines the list draws: every row and every heading, or the
  /// one line saying there is nothing to show. The list gives each one at
  /// least a row's height.
  var drawnRowCount: Int {
    max(blocks.count, 1)
  }

  /// How many window rows the list draws. Headings are not windows.
  var windowCount: Int {
    rows.count(where: { !$0.isWindowless })
  }

  /// The list for these rows under this query.
  ///
  /// The scope keeps one owner's rows when one is named and exclusions
  /// drop theirs, both before matching, so a row either one leaves out
  /// never comes back through a query. Then the display modes place each
  /// row, then each section is ranked on its own. The remembered row moves
  /// to the front of whichever section it landed in, so parking and hiding
  /// stand for it as for any other row. Grouping comes last and keeps each
  /// section's order within every group.
  static func make(
    rows: [WindowItem],
    modes: DisplayModes,
    query: String,
    exclusions: [ExclusionRule] = [],
    fuzzy: Bool = false,
    ordering: SearchOrdering = .mru,
    memory: WindowItem.Identifier? = nil,
    owner: pid_t? = nil,
    grouping: GroupingPolicy = GroupingPolicy()
  ) -> PanelLayout {
    let scoped = owner.map { owner in rows.filter { $0.ownerProcessIdentifier == owner } } ?? rows
    var (ordinary, subgroups) = DisplayModes.sections(
      of: scoped,
      modes: grouping.mode == .bySpace ? modes.parkingNothingByOtherSpace : modes,
      query: query,
      exclusions: exclusions,
      fuzzy: fuzzy,
      ordering: ordering
    )
    if grouping.mode == .bySpace {
      parkApplicationRows(ordinary: &ordinary, subgroups: &subgroups)
    }
    if let memory {
      moveToFront(memory, ordinary: &ordinary, subgroups: &subgroups)
    }
    guard grouping.mode != .none else {
      return PanelLayout(blocks: flat(ordinary: ordinary, subgroups: subgroups))
    }
    let grouper = Grouper(rows: ordinary + subgroups.flatMap(\.1), policy: grouping)
    let placed = SectionPlacement(grouping: grouping, subgroups: subgroups)
    let groups = grouper.orders(of: ordinary + placed.within.flatMap(\.1))
    guard groups.count > 1 else {
      return PanelLayout(blocks: flat(ordinary: ordinary, subgroups: subgroups))
    }
    var blocks = [Block]()
    for order in groups {
      blocks.append(.groupHeading(grouper.heading(of: order), order: order))
      blocks += ordinary.filter { grouper.order(of: $0) == order }.map { Block.row($0, isInSubgroup: false) }
      for (subgroup, members) in placed.within {
        let inGroup = members.filter { grouper.order(of: $0) == order }
        guard !inGroup.isEmpty else { continue }
        blocks.append(.subgroupHeading(subgroup, group: order))
        blocks += inGroup.map { Block.row($0, isInSubgroup: true) }
      }
    }
    for (subgroup, members) in placed.atEnd {
      blocks.append(.subgroupHeading(subgroup, group: nil))
      blocks += members.map { Block.row($0, isInSubgroup: true) }
    }
    return PanelLayout(blocks: blocks)
  }

  // MARK: Private

  private struct HeadingKey: Hashable {
    let subgroup: DisplaySubgroup?
    let group: Int?
  }

  /// Which group each row joins, and what the group is called.
  private struct Grouper {

    // MARK: Lifecycle

    init(rows: [WindowItem], policy: GroupingPolicy) {
      self.policy = policy
      var headings = [Int: GroupHeading]()
      if policy.mode == .manual {
        var names = [Int: [String]]()
        for row in rows {
          let group = policy.group(forBundleID: row.bundleIdentifier)
          if names[group, default: []].contains(row.appName) == false {
            names[group, default: []].append(row.appName)
          }
        }
        for (group, appNames) in names {
          headings[group] = Self.manualHeading(group, policy: policy, appNames: appNames)
        }
      } else {
        for row in rows {
          if let group = row.spaceGroup, headings[group.order] == nil {
            headings[group.order] = GroupHeading(number: nil, title: group.title, detail: group.detail)
          }
        }
      }
      self.headings = headings
      // A row whose Space is not known joins the first group drawn:
      // missing information never sends a row away.
      fallback = headings.keys.min() ?? 0
    }

    // MARK: Internal

    func order(of row: WindowItem) -> Int {
      if policy.mode == .manual {
        return policy.group(forBundleID: row.bundleIdentifier)
      }
      return row.spaceGroup?.order ?? fallback
    }

    /// The groups these rows fill, in drawing order.
    func orders(of rows: [WindowItem]) -> [Int] {
      Set(rows.map(order(of:))).sorted()
    }

    func heading(of order: Int) -> GroupHeading {
      headings[order] ?? GroupHeading(number: nil, title: "Desktop", detail: nil)
    }

    // MARK: Private

    private let policy: GroupingPolicy
    private let headings: [Int: GroupHeading]
    private let fallback: Int

    /// A manual group's heading in the chosen style. The number style
    /// says the number once, in the title; the others draw it beside.
    private static func manualHeading(_ group: Int, policy: GroupingPolicy, appNames: [String]) -> GroupHeading {
      switch policy.headingStyle {
      case .number:
        GroupHeading(number: nil, title: "Group \(group)", detail: nil)
      case .name:
        GroupHeading(number: group, title: policy.name(of: group) ?? "Group \(group)", detail: nil)
      case .appNames:
        GroupHeading(number: group, title: appNames.joined(separator: ", "), detail: nil)
      }
    }

  }

  /// The parked sections split by where each one goes.
  private struct SectionPlacement {
    init(grouping: GroupingPolicy, subgroups: [(DisplaySubgroup, [WindowItem])]) {
      within = subgroups.filter { subgroup, _ in Self.goesWithin(subgroup, grouping: grouping) }
      atEnd = subgroups.filter { subgroup, _ in !Self.goesWithin(subgroup, grouping: grouping) }
    }

    let within: [(DisplaySubgroup, [WindowItem])]
    let atEnd: [(DisplaySubgroup, [WindowItem])]

    /// Grouping by Space keeps rows with no window after every group:
    /// they are on no Space to be grouped under.
    private static func goesWithin(_ subgroup: DisplaySubgroup, grouping: GroupingPolicy) -> Bool {
      if grouping.mode == .bySpace, subgroup == .windowlessApp {
        return false
      }
      return grouping.placement(of: subgroup) == .withinGroup
    }
  }

  /// One list: the ordinary rows, then each subgroup under its heading.
  private static func flat(ordinary: [WindowItem], subgroups: [(DisplaySubgroup, [WindowItem])]) -> [Block] {
    var blocks = ordinary.map { Block.row($0, isInSubgroup: false) }
    for (subgroup, members) in subgroups {
      blocks.append(.subgroupHeading(subgroup, group: nil))
      blocks += members.map { Block.row($0, isInSubgroup: true) }
    }
    return blocks
  }

  /// Moves rows with no window out of the ordinary rows into their own
  /// section, ahead of any rows already there, keeping their order.
  private static func parkApplicationRows(
    ordinary: inout [WindowItem],
    subgroups: inout [(DisplaySubgroup, [WindowItem])]
  ) {
    let applications = ordinary.filter(\.isWindowless)
    guard !applications.isEmpty else { return }
    ordinary.removeAll(where: \.isWindowless)
    if let index = subgroups.firstIndex(where: { $0.0 == .windowlessApp }) {
      subgroups[index].1 = applications + subgroups[index].1
    } else {
      subgroups.append((.windowlessApp, applications))
    }
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

// MARK: - DisplayModes + grouping by Space

extension DisplayModes {
  /// The modes with other-Space rows no longer parked: grouping by Space
  /// files them under their own Space instead. Hiding them still hides.
  fileprivate var parkingNothingByOtherSpace: DisplayModes {
    var modes = self
    if modes.otherSpace == .separateAtBottom {
      modes.otherSpace = .show
    }
    return modes
  }
}
