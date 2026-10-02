// MARK: - GroupingMode

/// How the switcher list groups its rows.
///
/// Mirrors the config file values (`"none"`, `"bySpace"`, `"manual"`).
enum GroupingMode: String, Sendable {
  /// One list, as before grouping existed.
  case none
  /// One group per Space, shown Spaces first.
  case bySpace
  /// Groups the user makes by assigning applications to them.
  case manual
}

// MARK: - SubgroupPlacement

/// Where one kind's parked section goes once the list is grouped.
///
/// Mirrors the config file values (`"endOfList"`, `"withinGroup"`).
enum SubgroupPlacement: String, Sendable {
  /// After every group, gathered from all of them.
  case endOfList
  /// After each group's own rows.
  case withinGroup
}

// MARK: - GroupingPolicy

/// How the list is grouped, as one value.
struct GroupingPolicy: Equatable, Sendable {

  // MARK: Internal

  var mode = GroupingMode.none
  /// Where each kind's parked section goes. A kind left out goes to the
  /// end of the list.
  var placements = [DisplaySubgroup: SubgroupPlacement]()

  /// Where one kind's section goes.
  func placement(of subgroup: DisplaySubgroup) -> SubgroupPlacement {
    placements[subgroup] ?? .endOfList
  }

}
