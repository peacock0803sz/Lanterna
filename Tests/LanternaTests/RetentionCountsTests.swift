@testable import Lanterna
import Testing

/// The diagnostics read every retained thing's number in one place.
@MainActor
struct RetentionCountsTests {

  @Test
  func theSnapshotReadsTheOwnersNumbers() {
    let state = LogWindowState(readEntries: { [] })
    state.currentRows = LogFixture.entries(count: 3).map(LogRow.init(entry:))
    state.pendingRows = [LogRow(entry: LogFixture.entry(sequence: 9))]
    state.savedLogsBytesRead = 4096
    let snapshot = RetentionCounts.snapshot(
      logState: state,
      shortcutMemoryCount: 7,
      shortcutMemoryLimit: 256,
      mruRecordCount: 5,
      mruApplicationCount: 2,
      iconCount: 11,
      mirrorCount: 9
    )
    #expect(snapshot.liveRows == 3)
    #expect(snapshot.liveRowsLimit == DiagnosticLog.capacity)
    #expect(snapshot.waitingRows == 1)
    #expect(snapshot.waitingRowsLimit == DiagnosticLog.capacity)
    #expect(snapshot.logPaused == false)
    #expect(snapshot.savedBytes == 4096)
    #expect(snapshot.savedBytesLimit == LaunchLogStore.readByteLimit)
    #expect(snapshot.shortcutCount == 7)
    #expect(snapshot.shortcutLimit == 256)
    #expect(snapshot.iconCount == 11)
    #expect(snapshot.mruRecords == 5)
    #expect(snapshot.mruApplications == 2)
    #expect(snapshot.mirrorRows == 9)
    #expect(snapshot.mirrorRowsLimit == DiagnosticLog.capacity)
  }

  @Test
  func forgettingTheOlderRowsClearsTheSavedBytes() {
    let state = LogWindowState(readEntries: { [] })
    state.olderRows = [LogRow(separatorFor: LogFixture.launch)]
    state.savedLogsBytesRead = 512
    state.invalidateSavedLaunches()
    let snapshot = RetentionCounts.snapshot(
      logState: state,
      shortcutMemoryCount: 0,
      shortcutMemoryLimit: 256,
      mruRecordCount: 0,
      mruApplicationCount: 0,
      iconCount: 0,
      mirrorCount: 0
    )
    #expect(snapshot.savedBytes == 0)
  }

}
