import AppKit
import PrivateAPIs
import Synchronization
@testable import Lanterna

// MARK: - FakeReader

/// Answers from a table keyed by process identifier, so a test states what
/// each application replies and nothing else.
struct FakeReader: ApplicationWindowReading {
  init(_ reads: [pid_t: Result<ApplicationRead, ReadFailure>]) {
    self.reads = reads
  }

  let reads: [pid_t: Result<ApplicationRead, ReadFailure>]
  /// What each application was handed, shared by every copy of this reader.
  let calls = ReadCalls()

  func read(
    processIdentifier: pid_t,
    otherSpaceWindows: Set<CGWindowID>,
    isHidden: Bool
  ) -> Result<ApplicationRead, ReadFailure> {
    calls.note(processIdentifier, otherSpaceWindows: otherSpaceWindows, isHidden: isHidden)
    return reads[processIdentifier] ?? .success(ApplicationRead(records: [], droppedWithoutID: 0))
  }
}

// MARK: - ReadCalls

/// The arguments each application's read was given. A class holding a
/// `Mutex`, because the reads run concurrently and the fake reader that
/// owns it is a value.
final class ReadCalls: Sendable {

  // MARK: Internal

  struct Call: Equatable {
    let otherSpaceWindows: Set<CGWindowID>
    let isHidden: Bool
  }

  var byProcess: [pid_t: Call] {
    store.withLock { $0 }
  }

  func note(_ processIdentifier: pid_t, otherSpaceWindows: Set<CGWindowID>, isHidden: Bool) {
    store.withLock { $0[processIdentifier] = Call(otherSpaceWindows: otherSpaceWindows, isHidden: isHidden) }
  }

  // MARK: Private

  private let store = Mutex<[pid_t: Call]>([:])

}

// MARK: - FakeSpaceLocator

/// Names the windows on another Space outright, so no test asks the machine's
/// window server about ids it made up.
struct FakeSpaceLocator: SpaceLocating {
  var onOtherSpace = Set<CGWindowID>()
  var fullscreen = Set<CGWindowID>()
  /// The Spaces each window is on, and the displays' Spaces, for the
  /// passes that group by Space.
  var spaces = [CGWindowID: [CGSSpaceID]]()
  var layout: SpaceLayout?
  /// What `otherSpaceWindows()` answers.
  var otherSpace = OtherSpaceWindows()
  /// How often the other-Space list was read, shared by every copy.
  let calls = LocatorCalls()

  func otherSpaceWindows() -> OtherSpaceWindows {
    calls.noteOtherSpaceRead()
    return otherSpace
  }

  func windowsOnOtherSpaces(among windowIDs: [CGWindowID]) -> Set<CGWindowID> {
    onOtherSpace.intersection(windowIDs)
  }

  func fullscreenWindows(among windowIDs: [CGWindowID]) -> Set<CGWindowID> {
    fullscreen.intersection(windowIDs)
  }

  func reading(among windowIDs: [CGWindowID]) -> SpaceReading {
    calls.noteReading(windowIDs)
    return SpaceReading(
      onOtherSpace: windowsOnOtherSpaces(among: windowIDs),
      fullscreen: fullscreenWindows(among: windowIDs),
      spaces: spaces.filter { windowIDs.contains($0.key) },
      layout: layout
    )
  }
}

// MARK: - LocatorCalls

/// What the fake locator was asked. A class holding a `Mutex`, because it
/// is asked from a worker thread and the locator that owns it is a value.
final class LocatorCalls: Sendable {

  // MARK: Internal

  var otherSpaceReads: Int {
    store.withLock { $0.otherSpaceReads }
  }

  /// Every batch of window ids the Space reading was asked about.
  var readings: [[CGWindowID]] {
    store.withLock { $0.readings }
  }

  func noteOtherSpaceRead() {
    store.withLock { $0.otherSpaceReads += 1 }
  }

  func noteReading(_ windowIDs: [CGWindowID]) {
    store.withLock { $0.readings.append(windowIDs) }
  }

  // MARK: Private

  private struct Record {
    var otherSpaceReads = 0
    var readings = [[CGWindowID]]()
  }

  private let store = Mutex(Record())

}

/// The fixtures sit in a file of their own so every enumerator suite can
/// reach them, which is also what keeps each suite's file inside the length
/// the linter allows.
@MainActor
func application(
  _ processIdentifier: pid_t,
  name: String = "Finder",
  isHidden: Bool = false
) -> RunningApplicationInfo {
  RunningApplicationInfo(
    processIdentifier: processIdentifier,
    name: name,
    bundleIdentifier: nil,
    isHidden: isHidden,
    icon: NSImage()
  )
}

func record(
  _ windowID: CGWindowID,
  title: String = "Downloads",
  kind: WindowKind = .standard,
  isMinimized: Bool = false,
  isFullscreen: Bool = false
) -> WindowRecord {
  WindowRecord(windowID: windowID, title: title, kind: kind, isMinimized: isMinimized, isFullscreen: isFullscreen)
}

func read(
  _ records: [WindowRecord],
  droppedWithoutID: Int = 0,
  otherSpacesCutShort: Bool = false
) -> Result<ApplicationRead, ReadFailure> {
  .success(ApplicationRead(
    records: records,
    droppedWithoutID: droppedWithoutID,
    otherSpacesCutShort: otherSpacesCutShort
  ))
}
