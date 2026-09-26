import Foundation
@testable import Lanterna
import Testing

/// Counts the requests a scripted sender was asked to make. Locked, since
/// the senders are called through `@Sendable` closures.
private final class SentCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func add() {
        lock.withLock { count += 1 }
    }
}

/// An operation outlives the keystroke that started it: its reconciling
/// waits for a fresh list, and the panel can go, or a later one come up,
/// before that list arrives.
@MainActor
struct PanelWindowOperationsLifetimeTests {
    private var rows: [WindowItem] {
        [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1),
            operationRow(appName: "Safari", windowTitle: "Downloads", windowID: 2),
            operationRow(appName: "Finder", windowTitle: "AirDrop", windowID: 3),
        ]
    }

    /// The panel going while the list is awaited leaves the resumed
    /// reconciling touching nothing: no list swapped in, no choice made
    /// again, no closing, and one line saying it went unreconciled.
    @Test func aPanelGoneMidReconcilingIsLeftAlone() async {
        let rows = rows
        let held = HeldRefresh()
        let made = makeOperations(rows: rows, held: held)
        let running = made.operations.start(.closeWindow, naming: rows[0].id)
        await held.waitUntilAsked()
        made.operations.end()
        made.selection.end()
        made.filter.reset()
        let swapsBefore = made.surface.updatedLists.count
        held.finish(with: Array(rows.dropFirst()))
        await running?.value
        #expect(made.surface.updatedLists.count == swapsBefore)
        #expect(made.selection.chosenID == nil)
        #expect(made.counts.interruptions == 0)
        #expect(made.counts.emptied == 0)
        #expect(made.log.lines.contains { $0.contains("window operation left unreconciled (close Safari/Tabs") })
        #expect(!made.log.lines.contains { $0.contains("window operation (close") })
    }

    /// A later appearance up by the time the list arrives is not the one
    /// the operation set out in, and its rows and choice stay its own.
    @Test func aLaterAppearanceIsLeftAlone() async {
        let rows = rows
        let held = HeldRefresh()
        let made = makeOperations(rows: rows, held: held)
        let running = made.operations.start(.closeWindow, naming: rows[0].id)
        await held.waitUntilAsked()
        made.operations.end()
        let later = [rows[2], rows[1]]
        made.selection.beginSecond(later.map(\.id))
        made.filter.begin(fullWindows: later)
        made.operations.begin(windows: later)
        let swapsBefore = made.surface.updatedLists.count
        held.finish(with: [rows[2]])
        await running?.value
        #expect(made.surface.updatedLists.count == swapsBefore)
        #expect(made.selection.chosenID == rows[1].id)
        #expect(made.counts.interruptions == 0)
    }

    /// A second operation while one is still reconciling is dropped with a
    /// line rather than sent: only the first reaches its application.
    @Test func aSecondOperationWhileOneRunsIsDropped() async {
        let rows = rows
        let held = HeldRefresh()
        let made = makeOperations(rows: rows, held: held)
        let running = made.operations.start(.closeWindow, naming: rows[0].id)
        await held.waitUntilAsked()
        await made.operations.operate(.closeWindow, naming: rows[1].id)
        #expect(made.log.lines.contains { $0.contains("window operation dropped (close") })
        held.finish(with: Array(rows.dropFirst()))
        await running?.value
        #expect(held.askedCount == 1)
        #expect(made.log.lines.contains { $0.contains("window operation (close Safari/Tabs)") })
        #expect(!made.log.lines.contains { $0.contains("Safari/Downloads") })
    }

    /// An operation whose task first runs after its appearance has gone,
    /// and a later one come up, sends nothing: the row it named was chosen
    /// off a list the later appearance never showed.
    @Test func anOperationStartedInAnEndedAppearanceSendsNothing() async {
        let rows = rows
        let closes = SentCount()
        let made = makeOperations(rows: rows, close: { _ in
            closes.add()
            return nil
        })
        let running = made.operations.start(.closeWindow, naming: rows[0].id)
        made.operations.end()
        made.operations.begin(windows: rows)
        await running?.value
        #expect(closes.value == 0)
        #expect(made.surface.updatedLists.isEmpty)
    }

    /// An operation that has ended, whether reconciled or wound back after
    /// sending failed, leaves the appearance free for the next one.
    @Test(arguments: [false, true])
    func theNextOperationRunsAfterOneEnds(failing: Bool) async {
        let rows = rows
        let made = makeOperations(rows: rows, refreshed: [rows[2]], close: { _ in failing ? .windowGone : nil })
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        await made.operations.operate(.closeWindow, naming: rows[2].id)
        #expect(!made.log.lines.contains { $0.contains("window operation dropped") })
        #expect(made.log.lines.contains { $0.contains("Finder/AirDrop") })
    }

    /// An operation that found nothing to act on leaves the appearance
    /// free for the next one too.
    @Test func theNextOperationRunsAfterOneOutOfScope() async {
        let rows = rows
        let made = makeOperations(rows: rows, refreshed: [rows[1], rows[2]])
        await made.operations.operate(.minimizeWindow, naming: nil)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(!made.log.lines.contains { $0.contains("window operation dropped") })
        #expect(made.log.lines.contains { $0.contains("window operation (close Safari/Tabs)") })
    }
}
