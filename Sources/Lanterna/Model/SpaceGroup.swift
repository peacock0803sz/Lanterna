// MARK: - SpaceGroup

/// The Space group one row belongs to when the list groups by Space.
///
/// Worked out when the list is read, where the displays and Spaces are
/// known, and carried on the row so laying the list out needs nothing
/// else. Rows with the same order share a group.
struct SpaceGroup: Hashable, Sendable {
  /// Where the group draws: shown Spaces first, then the rest.
  let order: Int
  let title: String
  let detail: String?
}
