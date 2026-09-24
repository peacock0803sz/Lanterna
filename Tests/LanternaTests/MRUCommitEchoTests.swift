import AppKit
@testable import Lanterna
import Testing

/// Builds the row the echo tests sort. Local because the sibling suite keeps
/// its own builder private, and sharing one would couple the two files.
@MainActor
private func echoRow(windowID: CGWindowID, owner: pid_t) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: owner,
        appName: "SameApp",
        bundleIdentifier: nil,
        windowTitle: "Same Title",
        kind: .standard,
        isMinimized: false,
        icon: NSImage(size: NSSize(width: 1, height: 1))
    )
}

/// The commit's own echo, told apart from a genuine later move by the clock.
///
/// Switching raises the committed window last, so the activation notice that
/// follows can still find the previous window in front. Recording that
/// transient read would poison the order the commit just established; the
/// commit already named the exact row, so the echo carries nothing.
@MainActor
struct MRUCommitEchoTests {
    @Test func echoInsideTheWindowIsSkipped() {
        let clock = SteppingClock(step: .milliseconds(100))
        let tracker = MRUTracker(now: clock.read)
        let target = echoRow(windowID: 1, owner: 101)
        let passerby = echoRow(windowID: 2, owner: 101)
        tracker.record(
            target.id, ownerProcessIdentifier: target.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.noteSwitchReturned()
        recordExternalActivation(
            of: 101, excluding: 999,
            reading: FakeEchoReader(windowID: 2), into: tracker
        )
        #expect(tracker.newestSource == .commit)
        #expect(tracker.ordered([target, passerby]).map(\.id) == [target.id, passerby.id])
    }

    @Test func genuineLaterMoveIsRecorded() {
        let clock = SteppingClock(step: .milliseconds(600))
        let tracker = MRUTracker(now: clock.read)
        let target = echoRow(windowID: 1, owner: 101)
        let later = echoRow(windowID: 2, owner: 101)
        tracker.record(
            target.id, ownerProcessIdentifier: target.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.noteSwitchReturned()
        recordExternalActivation(
            of: 101, excluding: 999,
            reading: FakeEchoReader(windowID: 9), into: tracker
        )
        #expect(tracker.newestSource == .commit)
        recordExternalActivation(
            of: 101, excluding: 999,
            reading: FakeEchoReader(windowID: 2), into: tracker
        )
        #expect(tracker.newestSource == .external)
        #expect(tracker.ordered([target, later]).map(\.id) == [later.id, target.id])
    }

    @Test func otherApplicationsAreNeverEchoes() {
        let clock = SteppingClock(step: .milliseconds(100))
        let tracker = MRUTracker(now: clock.read)
        let target = echoRow(windowID: 1, owner: 101)
        let other = echoRow(windowID: 2, owner: 102)
        tracker.record(
            target.id, ownerProcessIdentifier: target.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.noteSwitchReturned()
        recordExternalActivation(
            of: 102, excluding: 999,
            reading: FakeEchoReader(windowID: 2), into: tracker
        )
        #expect(tracker.newestSource == .external)
        #expect(tracker.ordered([target, other]).map(\.id) == [other.id, target.id])
    }

    private struct FakeEchoReader: FocusedWindowReading {
        var windowID: CGWindowID?
        func focusedWindowID(of _: pid_t) -> CGWindowID? {
            windowID
        }
    }
}

/// A genuine return after a detour is never the echo.
///
/// Committing to one application, moving to another, and coming back records
/// every step: the detour retires the pending echo, so the return lands as
/// the newest use and the next panel opens on it.
@MainActor
struct MRUGenuineReturnTests {
    @Test func returnAfterDetourIsRecorded() {
        let clock = SteppingClock(step: .milliseconds(100))
        let tracker = MRUTracker(now: clock.read)
        let home = echoRow(windowID: 1, owner: 101)
        let away = echoRow(windowID: 2, owner: 102)
        tracker.record(
            home.id, ownerProcessIdentifier: home.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.noteSwitchReturned()
        recordExternalActivation(
            of: 102, excluding: 999,
            reading: FakeReturnReader(windowID: 2), into: tracker
        )
        recordExternalActivation(
            of: 101, excluding: 999,
            reading: FakeReturnReader(windowID: 1), into: tracker
        )
        #expect(tracker.newestSource == .external)
        #expect(tracker.ordered([home, away]).map(\.id) == [home.id, away.id])
    }

    private struct FakeReturnReader: FocusedWindowReading {
        var windowID: CGWindowID?
        func focusedWindowID(of _: pid_t) -> CGWindowID? {
            windowID
        }
    }
}

/// A slow switch does not spend the echo window.
///
/// The window starts when the switch returns, not when the commit ran: a
/// notice handled before that could not be the commit's own, because
/// handling anything at all means the switch is no longer holding the turn.
@MainActor
struct MRUSlowSwitchTests {
    @Test func windowStartsAtSwitchReturn() {
        let clock = SteppingClock(step: .milliseconds(100))
        let tracker = MRUTracker(now: clock.read)
        let target = echoRow(windowID: 1, owner: 101)
        tracker.record(
            target.id, ownerProcessIdentifier: target.ownerProcessIdentifier,
            origin: .commit
        )
        for _ in 0 ..< 20 {
            tracker.noteSwitchReturned()
        }
        recordExternalActivation(
            of: 101, excluding: 999,
            reading: FakeSlowReader(windowID: 2), into: tracker
        )
        #expect(tracker.newestSource == .commit)
    }

    private struct FakeSlowReader: FocusedWindowReading {
        var windowID: CGWindowID?
        func focusedWindowID(of _: pid_t) -> CGWindowID? {
            windowID
        }
    }
}
