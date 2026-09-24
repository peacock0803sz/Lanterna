import ApplicationServices
@testable import Lanterna
import Testing

/// The focused-window reader on its own: what each answer means, without any
/// tracker behind it.
///
/// A file of its own because the seam suite it would have joined is already
/// long enough that adding to it would put it over the file limit.
@MainActor
struct FocusedWindowReaderTests {
    @Test func liveReaderReportsTheFocusedWindowID() {
        let reader = AXFocusedWindowReader(
            setMessagingTimeout: { _, _ in .success },
            copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
            copyWindowID: { _ in (.success, 7) }
        )
        #expect(reader.focusedWindowID(of: 102) == 7)
    }

    @Test func liveReaderFailuresReadAsNothing() {
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .failure },
                copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
                copyWindowID: { _ in (.success, 7) }
            ).focusedWindowID(of: 102) == nil
        )
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .success },
                copyFocusedWindow: { _ in (.cannotComplete, nil) },
                copyWindowID: { _ in (.success, 7) }
            ).focusedWindowID(of: 102) == nil
        )
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .success },
                copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
                copyWindowID: { _ in (.failure, 0) }
            ).focusedWindowID(of: 102) == nil
        )
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .success },
                copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
                copyWindowID: { _ in (.success, 0) }
            ).focusedWindowID(of: 102) == nil
        )
    }

    /// The timeout rides with the element it protects: refusing it on the
    /// focused element reads as nothing, rather than sending the id fetch
    /// on the multi-second default.
    @Test func refusedTimeoutOnTheFocusedElementReadsAsNothing() {
        let timeouts = TimeoutCalls()
        let reader = AXFocusedWindowReader(
            setMessagingTimeout: { _, _ in timeouts.install() },
            copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
            copyWindowID: { _ in (.success, 7) }
        )
        #expect(reader.focusedWindowID(of: 102) == nil)
        #expect(timeouts.count == 2)
    }

    /// Counts timeout installations, so the test can refuse the focused one.
    /// Test-only confinement: built, read, and discarded on the main actor.
    private final class TimeoutCalls: @unchecked Sendable {
        private(set) var count = 0
        func install() -> AXError {
            count += 1
            return count == 1 ? .success : .failure
        }
    }
}
