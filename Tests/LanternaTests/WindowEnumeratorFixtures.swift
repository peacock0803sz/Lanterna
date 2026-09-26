import AppKit
@testable import Lanterna

/// Answers from a table keyed by process identifier, so a test states what
/// each application replies and nothing else.
struct FakeReader: ApplicationWindowReading {
    let reads: [pid_t: Result<ApplicationRead, ReadFailure>]

    init(_ reads: [pid_t: Result<ApplicationRead, ReadFailure>]) {
        self.reads = reads
    }

    func read(processIdentifier: pid_t) -> Result<ApplicationRead, ReadFailure> {
        reads[processIdentifier] ?? .success(ApplicationRead(records: [], droppedWithoutID: 0))
    }
}

/// Names the windows on another Space outright, so no test asks the machine's
/// window server about ids it made up.
struct FakeSpaceLocator: SpaceLocating {
    var onOtherSpace: Set<CGWindowID> = []
    var fullscreen: Set<CGWindowID> = []

    func windowsOnOtherSpaces(among windowIDs: [CGWindowID]) -> Set<CGWindowID> {
        onOtherSpace.intersection(windowIDs)
    }

    func fullscreenWindows(among windowIDs: [CGWindowID]) -> Set<CGWindowID> {
        fullscreen.intersection(windowIDs)
    }
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
    droppedWithoutID: Int = 0
) -> Result<ApplicationRead, ReadFailure> {
    .success(ApplicationRead(records: records, droppedWithoutID: droppedWithoutID))
}
