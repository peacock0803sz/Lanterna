/// Which row the panel that is up is drawing as chosen, and the one way it
/// moves.
///
/// The single place that question is answered, which is the whole point of
/// the type. The row used to be arrived at twice — the view took the first of
/// whatever list it was handed, and the presenter kept the names off the same
/// first row — and the two agreed only because nothing could move the choice.
/// A keyboard that moves it is exactly what turns two derivations of one
/// thing into two answers.
///
/// Distinct from `SelectionCursor`, which is the arithmetic: a value that
/// knows an order of identities and how to step through it, with no panel
/// behind it and nothing to redraw. This is that value and the panel it is
/// drawn on, kept together so that no caller can move one without the other
/// following.
@MainActor
final class PanelSelection {
    private let surface: any SwitcherSurface

    /// `nil` exactly when no panel is up. An empty list is not that case: it
    /// is a cursor with nothing to choose, which answers a keystroke by
    /// leaving the choice where it is rather than by having no answer.
    private var cursor: SelectionCursor?

    init(surface: any SwitcherSurface) {
        self.surface = surface
    }

    /// The chosen row, or nothing when no panel is up or the list is empty.
    var chosenID: WindowItem.Identifier? {
        cursor?.selectedID
    }

    /// Opens the choice on the second row of a list that is about to go up.
    ///
    /// The first row is the window already in front, so choosing it without
    /// moving would take the user nowhere they are not. One row keeps its
    /// first, and an empty list is a cursor with nothing to choose, as
    /// before. With no records yet the order is the fixed one and the
    /// second row may not be the previously used window; that is the
    /// specified cold-start behaviour, corrected by the first activation
    /// or commit. Determining the frontmost window here would cost an
    /// accessibility read inside the show span, so it is deliberately
    /// not done. The row is the same for forward and reverse openings:
    /// reverse presses walk back from here. A stale first row from a
    /// recorded switch that never landed still leaves this choice, which
    /// no focus read here could tell apart.
    ///
    /// Tells the panel nothing, because there is no panel yet: the chosen row
    /// travels with the list in the call that puts one there, and a redraw
    /// before that would be a redraw of nothing.
    func beginSecond(_ ids: [WindowItem.Identifier]) {
        var opened = SelectionCursor(ids: ids)
        opened.selectSecond()
        cursor = opened
    }

    /// Gives up the choice, which has no meaning once the panel is down.
    func end() {
        cursor = nil
    }

    func moveToNext() {
        move { $0.moveToNext() }
    }

    func moveToPrevious() {
        move { $0.moveToPrevious() }
    }

    /// Moves the choice and tells the panel, and does nothing else.
    ///
    /// Nothing is written down. Moving the choice is the one thing a user
    /// does many times over in a single appearance, and a line for each would
    /// bury the lines saying what became of the panel under lines saying
    /// somebody was still looking.
    ///
    /// The panel is told through the entry that only redraws. The entry that
    /// takes a list resizes the window and puts it back in the centre of the
    /// display, and a panel that jumped as the choice moved would be one the
    /// eye has to find again on every keystroke.
    ///
    /// A list of one row and a list of none are not cases here. The cursor
    /// answers both by leaving the choice where it is, so the panel is told
    /// the row it was already drawing — which is the honest report that a
    /// press arrived and moved nothing.
    private func move(_ step: (inout SelectionCursor) -> Void) {
        guard var moved = cursor else { return }
        step(&moved)
        cursor = moved
        surface.showSelection(moved.selectedID)
    }
}
