/// The memory one filtering appearance keeps: the query, the row chosen
/// when it vanished, and what matched last.
///
/// A value with no system behind it: resolving the choice is a calculation
/// over its inputs, so the whole of the rule below can be held to without a
/// panel. Made fresh for every appearance and thrown away when the panel
/// comes down; nothing carries over to the next one.
struct FilterState: Equatable, Sendable {
  /// The query with its insertion point. Fresh appearances start empty
  /// with the point at the start; closing the panel throws it away.
  var line = QueryText()
  /// The row chosen the moment it vanished. Updated only when a non-nil
  /// choice vanishes; moving with the arrows never updates it, and a nil
  /// choice never overwrites it.
  var rememberedID: WindowItem.Identifier?
  /// What matched last, for telling a renewed match apart from a kept one.
  var previousMatchedIDs = Set<WindowItem.Identifier>()
  /// The row first in use order when the appearance began, which is the
  /// window already in front. A filter that commits on release steps
  /// past it, since switching to it would change nothing.
  var frontID: WindowItem.Identifier?

  /// The current query. Empty means the whole list. Read off the line:
  /// the insertion point lives there, not here.
  var query: String {
    line.text
  }

  /// Drops the query and the memory; starting over as a fresh appearance does.
  mutating func clear() {
    line = QueryText()
    rememberedID = nil
    previousMatchedIDs = []
  }

  /// Takes the rows a swapped-in list matches as already seen. A row a
  /// swap brings back returns with the list, not with shortening, so it
  /// does not restore the remembered row, and being seen, a shortening
  /// restores it only after a query hides it again. Leaves the memory
  /// alone: a remembered row the query still hides after the swap is
  /// restored by the shortening that brings it back, unless the chosen
  /// row no longer matches when the swapped list is resolved, and that
  /// row then takes the remembered row's place in the memory (see
  /// `resolveSelection`).
  mutating func takeSwappedIn(matched: [WindowItem.Identifier]) {
    previousMatchedIDs = Set(matched)
  }

  /// Resolves which row the narrowed list chooses.
  ///
  /// Remembers the incoming choice exactly when a row that was chosen is
  /// gone, restores the remembered row exactly when shortening brings it
  /// back, otherwise keeps the incoming choice while it still matches and
  /// falls back to the first match. An empty match chooses nothing.
  mutating func resolveSelection(
    matched: [WindowItem.Identifier],
    incoming: WindowItem.Identifier?
  ) -> WindowItem.Identifier? {
    let matchedSet = Set(matched)
    if let incoming, !matchedSet.contains(incoming) {
      rememberedID = incoming
    }
    defer { previousMatchedIDs = matchedSet }
    let renews = rememberedID.map { matchedSet.contains($0) && !previousMatchedIDs.contains($0) } ?? false
    if let rememberedID, renews {
      return rememberedID
    }
    if let incoming, matchedSet.contains(incoming) {
      return incoming
    }
    return matched.first
  }

  /// Resolves the choice for a filter that commits on release, after the
  /// query changed: the best match other than the front row, or the front
  /// row when nothing else matches.
  ///
  /// Neither a choice moved by hand nor the remembered row survives a
  /// change of query. Letting go commits, so the row chosen is the one
  /// the query asks for now, not one picked for an earlier query.
  mutating func resolveLeavingFront(matched: [WindowItem.Identifier]) -> WindowItem.Identifier? {
    previousMatchedIDs = Set(matched)
    return matched.first { $0 != frontID } ?? matched.first
  }
}
