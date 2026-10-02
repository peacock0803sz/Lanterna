import Foundation

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

// MARK: - GroupHeadingStyle

/// What a manual group's heading says.
///
/// Mirrors the config file values (`"number"`, `"name"`, `"appNames"`).
enum GroupHeadingStyle: String, Sendable {
  /// The group's number alone.
  case number
  /// The name given to the group, or its number when it has none.
  case name
  /// The names of the applications listed in the group.
  case appNames
}

// MARK: - GroupAssignment

/// One application assigned to one manual group, by bundle identifier.
struct GroupAssignment: Hashable, Identifiable, Sendable {

  // MARK: Internal

  /// Row identity for the settings list, never encoded. Equality and
  /// hashing cover the visible fields alone, as for exclusion entries.
  let id = UUID()
  var bundleID: String
  /// The group number, 1 to 9. Kept when the group count falls below it.
  var group: Int

  static func ==(lhs: GroupAssignment, rhs: GroupAssignment) -> Bool {
    lhs.bundleID == rhs.bundleID && lhs.group == rhs.group
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(bundleID)
    hasher.combine(group)
  }

}

// MARK: - GroupingPolicy

/// How the list is grouped, as one value.
struct GroupingPolicy: Equatable, Sendable {

  var mode = GroupingMode.none
  /// Where each kind's parked section goes. A kind left out goes to the
  /// end of the list.
  var placements = [DisplaySubgroup: SubgroupPlacement]()
  /// How many manual groups there are, 1 to 9.
  var groupCount = 1
  var headingStyle = GroupHeadingStyle.number
  /// The names given to manual groups, by group number. Kept for groups
  /// past the count, so raising the count brings them back.
  var names = [Int: String]()
  /// Which manual group each application goes to, first entry winning.
  var assignments = [GroupAssignment]()

  /// Where one kind's section goes.
  func placement(of subgroup: DisplaySubgroup) -> SubgroupPlacement {
    placements[subgroup] ?? .endOfList
  }

  /// The manual group an application's rows join. An application with no
  /// bundle identifier, with no assignment, or assigned past the count
  /// joins the first group. Bundle identifiers compare without case, and
  /// the first assignment of one wins.
  func group(forBundleID bundleID: String?) -> Int {
    guard let bundleID else { return 1 }
    let folded = bundleID.lowercased()
    guard let assigned = assignments.first(where: { $0.bundleID.lowercased() == folded })?.group else {
      return 1
    }
    return (1 ... groupCount).contains(assigned) ? assigned : 1
  }

  /// The name of one manual group, or nil when it has none worth showing.
  func name(of group: Int) -> String? {
    guard let name = names[group], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return name
  }

}
