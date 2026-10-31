// MARK: - FilterOrigin

/// How the filter in an open panel was started.
///
/// The way in decides two things the query alone cannot: whether letting
/// go of the held key commits, and how the selection follows the query.
enum FilterOrigin: Equatable, Sendable {
  /// Asked for by its own key, such as Command-Space or S. The user chose
  /// to search, so letting go keeps the panel up.
  case invoked
  /// Started by typing a letter in a panel opened with a switcher key.
  /// The key is still held, so letting go commits as it would have.
  case typed
  /// Started by holding a Fast Search key and typing, with no panel up
  /// before the first letter. Letting go of that key commits.
  case fastSearch

  // MARK: Internal

  /// Whether letting go of the held key takes the selected row.
  ///
  /// Such a filter also starts each new query from the best match other
  /// than the window already in front, since the user is on the way out.
  var commitsOnRelease: Bool {
    self != .invoked
  }
}
