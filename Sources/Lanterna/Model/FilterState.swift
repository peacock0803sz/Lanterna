/// The memory one filtering appearance keeps: the query, the row chosen
/// when it vanished, and what matched last.
///
/// A value with no system behind it: resolving the choice is a calculation
/// over its inputs, so the whole of the rule below can be held to without a
/// panel. Made fresh for every appearance and thrown away when the panel
/// comes down; nothing carries over to the next one.
struct FilterState: Equatable, Sendable {
    /// The current query. Empty means the whole list.
    var query = ""
    /// The row chosen the moment it vanished. Updated only when a non-nil
    /// choice vanishes; moving with the arrows never updates it, and a nil
    /// choice never overwrites it.
    var rememberedID: WindowItem.Identifier?
    /// What matched last, for telling a renewed match apart from a kept one.
    var previousMatchedIDs: Set<WindowItem.Identifier> = []

    /// Appends typed text to the query.
    mutating func append(_ text: String) {
        query += text
    }

    /// Removes the last character, and does nothing when already empty.
    mutating func removeLast() {
        guard !query.isEmpty else { return }
        query.removeLast()
    }

    /// Drops the query and the memory; starting over as a fresh appearance does.
    mutating func clear() {
        query = ""
        rememberedID = nil
        previousMatchedIDs = []
    }

    /// Takes the rows a swapped-in list matches as already seen. A row a
    /// swap brings back returns with the list, not with shortening, so it
    /// does not restore the remembered row; the memory stays for a later
    /// shortening that brings it back.
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
}
