import CoreGraphics
@testable import Lanterna
import Testing

/// Identities made by hand rather than taken off `SampleWindows`, because
/// nothing here needs a row to look like anything: the cursor is given
/// identities and hands one back. Built without AppKit for the same reason the
/// cursor holds no items.
private func ids(_ count: Int) -> [WindowItem.Identifier] {
    (0 ..< count).map { WindowItem.Identifier(windowID: CGWindowID(1 + $0)) }
}

struct SelectionCursorTests {
    @Test func theFirstRowIsChosenToBeginWith() {
        let rows = ids(4)
        #expect(SelectionCursor(ids: rows).selectedID == rows[0])
    }

    @Test func anEmptyListHasNothingChosen() {
        #expect(SelectionCursor(ids: []).selectedID == nil)
    }

    /// Moving over an empty list is not an error and not a special case; it is
    /// simply nothing happening. The panel can be up with no rows in it, and
    /// the arrow keys still arrive.
    @Test func anEmptyListStaysEmptyHoweverItIsMoved() {
        var cursor = SelectionCursor(ids: [])
        cursor.moveToNext()
        #expect(cursor.selectedID == nil)
        cursor.moveToPrevious()
        #expect(cursor.selectedID == nil)
    }

    @Test func oneRowIsAlwaysTheChosenRow() {
        let rows = ids(1)
        var cursor = SelectionCursor(ids: rows)
        cursor.moveToNext()
        #expect(cursor.selectedID == rows[0])
        cursor.moveToPrevious()
        #expect(cursor.selectedID == rows[0])
    }

    @Test func movingOnGoesExactlyOneRow() {
        let rows = ids(5)
        var cursor = SelectionCursor(ids: rows)
        cursor.moveToNext()
        #expect(cursor.selectedID == rows[1])
        cursor.moveToNext()
        #expect(cursor.selectedID == rows[2])
    }

    /// Said of going back as well as of going on, rather than left to the
    /// wrapping cases below. Wrapping alone cannot tell a step of one from a
    /// step of two: off the first row both land somewhere near the end. Going
    /// back exactly one row is its own promise.
    @Test func movingBackGoesExactlyOneRow() {
        let rows = ids(5)
        var cursor = SelectionCursor(ids: rows)
        cursor.moveToNext()
        cursor.moveToNext()
        cursor.moveToPrevious()
        #expect(cursor.selectedID == rows[1])
    }

    @Test func movingOnFromTheLastRowWrapsToTheFirst() {
        let rows = ids(3)
        var cursor = SelectionCursor(ids: rows)
        cursor.moveToNext()
        cursor.moveToNext()
        #expect(cursor.selectedID == rows[2])
        cursor.moveToNext()
        #expect(cursor.selectedID == rows[0])
    }

    @Test func movingBackFromTheFirstRowWrapsToTheLast() {
        let rows = ids(3)
        var cursor = SelectionCursor(ids: rows)
        cursor.moveToPrevious()
        #expect(cursor.selectedID == rows[2])
    }
}
