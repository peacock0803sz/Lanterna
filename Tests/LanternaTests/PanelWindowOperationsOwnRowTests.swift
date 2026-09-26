@testable import Lanterna
import Testing

/// The process's own row is never a target, whichever operation is asked.
@MainActor
struct PanelWindowOperationsOwnRowTests {
    /// The process's own row is out of scope for every operation: nothing
    /// is sent, and no line says anything.
    @Test(arguments: WindowOperation.allCases)
    func theOwnRowIsLeftAlone(operation: WindowOperation) async {
        let own = operationRow(appName: "Lanterna", windowTitle: "Panel", windowID: 9, pid: 999)
        let sent = SentCount()
        let made = makeOperations(
            rows: [own],
            refreshed: [own],
            close: { _ in
                sent.add()
                return nil
            },
            quit: { _ in
                sent.add()
                return nil
            },
            hide: { _ in
                sent.add()
                return nil
            },
            minimize: { _ in
                sent.add()
                return nil
            },
            ownProcessIdentifier: 999
        )
        await made.operations.operate(operation, naming: own.id)
        #expect(sent.value == 0)
        #expect(made.surface.updatedLists.isEmpty)
        #expect(made.log.lines.isEmpty)
    }
}
