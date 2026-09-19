/// Which row of the list the panel is showing as chosen.
///
/// A value with one job, and nothing behind it: no window server, no AppKit,
/// no clock. Moving the selection is the part of this feature that has the
/// most to say and the least to do with the system, and keeping it here is
/// what lets all of it be checked without any of them.
struct SelectionCursor: Equatable, Sendable {
    /// The rows on screen, in the order they are drawn.
    ///
    /// Identities and not the items themselves. A `WindowItem` carries an
    /// `NSImage`, which is neither `Equatable` nor `Sendable`, so a cursor
    /// holding items could be neither either. What a row looks like is the
    /// panel's business, and the panel already holds the list to look it up
    /// in.
    ///
    /// Given once and never written again: the list a panel is showing does
    /// not change while it is up.
    private let ids: [WindowItem.Identifier]

    /// The chosen row, or nothing when there are no rows at all.
    ///
    /// An identity rather than a position. A position is no more an identity
    /// than a title is — both say where a row is or what it reads as, and
    /// neither says which window it is. Either would be enough while the list
    /// stands still, and neither is what the panel promises. With
    /// `--sample-count 18` the seventeen sample templates come round once, so
    /// two rows agree on both the application name and the window title; the
    /// window-server id is the only thing that still tells them apart.
    private(set) var selectedID: WindowItem.Identifier?

    /// Opens on the first row, which is the one the panel drew as chosen
    /// before anything could move the choice.
    init(ids: [WindowItem.Identifier]) {
        self.ids = ids
        selectedID = ids.first
    }

    mutating func moveToNext() {
        move(by: 1)
    }

    mutating func moveToPrevious() {
        move(by: -1)
    }

    /// Steps one row and wraps at both ends.
    ///
    /// The remainder is taken of `current + step + count` rather than of
    /// `current + step`, because Swift's remainder keeps the sign of the left
    /// operand: stepping back off the first row would otherwise index by -1.
    ///
    /// An empty list has no chosen row and so no step to take, and a list of
    /// one wraps straight back onto itself. Neither is a case of its own here;
    /// both fall out of the arithmetic, which is why neither can drift from
    /// it.
    private mutating func move(by step: Int) {
        guard let current = selectedID.flatMap(ids.firstIndex(of:)) else { return }
        selectedID = ids[(current + step + ids.count) % ids.count]
    }
}
