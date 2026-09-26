@testable import Lanterna
import Testing

struct WindowOperationTests {
    @Test func theFourOperationsAreDistinct() {
        let operations: [WindowOperation] = [
            .closeWindow, .quitApplication, .hideApplication, .minimizeWindow,
        ]
        #expect(Set(operations).count == 4)
    }

    @Test func eachOperationHasItsLogName() {
        #expect(WindowOperation.closeWindow.logName == "close")
        #expect(WindowOperation.quitApplication.logName == "quit")
        #expect(WindowOperation.hideApplication.logName == "hide")
        #expect(WindowOperation.minimizeWindow.logName == "minimize")
    }

    @Test func failuresReuseTheActivationVocabulary() {
        #expect(OperationOutcome.failed(.windowGone) == .failed(.windowGone))
        #expect(OperationOutcome.failed(.windowGone) != .failed(.applicationGone))
        #expect(OperationOutcome.done != .failed(.windowGone))
        #expect(OperationOutcome.interrupted != .done)
    }
}
